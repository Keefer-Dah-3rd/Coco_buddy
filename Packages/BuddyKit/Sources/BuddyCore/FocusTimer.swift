import Foundation

public enum FocusPhase: String, Codable, CaseIterable, Sendable {
    case focus, shortBreak, longBreak

    public var isBreak: Bool { self != .focus }

    public var label: String {
        switch self {
        case .focus: "Focus"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }
}

public struct FocusSettings: Codable, Equatable, Sendable {
    public static let minuteRange = 1...180

    public var focusMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 15
    public var sessionsBeforeLongBreak = 4

    public init() {}

    public func minutes(for phase: FocusPhase) -> Int {
        switch phase {
        case .focus: focusMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    public mutating func setMinutes(_ minutes: Int, for phase: FocusPhase) {
        let clamped = min(max(minutes, Self.minuteRange.lowerBound), Self.minuteRange.upperBound)
        switch phase {
        case .focus: focusMinutes = clamped
        case .shortBreak: shortBreakMinutes = clamped
        case .longBreak: longBreakMinutes = clamped
        }
    }
}

/// A focus/break timer defined entirely by wall-clock dates.
///
/// Nothing here counts ticks: a running session stores when it ends, a paused one
/// stores what was left. `remaining(at:)` is therefore correct after the app was
/// inactive, napped, relaunched or the Mac slept. Callers drive state forward with
/// `advance(to:)` whenever time may have passed (a UI tick, wake, launch).
public struct FocusTimer: Codable, Equatable, Sendable {
    public enum Status: Codable, Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        /// Ended naturally; waiting for the user to acknowledge or start the next phase.
        case finished(at: Date)
    }

    public private(set) var phase: FocusPhase = .focus
    public private(set) var status: Status = .idle
    public private(set) var duration: TimeInterval = 25 * 60
    public private(set) var taskID: UUID?
    /// Focus sessions completed since the last long break.
    public private(set) var focusStreak = 0

    public init() {}

    public var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = status { return true }
        return false
    }

    public var isFinished: Bool {
        if case .finished = status { return true }
        return false
    }

    /// Running or paused — a session the user has started and not ended.
    public var isActive: Bool { isRunning || isPaused }

    public var endsAt: Date? {
        if case .running(let endsAt) = status { return endsAt }
        return nil
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch status {
        case .idle: duration
        // Clamped so a clock set backwards can't show more than the session length.
        case .running(let endsAt): min(duration, max(0, endsAt.timeIntervalSince(now)))
        case .paused(let remaining): remaining
        case .finished: 0
        }
    }

    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    public func elapsed(at now: Date) -> TimeInterval {
        duration - remaining(at: now)
    }

    public mutating func start(_ phase: FocusPhase, duration: TimeInterval, taskID: UUID?, now: Date) {
        self.phase = phase
        self.duration = max(1, duration)
        self.taskID = phase == .focus ? taskID : self.taskID
        if phase == .longBreak { focusStreak = 0 }
        status = .running(endsAt: now.addingTimeInterval(self.duration))
    }

    @discardableResult
    public mutating func pause(now: Date) -> Bool {
        guard isRunning else { return false }
        status = .paused(remaining: remaining(at: now))
        return true
    }

    @discardableResult
    public mutating func resume(now: Date) -> Bool {
        guard case .paused(let remaining) = status else { return false }
        status = .running(endsAt: now.addingTimeInterval(remaining))
        return true
    }

    /// Ends the session early. Returns how many seconds had elapsed.
    @discardableResult
    public mutating func stop(now: Date) -> TimeInterval {
        guard isActive else { return 0 }
        let elapsed = elapsed(at: now)
        status = .idle
        return elapsed
    }

    /// Moves a running session to `.finished` once its end date has passed.
    /// Returns true exactly once per session — the moment to celebrate and notify.
    @discardableResult
    public mutating func advance(to now: Date) -> Bool {
        guard case .running(let endsAt) = status, now >= endsAt else { return false }
        status = .finished(at: endsAt)
        if phase == .focus { focusStreak += 1 }
        return true
    }

    /// Clears a finished session back to idle, keeping the phase and task for context.
    public mutating func acknowledge() {
        if isFinished { status = .idle }
    }

    public mutating func setTask(_ taskID: UUID?) {
        self.taskID = taskID
    }

    /// Prepares an idle timer to show a phase's full duration.
    public mutating func prepare(_ phase: FocusPhase, duration: TimeInterval) {
        guard !isActive else { return }
        self.phase = phase
        self.duration = max(1, duration)
        status = .idle
    }

    /// What should come after the phase that just ended.
    public func suggestedNextPhase(settings: FocusSettings) -> FocusPhase {
        guard phase == .focus else { return .focus }
        return focusStreak >= settings.sessionsBeforeLongBreak ? .longBreak : .shortBreak
    }
}
