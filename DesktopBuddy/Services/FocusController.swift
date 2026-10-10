import AppKit
import Observation
import BuddyCore

/// Drives a `FocusTimer` in the running app: persistence, a display tick,
/// completion detection, and the system notification.
///
/// Accuracy never depends on the tick. The tick only refreshes `now` for the
/// countdown; completion is decided by comparing dates in `reconcile()`, which
/// also runs on wake and launch.
@Observable
final class FocusController {
    enum Event {
        case started(FocusPhase, taskID: UUID?)
        case paused
        case resumed
        case stopped(FocusPhase, elapsed: TimeInterval, taskID: UUID?)
        /// `whileAway` is true when the session ended while the app wasn't running.
        case finished(FocusPhase, duration: TimeInterval, taskID: UUID?, whileAway: Bool)
    }

    private(set) var timer: FocusTimer
    /// The clock the UI renders against. Advanced by the tick and by `reconcile()`.
    private(set) var now = Date()

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    @ObservationIgnored var taskTitle: (UUID?) -> String? = { _ in nil }
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let notifications: NotificationService
    @ObservationIgnored private let store: JSONFileStore<FocusTimer>?
    @ObservationIgnored private var tick: Timer?
    @ObservationIgnored private var completion: Timer?

    init(preferences: Preferences, notifications: NotificationService, persistent: Bool = true) {
        self.preferences = preferences
        self.notifications = notifications
        store = persistent ? try? JSONFileStore(name: "focus") : nil
        timer = (try? store?.load()) ?? FocusTimer()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
    }

    /// Call once at launch, after `onEvent` is connected.
    func restoreAfterLaunch() {
        reconcile(atLaunch: true)
    }

    var remaining: TimeInterval { timer.remaining(at: now) }
    var progress: Double { timer.progress(at: now) }
    var isFocusing: Bool { timer.isRunning && timer.phase == .focus }

    // MARK: - Intents

    func start(_ phase: FocusPhase = .focus, taskID: UUID? = nil) {
        let minutes = preferences.focusSettings.minutes(for: phase)
        now = Date()
        timer.start(phase, duration: TimeInterval(minutes * 60), taskID: taskID, now: now)
        commit()
        onEvent?(.started(phase, taskID: timer.taskID))
    }

    func pause() {
        now = Date()
        guard timer.pause(now: now) else { return }
        commit()
        onEvent?(.paused)
    }

    func resume() {
        now = Date()
        guard timer.resume(now: now) else { return }
        commit()
        onEvent?(.resumed)
    }

    func stop() {
        now = Date()
        let phase = timer.phase
        let elapsed = timer.stop(now: now)
        commit()
        onEvent?(.stopped(phase, elapsed: elapsed, taskID: timer.taskID))
    }

    /// Dismisses a finished session and shows the next phase's full length.
    func acknowledge(preparing next: FocusPhase? = nil) {
        timer.acknowledge()
        let phase = next ?? timer.phase
        timer.prepare(phase, duration: TimeInterval(preferences.focusSettings.minutes(for: phase) * 60))
        commit()
    }

    /// Shows a phase's length on an idle timer (the phase picker).
    func prepare(_ phase: FocusPhase) {
        timer.acknowledge()
        timer.prepare(phase, duration: TimeInterval(preferences.focusSettings.minutes(for: phase) * 60))
        commit()
    }

    func selectTask(_ id: UUID?) {
        timer.setTask(id)
        commit()
    }

    func adjustLength(by minutes: Int) {
        guard !timer.isActive else { return }
        var settings = preferences.focusSettings
        settings.setMinutes(settings.minutes(for: timer.phase) + minutes, for: timer.phase)
        preferences.focusSettings = settings
        prepare(timer.phase)
    }

    var suggestedNextPhase: FocusPhase {
        timer.suggestedNextPhase(settings: preferences.focusSettings)
    }

    // MARK: - Time

    /// Brings state up to date with the wall clock. Safe to call any time.
    func reconcile(atLaunch: Bool = false) {
        now = Date()
        if timer.advance(to: now) {
            let ended = timer
            commit()
            onEvent?(.finished(ended.phase, duration: ended.duration, taskID: ended.taskID, whileAway: atLaunch))
        } else {
            scheduleTimers()
        }
    }

    private func commit() {
        try? store?.save(timer)
        scheduleTimers()
        scheduleNotification()
    }

    private func scheduleTimers() {
        tick?.invalidate()
        completion?.invalidate()
        tick = nil
        completion = nil
        guard let endsAt = timer.endsAt else { return }

        // Completion: one shot at the exact end date.
        completion = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconcile() }
        }
        completion?.tolerance = 0.05

        // Display tick, aligned so the visible seconds change on the boundary.
        let fraction = timer.remaining(at: now).truncatingRemainder(dividingBy: 1)
        let firstTick = now.addingTimeInterval(fraction > 0.02 ? fraction : 1)
        tick = Timer(fire: firstTick, interval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.now = Date()
                if self.timer.remaining(at: self.now) <= 0 { self.reconcile() }
            }
        }
        tick?.tolerance = 0.05
        for t in [completion, tick].compactMap({ $0 }) {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    private func scheduleNotification() {
        guard let endsAt = timer.endsAt else {
            notifications.cancelSessionEnd()
            return
        }
        let phase = timer.phase
        let minutes = Int((timer.duration / 60).rounded())
        let title = taskTitle(timer.taskID)
        let next = suggestedNextPhaseAfterFinishing(phase)
        notifications.scheduleSessionEnd(at: endsAt, phase: phase, minutes: minutes, taskTitle: title, next: next,
                                          nextMinutes: preferences.focusSettings.minutes(for: next))
    }

    private func suggestedNextPhaseAfterFinishing(_ phase: FocusPhase) -> FocusPhase {
        guard phase == .focus else { return .focus }
        let streak = timer.focusStreak + 1
        return streak >= preferences.focusSettings.sessionsBeforeLongBreak ? .longBreak : .shortBreak
    }
}
