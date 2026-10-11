import AppKit

/// A handful of sounds for meaningful moments only — never for idle behaviour.
/// Respects the mute preference (which also silences Coco's barks).
@MainActor
final class SoundPlayer {
    enum Cue {
        case taskDone, sessionStart, sessionEnd
        /// One of Coco's four barks, never the same one twice in a row.
        case bark

        var systemName: NSSound.Name? {
            switch self {
            case .taskDone: "Pop"
            case .sessionStart: "Tink"
            case .sessionEnd: "Glass"
            case .bark: nil
            }
        }
    }

    private let preferences: Preferences
    /// Four single-bark cuts from the bark recording, bundled as short WAVs.
    private let barks: [NSSound]
    private var lastBark = -1

    init(preferences: Preferences) {
        self.preferences = preferences
        barks = (1...4).compactMap { index in
            Bundle.main.url(forResource: "coco-bark-\(index)", withExtension: "wav")
                .flatMap { NSSound(contentsOf: $0, byReference: true) }
        }
    }

    func play(_ cue: Cue) {
        guard !preferences.soundsMuted else { return }
        if cue == .bark {
            guard preferences.barksEnabled, !barks.isEmpty else { return }
            var index = Int.random(in: 0..<barks.count)
            if index == lastBark, barks.count > 1 { index = (index + 1) % barks.count }
            lastBark = index
            let sound = barks[index]
            sound.stop()
            sound.volume = 0.55
            sound.play()
            return
        }
        guard let name = cue.systemName, let sound = NSSound(named: name)?.copy() as? NSSound else { return }
        sound.volume = 0.4
        sound.play()
    }
}
