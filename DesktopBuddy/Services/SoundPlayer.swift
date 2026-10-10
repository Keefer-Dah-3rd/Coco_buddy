import AppKit

/// A handful of quiet system sounds for meaningful moments only — never for clicks
/// or idle behaviour. Respects the mute preference.
struct SoundPlayer {
    enum Cue {
        case taskDone, sessionStart, sessionEnd

        var name: NSSound.Name {
            switch self {
            case .taskDone: "Pop"
            case .sessionStart: "Tink"
            case .sessionEnd: "Glass"
            }
        }
    }

    let preferences: Preferences

    func play(_ cue: Cue) {
        guard !preferences.soundsMuted,
              let sound = NSSound(named: cue.name)?.copy() as? NSSound else { return }
        sound.volume = 0.4
        sound.play()
    }
}
