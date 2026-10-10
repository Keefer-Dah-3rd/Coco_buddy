import Foundation

/// Picks one task to suggest next, and says why — deadlines first, then priority,
/// then quick wins. Deliberately simple rules rather than a black box: the reason
/// shown to the user is the rule that actually decided.
public enum DayPlanner {
    public enum Reason: Equatable, Sendable {
        case overdue
        case dueToday
        case dueTomorrow
        case highPriority
        case quickWin
        case nextInLine
    }

    public struct Suggestion: Equatable, Sendable {
        public var taskID: BuddyTask.ID
        public var reason: Reason
    }

    public static func suggestion(from tasks: [BuddyTask], now: Date, calendar: Calendar = .current) -> Suggestion? {
        let open = tasks.filter { !$0.isCompleted }
        let ranked = open.map { task in (task, score(task, now: now, calendar: calendar)) }
        let best = ranked.max { a, b in
            a.1 != b.1 ? a.1 < b.1 : a.0.createdAt > b.0.createdAt
        }
        guard let (task, _) = best else { return nil }
        return Suggestion(taskID: task.id, reason: reason(for: task, now: now, calendar: calendar))
    }

    /// Whole days from today until the deadline (negative = overdue), or nil without one.
    public static func daysUntilDeadline(_ task: BuddyTask, now: Date, calendar: Calendar = .current) -> Int? {
        guard let deadline = task.deadline else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                       to: calendar.startOfDay(for: deadline)).day
    }

    private static func score(_ task: BuddyTask, now: Date, calendar: Calendar) -> Int {
        var score = task.priority.rawValue * 20
        switch daysUntilDeadline(task, now: now, calendar: calendar) {
        case let days? where days < 0: score += 100
        case 0?: score += 60
        case 1?: score += 25
        default: break
        }
        if let estimate = task.estimateMinutes, estimate <= 20 { score += 8 }
        return score
    }

    private static func reason(for task: BuddyTask, now: Date, calendar: Calendar) -> Reason {
        switch daysUntilDeadline(task, now: now, calendar: calendar) {
        case let days? where days < 0: return .overdue
        case 0?: return .dueToday
        case 1? where task.priority < .high: return .dueTomorrow
        default: break
        }
        if task.priority == .high { return .highPriority }
        if let estimate = task.estimateMinutes, estimate <= 20 { return .quickWin }
        return .nextInLine
    }
}

/// One focus session that actually happened (finished or stopped early).
public struct FocusSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var taskID: UUID?
    public var endedAt: Date
    /// Seconds actually focused (pauses excluded).
    public var seconds: TimeInterval
    /// True if the session ran to the end rather than being stopped.
    public var finished: Bool

    public init(id: UUID = UUID(), taskID: UUID?, endedAt: Date, seconds: TimeInterval, finished: Bool) {
        self.id = id
        self.taskID = taskID
        self.endedAt = endedAt
        self.seconds = seconds
        self.finished = finished
    }
}

/// A rolling history of focus sessions, kept for a few weeks for daily summaries.
public struct FocusLog: Codable, Equatable, Sendable {
    public private(set) var sessions: [FocusSessionRecord] = []
    public static let keepDays = 30
    /// Sessions shorter than this aren't worth logging (a mis-click, an immediate stop).
    public static let minimumSeconds: TimeInterval = 60

    public init(sessions: [FocusSessionRecord] = []) {
        self.sessions = sessions
    }

    public mutating func record(_ session: FocusSessionRecord, calendar: Calendar = .current) {
        guard session.seconds >= Self.minimumSeconds else { return }
        sessions.append(session)
        let cutoff = calendar.date(byAdding: .day, value: -Self.keepDays, to: session.endedAt) ?? .distantPast
        sessions.removeAll { $0.endedAt < cutoff }
    }

    public struct DaySummary: Equatable, Sendable {
        public var minutes: Int
        public var sessions: Int
    }

    public func summary(on day: Date, calendar: Calendar = .current) -> DaySummary {
        let todays = sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }
        let seconds = todays.reduce(0) { $0 + $1.seconds }
        return DaySummary(minutes: Int((seconds / 60).rounded()), sessions: todays.count)
    }
}
