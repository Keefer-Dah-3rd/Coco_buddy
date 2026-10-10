import AppKit
import CoreGraphics

/// Notices when the user has stepped away (no input for a while, or displays asleep)
/// so the buddy can doze off — and when they come back.
///
/// Uses the system-wide idle time, which needs no special permission. Polls slowly
/// while the user is present and quickly while away, so waking up feels immediate.
final class PresenceMonitor {
    var onChange: ((_ isAway: Bool) -> Void)?
    private(set) var isAway = false

    private let awayAfter: TimeInterval = 5 * 60
    private var timer: Timer?
    private var displaysAsleep = false

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displaysAsleep = true
                self?.evaluate()
            }
        }
        center.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.displaysAsleep = false
                self?.evaluate()
            }
        }
        evaluate()
    }

    private func evaluate() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let away = displaysAsleep || idle >= awayAfter
        if away != isAway {
            isAway = away
            onChange?(away)
        }
        schedule(after: away ? 1.5 : max(5, min(30, awayAfter - idle)))
    }

    private func schedule(after interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer?.tolerance = interval * 0.2
    }
}
