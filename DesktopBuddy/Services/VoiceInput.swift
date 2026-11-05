import AVFoundation
import Observation
import os
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

    /// Why listening failed, so the panel can link the right settings and Coco can say the right thing.
    enum Problem: Equatable {
        case speechPermission
        case microphonePermission
        case speechUnavailable
        /// No input device, or it wouldn't start.
        case noMicrophone
        /// The input is a laptop's built-in mic and the lid is shut, which switches it off.
        case lidClosed
        /// The mic opened but sent nothing but silence.
        case silentMicrophone
    }

    private(set) var status: Status = .idle
    /// Live transcript while listening.
    private(set) var transcript = ""
    /// False when audio is sent to Apple's speech service instead of staying on this Mac.
    private(set) var isOnDevice = true
    /// Set while `status` is `.denied` or `.unavailable`.
    private(set) var problem: Problem?
    @ObservationIgnored var onFinish: ((String) -> Void)?
    /// Called when listening can't start, or when it turns out the mic heard only silence.
    @ObservationIgnored var onProblem: ((Problem) -> Void)?

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognition: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTimer: Timer?
    @ObservationIgnored private var limitTimer: Timer?
    @ObservationIgnored private var completed = true
    /// Bumped by every `start()`, so a late callback or delayed stop from an earlier
    /// session can't end (or leave the mic running under) the current one.
    @ObservationIgnored private var session = 0
    @ObservationIgnored private var meter = LevelMeter()
    @ObservationIgnored private var microphone: MicrophoneCheck.Input?
    @ObservationIgnored private var listeningSince: Date?
    @ObservationIgnored private var listenedFor: TimeInterval = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "voice")

    var isListening: Bool { status == .starting || status == .listening }

    static let microphoneSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    static let speechSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    static let soundSettingsURL = URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!

    /// Where the current problem can be fixed, if anywhere.
    var settingsURL: URL? {
        switch problem {
        case .speechPermission: Self.speechSettingsURL
        case .microphonePermission: Self.microphoneSettingsURL
        case .noMicrophone, .lidClosed, .silentMicrophone: Self.soundSettingsURL
        case .speechUnavailable, nil: nil
        }
    }

    func start() async {
        guard !isListening else { return }
        session += 1
        let session = session
        status = .starting
        problem = nil
        transcript = ""

        guard await Self.speechRecognitionAllowed() else {
            fail(.speechPermission, .denied("Speech recognition is off for Coco. Turn it on in System Settings › Privacy & Security › Speech Recognition."))
            return
        }
        guard await Self.microphoneAllowed() else {
            fail(.microphonePermission, .denied("Microphone access is off for Coco. Turn it on in System Settings › Privacy & Security › Microphone."))
            return
        }
        guard let microphone = MicrophoneCheck.defaultInput() else {
            fail(.noMicrophone, .unavailable("No microphone is available. Connect one, or choose one in System Settings › Sound › Input."))
            return
        }
        // Docked with the lid shut, the built-in mic records nothing — say so before listening to silence.
        if microphone.isBuiltIn, MicrophoneCheck.isLidClosed() {
            log.notice("not listening: lid closed and the input is \(microphone.name, privacy: .public)")
            fail(.lidClosed, .unavailable("Your Mac's lid is closed, which switches off its built-in microphone. Open the lid, or choose another microphone in System Settings › Sound › Input."))
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            fail(.speechUnavailable, .unavailable("Speech recognition isn't available right now."))
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
            fail(.noMicrophone, .unavailable("No microphone is available. Connect one, or choose one in System Settings › Sound › Input."))
            return
        }
        let meter = LevelMeter()
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tap(appendingTo: request, meter: meter))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            fail(.noMicrophone, .unavailable("Couldn't start the microphone (\(microphone.name))."))
            return
        }

        self.engine = engine
        self.request = request
        self.meter = meter
        self.microphone = microphone
        listeningSince = .now
        listenedFor = 0
        completed = false
        recognition = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self, session: session))
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
        let session = session
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            // A new session may have started meanwhile; this stop belongs to the old one.
            guard self.session == session else { return }
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
        guard !isListening else { return }
        status = .idle
        problem = nil
    }

    #if DEBUG
    /// Snapshots only: shows a state without opening the mic.
    func preview(_ status: Status, transcript: String = "", problem: Problem? = nil) {
        self.status = status
        self.transcript = transcript
        self.problem = problem
    }
    #endif

    // MARK: - Private

    private func fail(_ problem: Problem, _ status: Status) {
        self.problem = problem
        self.status = status
        onProblem?(problem)
    }

    private func received(_ text: String?, isFinal: Bool, failed: Bool, session: Int) {
        guard session == self.session, !completed else { return }
        if let text, text != transcript {
            transcript = text
            restartSilenceTimer(after: 1.6)
        }
        if isFinal || failed {
            complete()
        }
    }

    private func complete() {
        guard !completed else { return }
        completed = true
        stopAudio()
        recognition?.cancel()
        let heard = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let reading = meter.reading
        let decibels = reading.peak > 0 ? 20 * log10(reading.peak) : -.infinity
        log.notice("""
            listening ended: \(self.listenedFor, format: .fixed(precision: 1)) s, \
            \(reading.seconds, format: .fixed(precision: 1)) s of audio, peak \(decibels, format: .fixed(precision: 0)) dBFS, \
            heard \(heard.count) characters, input \(self.microphone?.name ?? "?", privacy: .public)
            """)
        reset()
        if heard.isEmpty, LevelMeter.isSilent(reading, listenedFor: listenedFor) {
            let name = microphone.map { "“\($0.name)”" } ?? "the microphone"
            fail(.silentMicrophone, .unavailable("No sound came through from \(name) — it may be muted or switched off. Choose another microphone in System Settings › Sound › Input."))
            return
        }
        status = .idle
        onFinish?(heard)
    }

    private func restartSilenceTimer(after interval: TimeInterval) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish() }
        }
    }

    /// Closes the mic. Safe to call more than once.
    private func stopAudio() {
        silenceTimer?.invalidate()
        limitTimer?.invalidate()
        guard let engine else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        self.engine = nil
        if let listeningSince { listenedFor = Date.now.timeIntervalSince(listeningSince) }
    }

    private func reset() {
        recognition = nil
        request = nil
    }

    // The audio tap and recognition callbacks run on background threads, so they're
    // built outside the main actor and only hop back with plain values.

    nonisolated private static func tap(appendingTo request: SFSpeechAudioBufferRecognitionRequest,
                                        meter: LevelMeter) -> AVAudioNodeTapBlock {
        nonisolated(unsafe) let request = request
        return { buffer, _ in
            meter.record(buffer)
            request.append(buffer)
        }
    }

    nonisolated private static func resultHandler(for input: VoiceInput, session: Int) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in input.received(text, isFinal: isFinal, failed: failed, session: session) }
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
