import Foundation

public enum TaskPriority: Int, Codable, CaseIterable, Comparable, Sendable {
    case none, low, medium, high

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .none: "None"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// Where a task lives. `.personal` tasks persist until done or removed;
/// `.today` tasks are scratch items that belong to a single day.
public enum TaskScope: String, Codable, Sendable {
    case personal
    case today
}

/// Where a task came from when it isn't purely local, e.g. a Notion page.
public struct ExternalTaskRef: Codable, Hashable, Sendable {
    public enum Source: String, Codable, Sendable { case notion }

    public var source: Source
    public var id: String
    public var url: URL?

    public init(source: Source, id: String, url: URL? = nil) {
        self.source = source
        self.id = id
        self.url = url
    }
}

public struct BuddyTask: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var notes: String
    public var priority: TaskPriority
    public var estimateMinutes: Int?
    public var deadline: Date?
    public var scope: TaskScope
    public var createdAt: Date
    /// Set only when the user confirms completion. Never inferred from elapsed time.
    public var completedAt: Date?
    /// Total minutes of finished focus sessions linked to this task.
    public var focusMinutes: Int
    /// For `.today` tasks: the day they belong to (start of day). Nil means the day they were created.
    public var plannedDay: Date?
    /// Set for tasks imported from (and linked to) an external service.
    public var external: ExternalTaskRef?

    public var isCompleted: Bool { completedAt != nil }

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        priority: TaskPriority = .none,
        estimateMinutes: Int? = nil,
        deadline: Date? = nil,
        scope: TaskScope = .personal,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        focusMinutes: Int = 0,
        plannedDay: Date? = nil,
        external: ExternalTaskRef? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.priority = priority
        self.estimateMinutes = estimateMinutes
        self.deadline = deadline
        self.scope = scope
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.focusMinutes = focusMinutes
        self.plannedDay = plannedDay
        self.external = external
    }
}
