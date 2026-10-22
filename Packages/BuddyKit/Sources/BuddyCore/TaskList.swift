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

    /// Adds a task unless an open task with the same title already sits at the same place
    /// (two parents can each have a "Publish" subtask). A parent that doesn't exist is dropped.
    @discardableResult
    public mutating func add(_ task: BuddyTask) -> AddResult {
        var task = task
        if let parent = task.parentID, self.task(parent) == nil || parent == task.id { task.parentID = nil }
        let key = Self.normalized(task.title)
        if let existing = tasks.first(where: { !$0.isCompleted && $0.parentID == task.parentID && Self.normalized($0.title) == key }) {
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

    /// Removes one task. Its subtasks are kept and move up to its own parent, so removing a
    /// parent never deletes work silently.
    @discardableResult
    public mutating func remove(_ id: BuddyTask.ID) -> BuddyTask? {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return nil }
        let removed = tasks.remove(at: index)
        for i in tasks.indices where tasks[i].parentID == id {
            tasks[i].parentID = removed.parentID
        }
        return removed
    }

    // MARK: - Subtasks

    /// The direct subtasks of a task, in the order they were added.
    public func children(of id: BuddyTask.ID) -> [BuddyTask] {
        tasks.filter { $0.parentID == id }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Every task below this one, at any depth.
    public func descendantIDs(of id: BuddyTask.ID) -> Set<BuddyTask.ID> {
        var found = Set<BuddyTask.ID>()
        var queue = [id]
        while let next = queue.popLast() {
            for child in tasks where child.parentID == next && !found.contains(child.id) && child.id != id {
                found.insert(child.id)
                queue.append(child.id)
            }
        }
        return found
    }

    public enum ParentProblem: Error, Equatable, Sendable {
        /// The proposed parent isn't on the list.
        case notFound
        /// A task can't be its own parent.
        case isSelf
        /// The proposed parent is below the task, which would make a loop.
        case isDescendant
    }

    /// Why `parent` can't hold the task `id`, or nil if it can. Nil `parent` (top level) is always fine.
    public func parentProblem(_ parent: BuddyTask.ID?, for id: BuddyTask.ID) -> ParentProblem? {
        guard let parent else { return nil }
        if parent == id { return .isSelf }
        guard task(parent) != nil else { return .notFound }
        if descendantIDs(of: id).contains(parent) { return .isDescendant }
        return nil
    }

    /// Moves a task under `parent` (nil = top level). Refuses anything that would loop.
    @discardableResult
    public mutating func setParent(_ parent: BuddyTask.ID?, for id: BuddyTask.ID) -> ParentProblem? {
        guard task(id) != nil else { return .notFound }
        if let problem = parentProblem(parent, for: id) { return problem }
        update(id) { $0.parentID = parent }
        return nil
    }

    /// Puts back a removed task and re-attaches the subtasks that moved up when it went.
    public mutating func restore(_ task: BuddyTask, children: [BuddyTask.ID]) -> AddResult {
        let result = add(task)
        if case .added = result {
            for i in tasks.indices where children.contains(tasks[i].id) && tasks[i].parentID == task.parentID {
                tasks[i].parentID = task.id
            }
        }
        return result
    }

    /// Today's list as an outline: each task followed by its subtasks (oldest first), indented
    /// by depth. Subtasks of a collapsed task are left out. Counts cover every direct subtask,
    /// including ones finished on earlier days that no longer show.
    public func outline(now: Date, collapsed: Set<BuddyTask.ID> = [], calendar: Calendar = .current) -> [TaskOutlineRow] {
        let visible = today(now: now, calendar: calendar)
        let visibleIDs = Set(visible.map(\.id))
        var childrenOf: [BuddyTask.ID: [BuddyTask]] = [:]
        for task in visible {
            if let parent = task.parentID, visibleIDs.contains(parent) { childrenOf[parent, default: []].append(task) }
        }
        for key in childrenOf.keys { childrenOf[key]?.sort { $0.createdAt < $1.createdAt } }
        // A subtask whose parent isn't showing (finished on an earlier day) stands on its own.
        let roots = visible.filter { task in task.parentID.map { !visibleIDs.contains($0) } ?? true }

        var rows: [TaskOutlineRow] = []
        var seen = Set<BuddyTask.ID>()
        func visit(_ task: BuddyTask, depth: Int) {
            guard seen.insert(task.id).inserted else { return }
            let all = tasks.filter { $0.parentID == task.id }
            let expanded = !collapsed.contains(task.id)
            rows.append(TaskOutlineRow(task: task, depth: depth, subtaskCount: all.count,
                                       completedSubtaskCount: all.filter(\.isCompleted).count, isExpanded: expanded))
            guard expanded else { return }
            for child in childrenOf[task.id] ?? [] { visit(child, depth: depth + 1) }
        }
        for root in roots { visit(root, depth: 0) }
        return rows
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

    public enum LinkResult: Equatable, Sendable {
        /// A new task was added for the external item.
        case added(BuddyTask)
        /// An existing local task with the same title was linked instead of duplicated.
        case linkedExisting(BuddyTask)
        /// This external item is already on the list.
        case alreadyLinked(BuddyTask)
    }

    /// Adds a task that mirrors an external item, without creating duplicates:
    /// the same external item is never added twice, and an open local task with
    /// the same title is linked rather than copied.
    @discardableResult
    public mutating func addLinked(_ task: BuddyTask) -> LinkResult {
        guard let ref = task.external else {
            return add(task) == .added(task) ? .added(task) : .alreadyLinked(task)
        }
        if let existing = tasks.first(where: { $0.external == ref || ($0.external?.source == ref.source && $0.external?.id == ref.id) }) {
            return .alreadyLinked(existing)
        }
        let key = Self.normalized(task.title)
        if let index = tasks.firstIndex(where: { !$0.isCompleted && $0.external == nil && Self.normalized($0.title) == key }) {
            tasks[index].external = ref
            return .linkedExisting(tasks[index])
        }
        tasks.append(task)
        return .added(task)
    }

    /// Updates linked tasks from fresh external data (titles, due dates, completion).
    /// The external service is the source of truth for those fields; local-only
    /// fields (notes, estimate, focus time) are left alone.
    public mutating func refreshLinked(_ updates: [ExternalTaskRef: (title: String, deadline: Date?, isDone: Bool)], at date: Date) {
        for index in tasks.indices {
            guard let ref = tasks[index].external, let update = updates[ref] else { continue }
            tasks[index].title = update.title
            tasks[index].deadline = update.deadline
            if update.isDone, tasks[index].completedAt == nil { tasks[index].completedAt = date }
        }
    }

    public func linkedTask(_ ref: ExternalTaskRef) -> BuddyTask? {
        tasks.first { $0.external?.source == ref.source && $0.external?.id == ref.id }
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

/// One line of today's outline.
public struct TaskOutlineRow: Identifiable, Equatable, Sendable {
    public var task: BuddyTask
    /// 0 for a top-level task, 1 for its subtasks, and so on.
    public var depth: Int
    /// Direct subtasks, done or not.
    public var subtaskCount: Int
    public var completedSubtaskCount: Int
    /// False when the user folded this task's subtasks away.
    public var isExpanded: Bool

    public var id: BuddyTask.ID { task.id }
    public var hasSubtasks: Bool { subtaskCount > 0 }

    public init(task: BuddyTask, depth: Int, subtaskCount: Int, completedSubtaskCount: Int, isExpanded: Bool) {
        self.task = task
        self.depth = depth
        self.subtaskCount = subtaskCount
        self.completedSubtaskCount = completedSubtaskCount
        self.isExpanded = isExpanded
    }
}
