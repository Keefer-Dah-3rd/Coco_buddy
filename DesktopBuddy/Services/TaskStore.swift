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
    @ObservationIgnored private let file: JSONFileStore<TaskList>?
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "tasks")

    /// - Parameter persistent: false keeps everything in memory (previews, snapshots).
    init(persistent: Bool = true) {
        file = persistent ? try? JSONFileStore(name: "tasks") : nil
        list = TaskList()
        if persistent { load() }
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

    /// Adds a task from quick-add text. Returns false if the text had no title.
    @discardableResult
    func add(text: String) -> Bool {
        guard let parsed = QuickAddParser.parse(text) else { return false }
        let task = BuddyTask(title: parsed.title, priority: parsed.priority, estimateMinutes: parsed.estimateMinutes)
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
                                 priority: draft.priority, estimateMinutes: draft.estimateMinutes)
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
        guard let removed = list.remove(id) else { return }
        save()
        onEvent?(.removed(removed))
    }

    /// Puts back a task that was just removed (undo).
    func restore(_ task: BuddyTask) {
        if case .added = list.add(task) { save() }
    }

    func setPriority(_ priority: TaskPriority, for id: BuddyTask.ID) {
        list.update(id) { $0.priority = priority }
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
