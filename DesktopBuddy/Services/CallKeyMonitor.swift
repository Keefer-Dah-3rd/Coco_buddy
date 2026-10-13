import AppKit
import os

/// A right-hand modifier key held on its own: right Option calls Coco, right Command
/// throws her ball, right Shift gives her a treat.
enum HeldKey {
    case rightOption
    case rightCommand
    case rightShift

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .rightCommand: "Right ⌘"
        case .rightShift: "Right ⇧"
        }
    }

    /// Device-dependent flag for the right-hand key (NX_DEVICERALTKEYMASK, NX_DEVICERCMDKEYMASK).
    fileprivate var sideMask: UInt {
        switch self {
        case .rightOption: 0x40
        case .rightCommand: 0x10
        case .rightShift: 0x04
        }
    }

    fileprivate var family: NSEvent.ModifierFlags {
        switch self {
        case .rightOption: .option
        case .rightCommand: .command
        case .rightShift: .shift
        }
    }

    /// Any of these held as well means a shortcut, not this key on its own.
    fileprivate var others: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags([.command, .option, .control, .shift, .function]).subtracting(family)
    }

    /// ⌘ starts nearly every shortcut and ⇧ types capitals, so they only count once held a
    /// moment on their own — quick ⌘C or a typed capital never shows anything.
    fileprivate var holdDelay: TimeInterval {
        switch self {
        case .rightOption: 0
        case .rightCommand: 0.2
        case .rightShift: 0.25
        }
    }

    /// This key, and only this key (Caps Lock doesn't count).
    func matches(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(family) && flags.isDisjoint(with: others) && flags.rawValue & sideMask != 0
    }

    /// The key's family is down on its own, as the system sees it right now. Which side
    /// isn't reported here, so this only notices the key going up (or a shortcut starting).
    fileprivate var isDownNow: Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(family) && flags.isDisjoint(with: others)
    }
}

/// Watches a held key — right Option to call Coco, right Command to throw her ball — so
/// holding it and clicking anywhere does the thing.
///
/// Asks for no Accessibility or Input Monitoring permission. Key changes arrive as
/// flags-changed events wherever macOS shares them with the app; every mouse event also
/// carries the keys being held, so moving the mouse always catches up; and while the
/// key is down, a light check notices the moment it's let go.
final class CallKeyMonitor {
    let key: HeldKey
    var displayName: String { key.displayName }

    /// True when the key goes down on its own (after its hold delay), false when released.
    var onChange: ((Bool) -> Void)?
    private(set) var isHeld = false

    private var monitors: [Any] = []
    private var releaseCheck: Timer?
    private var pendingHold: DispatchWorkItem?
    private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "call")

    init(key: HeldKey) {
        self.key = key
    }

    func setEnabled(_ enabled: Bool) {
        if enabled { start() } else { stop() }
    }

    private func start() {
        guard monitors.isEmpty else { return }
        let global: NSEvent.EventTypeMask = [.flagsChanged, .mouseMoved, .leftMouseDragged, .rightMouseDragged, .leftMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: global, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event, from: "global") }
        }) {
            monitors.append(monitor)
        }
        // Locally that includes clicks on the overlay, so a key-up that went unnoticed is
        // caught before the click is mistaken for a call.
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .mouseMoved, .leftMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated { self?.observe(event, from: "local") }
            return event
        }) {
            monitors.append(monitor)
        }
    }

    private func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        pendingHold?.cancel()
        setHeld(false, via: "disabled")
    }

    private func observe(_ event: NSEvent, from scope: String) {
        let down = key.matches(event.modifierFlags)
        let source = "\(scope) \(event.type == .flagsChanged ? "key" : "mouse") event"
        if !down {
            pendingHold?.cancel()
            pendingHold = nil
            if isHeld { setHeld(false, via: source) }
            return
        }
        guard !isHeld, pendingHold == nil else { return }
        guard key.holdDelay > 0 else { return setHeld(true, via: source) }
        // Counts only if nothing let go of it (or added another key) during the delay —
        // any such event cancels this.
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pendingHold = nil
                self.setHeld(true, via: source + " (held)")
            }
        }
        pendingHold = work
        DispatchQueue.main.asyncAfter(deadline: .now() + key.holdDelay, execute: work)
    }

    private func setHeld(_ held: Bool, via source: String) {
        guard held != isHeld else { return }
        isHeld = held
        releaseCheck?.invalidate()
        releaseCheck = nil
        // Key-up events may not reach the app, so while the key is down, check it directly —
        // but only if that check can actually see it, or the overlay would vanish at once.
        let checkable = held && key.isDownNow
        log.notice("\(self.key.displayName, privacy: .public) \(held ? "down" : "up", privacy: .public) via \(source, privacy: .public)\(held ? (checkable ? ", release check on" : ", release check unavailable") : "", privacy: .public)")
        if checkable {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isHeld, !self.key.isDownNow else { return }
                    self.setHeld(false, via: "release check")
                }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            releaseCheck = timer
        }
        onChange?(held)
    }
}
