import Foundation
import Observation
import BuddyCore

/// User preferences, persisted to UserDefaults on every change.
@Observable
final class Preferences {
    enum Presence: String, CaseIterable, Identifiable {
        /// Small, reacts only to direct interaction and important events.
        case compact
        /// Full size, follows the cursor, offers short acknowledgements.
        case interactive

        var id: Self { self }
        var label: String { rawValue.capitalized }
    }

    enum FocusPresentation: String, CaseIterable, Identifiable {
        case visible, smaller, quiet

        var id: Self { self }
        var label: String {
            switch self {
            case .visible: "Stay visible"
            case .smaller: "Get smaller"
            case .quiet: "Go quiet"
            }
        }
    }

    var isBuddyVisible: Bool { didSet { defaults.set(isBuddyVisible, forKey: Key.visible) } }
    var alwaysOnTop: Bool { didSet { defaults.set(alwaysOnTop, forKey: Key.onTop) } }
    var soundsMuted: Bool { didSet { defaults.set(soundsMuted, forKey: Key.muted) } }
    /// The buddy speaks her lines aloud as well as showing them.
    var voiceEnabled: Bool { didSet { defaults.set(voiceEnabled, forKey: Key.voice) } }
    var presence: Presence { didSet { defaults.set(presence.rawValue, forKey: Key.presence) } }
    var focusPresentation: FocusPresentation {
        didSet { defaults.set(focusPresentation.rawValue, forKey: Key.focusPresentation) }
    }
    var focusSettings: FocusSettings {
        didSet { defaults.set(try? JSONEncoder().encode(focusSettings), forKey: Key.focusSettings) }
    }
    /// Bottom-left of the character window in global screen coordinates.
    var buddyOrigin: CGPoint? {
        didSet {
            if let buddyOrigin {
                defaults.set([buddyOrigin.x, buddyOrigin.y], forKey: Key.origin)
            } else {
                defaults.removeObject(forKey: Key.origin)
            }
        }
    }
    /// "yyyy-MM-dd" of the last launch greeting, so the buddy says hello once a day.
    var lastGreetingDay: String? { didSet { defaults.set(lastGreetingDay, forKey: Key.greeting) } }
    /// Coco barks at big moments (still silenced by Mute Sounds).
    var barksEnabled: Bool { didSet { defaults.set(barksEnabled, forKey: Key.barks) } }
    /// Hour the working day ends, for free-time maths (0–23).
    var workdayEndHour: Int { didSet { defaults.set(workdayEndHour, forKey: Key.workdayEnd) } }
    /// Hour the working day starts — open time on the calendar is counted from here.
    var workdayStartHour: Int { didSet { defaults.set(workdayStartHour, forKey: Key.workdayStart) } }
    /// ⌃⌥C opens Coco's panel from any app.
    var globalShortcutEnabled: Bool { didSet { defaults.set(globalShortcutEnabled, forKey: Key.shortcut) } }
    /// Hold right Option and click anywhere to call Coco over.
    var callKeyEnabled: Bool { didSet { defaults.set(callKeyEnabled, forKey: Key.callKey) } }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Key.onboarding) } }

    @ObservationIgnored private let defaults: UserDefaults

    /// Back to first-launch defaults (part of "Delete all my data").
    func reset() {
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix("buddy.") || key.hasPrefix("focus.") || key.hasPrefix("calendar.") || key.hasPrefix("notion.") {
            defaults.removeObject(forKey: key)
        }
        isBuddyVisible = true
        alwaysOnTop = true
        soundsMuted = false
        voiceEnabled = false
        presence = .interactive
        focusPresentation = .smaller
        focusSettings = FocusSettings()
        buddyOrigin = nil
        lastGreetingDay = nil
        barksEnabled = true
        workdayEndHour = 18
        workdayStartHour = 9
        globalShortcutEnabled = true
        callKeyEnabled = true
        onboardingCompleted = false
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Key.visible: true, Key.onTop: true, Key.muted: false,
                                     Key.barks: true, Key.workdayEnd: 18, Key.workdayStart: 9, Key.shortcut: true,
                                     Key.callKey: true])

        isBuddyVisible = defaults.bool(forKey: Key.visible)
        alwaysOnTop = defaults.bool(forKey: Key.onTop)
        soundsMuted = defaults.bool(forKey: Key.muted)
        voiceEnabled = defaults.bool(forKey: Key.voice)
        presence = defaults.string(forKey: Key.presence).flatMap(Presence.init) ?? .interactive
        focusPresentation = defaults.string(forKey: Key.focusPresentation)
            .flatMap(FocusPresentation.init) ?? .smaller
        focusSettings = defaults.data(forKey: Key.focusSettings)
            .flatMap { try? JSONDecoder().decode(FocusSettings.self, from: $0) } ?? FocusSettings()
        if let xy = defaults.array(forKey: Key.origin) as? [Double], xy.count == 2 {
            buddyOrigin = CGPoint(x: xy[0], y: xy[1])
        }
        lastGreetingDay = defaults.string(forKey: Key.greeting)
        barksEnabled = defaults.bool(forKey: Key.barks)
        let endHour = min(23, max(1, defaults.integer(forKey: Key.workdayEnd)))
        workdayEndHour = endHour
        workdayStartHour = min(endHour - 1, max(0, defaults.integer(forKey: Key.workdayStart)))
        globalShortcutEnabled = defaults.bool(forKey: Key.shortcut)
        callKeyEnabled = defaults.bool(forKey: Key.callKey)
        onboardingCompleted = defaults.bool(forKey: Key.onboarding)
    }

    private enum Key {
        static let visible = "buddy.visible"
        static let onTop = "buddy.alwaysOnTop"
        static let muted = "buddy.soundsMuted"
        static let voice = "buddy.voiceEnabled"
        static let presence = "buddy.presence"
        static let focusPresentation = "focus.presentation"
        static let focusSettings = "focus.settings"
        static let origin = "buddy.origin"
        static let greeting = "buddy.lastGreetingDay"
        static let barks = "buddy.barksEnabled"
        static let workdayEnd = "calendar.workdayEndHour"
        static let workdayStart = "calendar.workdayStartHour"
        static let shortcut = "buddy.globalShortcut"
        static let callKey = "buddy.callKey"
        static let onboarding = "buddy.onboardingCompleted"
    }
}

/// Calls `apply` with `read()`'s value now and again whenever an observable property
/// that `read` touched changes. Reading and applying are split so `apply` can write
/// to other observable objects without subscribing to them (and looping).
/// This is the bridge from Observation to AppKit controllers.
func track<Value>(
    _ read: @escaping @MainActor @Sendable () -> Value,
    apply: @escaping @MainActor @Sendable (Value) -> Void
) {
    let value = withObservationTracking(read) {
        Task { @MainActor in track(read, apply: apply) }
    }
    apply(value)
}
