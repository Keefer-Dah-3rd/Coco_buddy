import AppKit
import os

/// Watches the call key — right Option — so holding it and clicking anywhere calls Coco.
///
/// Asks for no Accessibility or Input Monitoring permission. Key changes arrive as
/// flags-changed events wherever macOS shares them with the app; every mouse event also
/// carries the keys being held, so moving the mouse always catches up; and while the
/// key is down, a light check notices the moment it's let go.
final class CallKeyMonitor {
    static let displayName = "Right ⌥"

    /// True when right Option goes down on its own, false when it's released.
    var onChange: ((Bool) -> Void)?
    private(set) var isHeld = false

    private var monitors: [Any] = []
    private var releaseCheck: Timer?
    private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "call")

    /// Device-dependent flag for the right-hand Option key (NX_DEVICERALTKEYMASK).
    private static let rightOptionMask: UInt = 0x40
    /// Any of these held as well means a shortcut, not a call.
    private static let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .shift, .function]

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
        setHeld(false, via: "disabled")
    }

    private func observe(_ event: NSEvent, from scope: String) {
        let held = Self.isCallKey(event.modifierFlags)
        guard held != isHeld else { return }
        setHeld(held, via: "\(scope) \(event.type == .flagsChanged ? "key" : "mouse") event")
    }

    /// Right Option, with no other modifier (Caps Lock doesn't count).
    static func isCallKey(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.option) && flags.isDisjoint(with: otherModifiers) && flags.rawValue & rightOptionMask != 0
    }

    private func setHeld(_ held: Bool, via source: String) {
        guard held != isHeld else { return }
        isHeld = held
        releaseCheck?.invalidate()
        releaseCheck = nil
        // Key-up events may not reach the app, so while the key is down, check it directly —
        // but only if that check can actually see it, or the circle would vanish at once.
        let checkable = held && Self.optionIsDown()
        log.notice("call key \(held ? "down" : "up", privacy: .public) via \(source, privacy: .public)\(held ? (checkable ? ", release check on" : ", release check unavailable") : "", privacy: .public)")
        if checkable {
            let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isHeld, !Self.optionIsDown() else { return }
                    self.setHeld(false, via: "release check")
                }
            }
            timer.tolerance = 0.02
            RunLoop.main.add(timer, forMode: .common)
            releaseCheck = timer
        }
        onChange?(held)
    }

    /// Option down with no other modifier, as the system sees it right now. Which side
    /// isn't reported here, so this only notices Option going up (or a shortcut starting).
    private static func optionIsDown() -> Bool {
        let flags = NSEvent.modifierFlags
        return flags.contains(.option) && flags.isDisjoint(with: otherModifiers)
    }
}
