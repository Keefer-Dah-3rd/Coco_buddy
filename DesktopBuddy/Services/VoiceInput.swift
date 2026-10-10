import AVFoundation
import Observation
import Speech

/// Push-to-talk transcription with Apple's Speech framework.
///
/// The microphone is only open between `start()` and the end of the utterance —
/// it stops on its own after a short silence, after 30 seconds, or when tapped
/// again. Recognition runs on this Mac whenever the language supports it; if it
/// can't, `isOnDevice` is false and the UI says so.
@Observable
final class VoiceInput {
    enum Status: Equatable {
        case idle
        case starting
        case listening
        /// Permission is off; the message says where to turn it on.
        case denied(String)
        case unavailable(String)
    }

    private(set) var status: Status = .idle
    /// Live transcript while listening.
    private(set) var transcript = ""
    /// False when audio is sent to Apple's speech service instead of staying on this Mac.
    private(set) var isOnDevice = true
    @ObservationIgnored var onFinish: ((String) -> Void)?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var limitTimer: Timer?
    @ObservationIgnored private var completed = true

    var isListening: Bool { status == .starting || status == .listening }

    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let speechSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!

    func start() async {
        guard !isListening else { return }
        status = .starting
        transcript = ""

        guard await Self.speechRecognitionAllowed() else {
            status = .denied("Speech recognition is off for Desktop Buddy. Turn it on in System Settings › Privacy & Security › Speech Recognition.")
            return
        }
        guard await Self.microphoneAllowed() else {
            status = .denied("Microphone access is off for Desktop Buddy. Turn it on in System Settings › Privacy & Security › Microphone.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            status = .unavailable("Speech recognition isn't available right now.")
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        isOnDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = isOnDevice

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            status = .unavailable("No microphone is available.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            status = .unavailable("Couldn't start the microphone.")
            return
        }

        self.engine = engine
        self.request = request
        completed = false
        recognition = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
        status = .listening
        limitTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
        // Give people a moment to start talking before treating quiet as "done".
        restartSilenceTimer(after: 6)
    }

    /// Stops listening and delivers what was heard.
    func finish() {
        guard !completed else { return }
        stopAudio()
        request?.endAudio()
        // The final result usually arrives within a moment; don't wait forever for it.
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            complete()
        }
    }

    /// Stops listening and throws away what was heard.
    func cancel() {
        guard !completed else { return }
        completed = true
        stopAudio()
        recognition?.cancel()
        reset()
        status = .idle
    }

    func clearProblem() {
        if !isListening { status = .idle }
    }

    // MARK: - Private

    private func received(_ text: String?, isFinal: Bool, failed: Bool) {
        guard !completed else { return }
        if let text, text != transcript {
            transcript = text
            restartSilenceTimer(after: 1.6)
        }
        if isFinal || failed {
            stopAudio()
            complete()
        }
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        recognition?.cancel()
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        reset()
        status = .idle
        onFinish?(heard)
    }

    private func restartSilenceTimer(after interval: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    private func stopAudio() {
        silenceTimer?.invalidate()
        limitTimer?.invalidate()
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
    }

    private func reset() {
        recognition = nil
        request = nil
    }

    // The audio tap and recognition callbacks run on background threads, so they're
    // built outside the main actor and only hop back with plain values.

    nonisolated private static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in request.append(buffer) }
    }

    nonisolated private static func resultHandler(for input: VoiceInput) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in input.received(text, isFinal: isFinal, failed: failed) }
        }
    }

    nonisolated private static func speechRecognitionAllowed() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }

    nonisolated private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }
}
