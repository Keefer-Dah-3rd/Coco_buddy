import AVFoundation
import Observation

/// Speaks Coco's lines with the system speech synthesizer — offline, no account,
/// no data leaves the Mac. Picks the best installed voice for the user's language;
/// installing a Premium or Enhanced voice (System Settings › Accessibility ›
/// Spoken Content) makes her sound much better.
@Observable
final class VoiceOutput: NSObject {
    private(set) var isSpeaking = false
    @ObservationIgnored var onSpeakingChanged: ((Bool) -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var voice: AVSpeechSynthesisVoice?
    @ObservationIgnored private var voiceLookup: Task<Void, Never>?
    @ObservationIgnored private var isVoiceReady = false
    /// A line asked for before the voice was found; only the latest is kept, as when speaking.
    @ObservationIgnored private var waitingLine: String?
    /// The line being spoken. Callbacks for a line it replaced are ignored, so the
    /// speaking state never needs `synthesizer.isSpeaking` — that call blocks the main
    /// thread on the synthesizer's lower-priority speech thread (an Xcode hang risk).
    @ObservationIgnored private var current: AVSpeechUtterance?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Finds the voice off the main thread: listing the installed voices takes about a
    /// quarter of a second, which froze Coco on her first spoken line.
    func prepare() {
        guard voiceLookup == nil else { return }
        voiceLookup = Task { [weak self] in
            let found = await Task.detached(priority: .userInitiated) { Self.preferredVoice() }.value
            guard let self else { return }
            voice = found
            isVoiceReady = true
            if let line = waitingLine {
                waitingLine = nil
                speak(line)
            }
        }
    }

    func speak(_ text: String) {
        guard isVoiceReady else {
            waitingLine = text
            prepare()
            return
        }
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: Self.speakable(text))
        utterance.voice = voice
        utterance.pitchMultiplier = 1.18
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.04
        utterance.volume = 0.85
        current = utterance
        synthesizer.speak(utterance)
    }

    func stop() {
        waitingLine = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard let current, ObjectIdentifier(current) == id else { return }
        self.current = nil
        setSpeaking(false)
    }

    private func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        onSpeakingChanged?(speaking)
    }

    /// Typography that reads well but sounds odd when spoken.
    private static func speakable(_ text: String) -> String {
        text.replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "…", with: ".")
            .replacingOccurrences(of: " — ", with: ", ")
    }

    /// The highest-quality installed voice for the current language, or nil to use
    /// the system's Spoken Content voice. Novelty voices are skipped.
    nonisolated private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(String(language.prefix(2))) && $0.identifier.hasPrefix("com.apple.voice.")
        }
        let best = candidates.max { score($0, language) < score($1, language) }
        // A compact voice is no better than the user's own system default.
        return best.flatMap { $0.quality == .default ? nil : $0 }
    }

    nonisolated private static func score(_ voice: AVSpeechSynthesisVoice, _ language: String) -> Int {
        var score = voice.quality.rawValue * 10
        if voice.language == language { score += 5 }
        if voice.gender == .female { score += 2 }
        return score
    }
}

extension VoiceOutput: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.setSpeaking(true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}
