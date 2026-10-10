import Foundation

/// The user's task collection and every rule about how it changes.
/// A pure value type: the app layer owns persistence and observation.
public struct TaskList: Codable, Equatable, Sendable {
    public private(set) var tasks: [BuddyTask]

    public init(tasks: [BuddyTask] = []) {
        self.tasks = tasks
    }

    public enum AddResult: Equatable, Sendable {
        case added(BuddyTask)
        /// An open task with the same title already exists; nothing was added.
        case duplicate(BuddyTask)
    }

    @discardableResult
    public mutating func add(_ task: BuddyTask) -> AddResult {
        let key = Self.normalized(task.title)
        if let existing = tasks.first(where: { !$0.isCompleted && Self.normalized($0.title) == key }) {
            return .duplicate(existing)
        }
        tasks.append(task)
        return .added(task)
    }

    /// Returns true when the completion state actually changed.
    @discardableResult
    public mutating func setCompleted(_ id: BuddyTask.ID, _ completed: Bool, at date: Date) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].isCompleted != completed else { return false }
        tasks[index].completedAt = completed ? date : nil
        return true
    }

    @discardableResult
    public mutating func remove(_ id: BuddyTask.ID) -> BuddyTask? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        return tasks.remove(at: index)
    }

    public mutating func update(_ id: BuddyTask.ID, _ transform: (inout BuddyTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        transform(&tasks[index])
        tasks[index].title = tasks[index].title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public mutating func logFocus(minutes: Int, for id: BuddyTask.ID) {
        update(id) { $0.focusMinutes += max(0, minutes) }
    }

    public func task(_ id: BuddyTask.ID?) -> BuddyTask? {
        guard let id else { return nil }
        return tasks.first { $0.id == id }
    }

    /// What belongs on today's list: every open personal task (unfinished work rolls
    /// over — it is never auto-completed), today-only items created today, and
    /// anything completed today. Open work first, by priority, then deadline, then age.
    public func today(now: Date, calendar: Calendar = .current) -> [BuddyTask] {
        let visible = tasks.filter { task in
            if let completedAt = task.completedAt {
                return calendar.isDate(completedAt, inSameDayAs: now)
            }
            switch task.scope {
            case .personal: return true
            case .today: return calendar.isDate(task.plannedDay ?? task.createdAt, inSameDayAs: now)
            }
        }
        let open = visible.filter { !$0.isCompleted }.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.deadline != $1.deadline { return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture) }
            return $0.createdAt < $1.createdAt
        }
        let done = visible.filter(\.isCompleted).sorted {
            ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
        }
        return open + done
    }

    /// Unfinished "today only" tasks from earlier days — waiting for the user to carry
    /// them over or let them go. Never dropped silently.
    public func leftovers(now: Date, calendar: Calendar = .current) -> [BuddyTask] {
        let today = calendar.startOfDay(for: now)
        return tasks.filter {
            !$0.isCompleted && $0.scope == .today && calendar.startOfDay(for: $0.plannedDay ?? $0.createdAt) < today
        }
    }

    /// Moves today-only tasks onto the given day.
    public mutating func carryOver(_ ids: [BuddyTask.ID], to day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        for id in ids {
            update(id) { $0.plannedDay = start }
        }
    }

    public static func normalized(_ title: String) -> String {
        title.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}
