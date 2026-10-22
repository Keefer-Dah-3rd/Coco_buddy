import Foundation
import Observation
import BuddyCore
import os

/// Observable, persisted wrapper around `TaskList`. All rules live in `TaskList`;
/// this type only adds storage and change events.
@Observable
final class TaskStore {
    enum Event {
        case added(BuddyTask)
        case duplicate(BuddyTask)
        case completed(BuddyTask)
        case reopened(BuddyTask)
        case removed(BuddyTask)
        /// Several tasks added at once (voice review); one event instead of one per task.
        case addedBatch(count: Int)
    }

    private(set) var list: TaskList
    /// Set if the saved file couldn't be read. The unreadable file is kept, not overwritten.
    private(set) var storageProblem: String?

    @ObservationIgnored var onEvent: ((Event) -> Void)?
    /// Subtasks that moved up when their parent was removed, so undo can put them back.
    @ObservationIgnored private var removedChildren: [BuddyTask.ID: [BuddyTask.ID]] = [:]
    @ObservationIgnored private let file: JSONFileStore<TaskList>?
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "tasks")

    /// - Parameter persistent: false keeps everything in memory (previews, snapshots).
    init(persistent: Bool = true) {
        file = persistent ? try? JSONFileStore(name: "tasks") : nil
        list = TaskList()
        if persistent { load() }
    }

    /// A store saved at a given file — the tasks self-test uses this to check a restart.
    init(fileURL: URL) {
        file = JSONFileStore(url: fileURL)
        list = TaskList()
        load()
    }

    func today(now: Date = .now) -> [BuddyTask] {
        list.today(now: now)
    }

    var openToday: [BuddyTask] {
        today().filter { !$0.isCompleted }
    }

    func task(_ id: BuddyTask.ID?) -> BuddyTask? {
        list.task(id)
    }

    /// Today's list with subtasks under their parents.
    func outline(collapsed: Set<BuddyTask.ID>, now: Date = .now) -> [TaskOutlineRow] {
        list.outline(now: now, collapsed: collapsed)
    }

    /// Adds a task built by the new-task form. Duplicates (same title, same parent) aren't added.
    @discardableResult
    func add(_ task: BuddyTask) -> TaskList.AddResult {
        var task = task
        task.title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.updatedAt = task.createdAt
        let result = list.add(task)
        switch result {
        case .added(let added):
            save()
            onEvent?(.added(added))
        case .duplicate(let existing):
            onEvent?(.duplicate(existing))
        }
        return result
    }

    /// Moves a task under another (nil = top level). Returns why not, if it would loop.
    @discardableResult
    func setParent(_ parent: BuddyTask.ID?, for id: BuddyTask.ID) -> TaskList.ParentProblem? {
        if let problem = list.setParent(parent, for: id) { return problem }
        list.update(id) { $0.updatedAt = .now }
        save()
        return nil
    }

    /// Ticks a task and every subtask under it. Only when the user asks for exactly that.
    func completeWithSubtasks(_ id: BuddyTask.ID) {
        for child in list.descendantIDs(of: id) { _ = list.setCompleted(child, true, at: .now) }
        setCompleted(id, true)
        save()
    }

    /// Adds a task from quick-add text. Returns false if the text had no title.
    @discardableResult
    func add(text: String) -> Bool {
        guard let parsed = QuickAddParser.parse(text) else { return false }
        let task = BuddyTask(title: parsed.title, priority: parsed.priority,
                             estimateMinutes: parsed.estimateMinutes, scope: parsed.scope)
        switch list.add(task) {
        case .added(let added):
            save()
            onEvent?(.added(added))
        case .duplicate(let existing):
            onEvent?(.duplicate(existing))
        }
        return true
    }

    /// Adds reviewed tasks in one go. Returns how many were actually added (duplicates are skipped).
    @discardableResult
    func add(_ drafts: [QuickAddParser.Result]) -> Int {
        var added = 0
        for draft in drafts where !draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            let task = BuddyTask(title: draft.title.trimmingCharacters(in: .whitespaces),
                                 priority: draft.priority, estimateMinutes: draft.estimateMinutes, scope: draft.scope)
            if case .added = list.add(task) { added += 1 }
        }
        if added > 0 {
            save()
            onEvent?(.addedBatch(count: added))
        }
        return added
    }

    func setCompleted(_ id: BuddyTask.ID, _ completed: Bool) {
        guard list.setCompleted(id, completed, at: .now), let task = list.task(id) else { return }
        save()
        onEvent?(completed ? .completed(task) : .reopened(task))
    }

    func toggle(_ id: BuddyTask.ID) {
        guard let task = list.task(id) else { return }
        setCompleted(id, !task.isCompleted)
    }

    func remove(_ id: BuddyTask.ID) {
        let children = list.children(of: id).map(\.id)
        guard let removed = list.remove(id) else { return }
        removedChildren = children.isEmpty ? [:] : [id: children]
        save()
        onEvent?(.removed(removed))
    }

    /// Deletes every task and the saved file (part of "Delete all my data").
    func eraseAll() {
        list = TaskList()
        try? file?.delete()
        storageProblem = nil
    }

    /// Puts back a task that was just removed (undo).
    func restore(_ task: BuddyTask) {
        if case .added = list.restore(task, children: removedChildren[task.id] ?? []) { save() }
        removedChildren[task.id] = nil
    }

    /// Applies an edit from the task editor. Empty titles are ignored rather than saved.
    func update(_ id: BuddyTask.ID, _ transform: (inout BuddyTask) -> Void) {
        guard let before = list.task(id) else { return }
        list.update(id, transform)
        if list.task(id)?.title.isEmpty == true {
            list.update(id) { $0.title = before.title }
        }
        if list.task(id) != before {
            list.update(id) { $0.updatedAt = .now }
            save()
        }
    }

    /// Adds tasks picked from an external service, linking rather than duplicating.
    /// Returns (added, linked to an existing local task).
    @discardableResult
    func addLinked(_ incoming: [BuddyTask]) -> (added: Int, linked: Int) {
        var added = 0, linked = 0
        for task in incoming {
            switch list.addLinked(task) {
            case .added: added += 1
            case .linkedExisting: linked += 1
            case .alreadyLinked: break
            }
        }
        if added + linked > 0 {
            save()
            onEvent?(.addedBatch(count: added + linked))
        }
        return (added, linked)
    }

    /// Open tasks that mirror an external item.
    var openLinkedRefs: [ExternalTaskRef] {
        list.tasks.filter { !$0.isCompleted }.compactMap(\.external)
    }

    func applyExternalUpdates(_ updates: [ExternalTaskRef: (title: String, deadline: Date?, isDone: Bool)]) {
        guard !updates.isEmpty else { return }
        let before = list
        list.refreshLinked(updates, at: .now)
        if list != before { save() }
    }

    var leftovers: [BuddyTask] {
        list.leftovers(now: .now)
    }

    /// Brings unfinished today-only tasks from earlier days onto today's list.
    func carryOverLeftovers() {
        list.carryOver(leftovers.map(\.id), to: .now)
        save()
    }

    /// The user chose to let yesterday's scratch items go.
    func letGoOfLeftovers() {
        for task in leftovers { list.remove(task.id) }
        save()
    }

    func setPriority(_ priority: TaskPriority, for id: BuddyTask.ID) {
        list.update(id) { $0.priority = priority; $0.updatedAt = .now }
        save()
    }

    func logFocus(minutes: Int, for id: BuddyTask.ID) {
        guard minutes > 0 else { return }
        list.logFocus(minutes: minutes, for: id)
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let file else {
            storageProblem = "Tasks can't be saved on this Mac right now."
            return
        }
        do {
            list = try file.load() ?? TaskList()
        } catch {
            // Never overwrite data we couldn't read: move it aside and start fresh.
            let backup = file.url.deletingPathExtension()
                .appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: file.url, to: backup)
            storageProblem = "Your saved tasks couldn't be read, so a backup was kept at \(backup.lastPathComponent)."
            log.error("Task file unreadable: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func save() {
        do {
            try file?.save(list)
        } catch {
            storageProblem = "Couldn't save tasks: \(error.localizedDescription)"
            log.error("Task save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
