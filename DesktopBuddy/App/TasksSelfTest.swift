#if DEBUG
import Foundation
import BuddyCore

/// Drives the real model through the new-task form, subtasks and "Focus on this now", and
/// checks a restart keeps the hierarchy. Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --tasks-selftest
enum TasksSelfTest {
    @MainActor
    static func run() {
        var passed = 0
        var failed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { passed += 1 } else { failed += 1; print("tasks selftest FAILED: \(name)") }
        }
        let model = AppModel(preview: true)
        model.preferences.reset()
        model.start()  // wires the task and focus events, as at launch
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!

        // The plus button opens the form, bringing along anything typed in the add field.
        model.openTaskForm(typed: "Draft intro ~30m !!")
        check(model.taskForm?.title == "Draft intro" && model.taskForm?.estimateMinutes == 30
              && model.taskForm?.priority == .medium && model.taskForm?.parentID == nil, "the plus button opens a prefilled form")
        model.taskForm = nil
        model.openTaskForm()
        check(model.taskForm != nil && model.taskForm?.title == "", "the plus button opens an empty form")

        // A name is required.
        let before = model.tasks.list.tasks.count
        check(model.createTask(from: NewTaskDraft(title: "   ")) == .invalid("Give the task a name first."), "an empty name is refused")
        check(model.tasks.list.tasks.count == before && model.taskForm != nil, "nothing is added and the form stays open")

        // A full task is saved with every field, closes the form and shows at once.
        var draft = NewTaskDraft(title: "Redesign portfolio", notes: "Start with the case studies",
                                 estimateMinutes: 120, priority: .urgent, deadline: tomorrow)
        guard case .created(let parent) = model.createTask(from: draft) else {
            print("tasks selftest FAILED: creating a task"); exit(1)
        }
        check(model.taskForm == nil, "creating closes the form")
        let stored = model.tasks.task(parent.id)
        check(stored?.notes == "Start with the case studies" && stored?.estimateMinutes == 120 && stored?.priority == .urgent
              && stored?.deadline == tomorrow && stored?.parentID == nil && stored?.updatedAt != nil, "every field is stored")
        check(model.tasks.outline(collapsed: model.collapsedTaskIDs).contains { $0.id == parent.id }, "the new task is on the list straight away")
        check(model.justAddedTaskID == parent.id, "the new task is highlighted")

        // The same title in the same place isn't added twice; the form stays open to fix it.
        model.openTaskForm()
        draft.id = UUID()
        if case .duplicate = model.createTask(from: draft) { check(true, "duplicate") } else { check(false, "a duplicate is refused") }
        check(model.taskForm != nil, "the form stays open after a duplicate")
        model.taskForm = nil

        // Subtasks: the form opens with the parent set, and saves under it.
        model.collapsedTaskIDs.insert(parent.id)
        model.openTaskForm(parent: parent.id)
        check(model.taskForm?.parentID == parent.id, "Add subtask opens the form with the parent set")
        var subtasks: [BuddyTask] = []
        for title in ["Audit existing case studies", "Update the Buz case study", "Build new animations", "Publish the changes"] {
            model.openTaskForm(parent: parent.id)
            if case .created(let task) = model.createTask(from: NewTaskDraft(title: title, estimateMinutes: 45, parentID: parent.id)) {
                subtasks.append(task)
            }
        }
        check(subtasks.count == 4 && subtasks.allSatisfy { model.tasks.task($0.id)?.parentID == parent.id }, "subtasks are saved under the parent")
        check(!model.collapsedTaskIDs.contains(parent.id), "adding a subtask unfolds its parent")
        var rows = model.tasks.outline(collapsed: model.collapsedTaskIDs)
        let parentIndex = rows.firstIndex { $0.id == parent.id } ?? -1
        check(parentIndex >= 0 && Array(rows[(parentIndex + 1)...].prefix(4).map(\.id)) == subtasks.map(\.id)
              && rows[parentIndex + 1].depth == 1, "subtasks are listed, indented, under the parent in the order added")
        check(rows[parentIndex].subtaskCount == 4 && rows[parentIndex].completedSubtaskCount == 0, "the parent counts its subtasks")

        // Folding.
        model.toggleCollapsed(parent.id)
        rows = model.tasks.outline(collapsed: model.collapsedTaskIDs)
        check(!rows.contains { $0.id == subtasks[0].id } && rows.first { $0.id == parent.id }?.isExpanded == false, "collapsing hides the subtasks")
        model.toggleCollapsed(parent.id)
        check(model.tasks.outline(collapsed: model.collapsedTaskIDs).contains { $0.id == subtasks[0].id }, "expanding shows them again")

        // Completing a subtask on its own.
        model.toggleTask(subtasks[0].id)
        rows = model.tasks.outline(collapsed: model.collapsedTaskIDs)
        check(model.tasks.task(subtasks[0].id)?.isCompleted == true && model.tasks.task(parent.id)?.isCompleted == false,
              "a subtask completes without touching its parent")
        check(rows.first { $0.id == parent.id }?.completedSubtaskCount == 1, "the parent's summary follows")
        for task in subtasks.dropFirst() { model.toggleTask(task.id) }
        check(model.tasks.task(parent.id)?.isCompleted == false, "finishing every subtask leaves the parent for the user")

        // No loops.
        check(model.tasks.setParent(parent.id, for: parent.id) == .isSelf, "a task can't be its own parent")
        check(model.tasks.setParent(subtasks[1].id, for: parent.id) == .isDescendant, "a parent can't go under its own subtask")
        check(model.tasks.task(parent.id)?.parentID == nil, "a refused move changes nothing")

        // Removing a parent keeps the subtasks; undo puts them back underneath.
        model.removeTask(parent.id)
        check(subtasks.allSatisfy { model.tasks.task($0.id)?.parentID == nil }, "removing a parent keeps its subtasks")
        model.undoRemove()
        check(subtasks.allSatisfy { model.tasks.task($0.id)?.parentID == parent.id }, "undo re-attaches them")

        // Focus on this now: starts the usual session, proposing the estimate as its length.
        guard case .created(let focusTask) = model.createTask(from: NewTaskDraft(title: "Write the intro", estimateMinutes: 30, focusNow: true)) else {
            print("tasks selftest FAILED: creating with focus"); exit(1)
        }
        check(model.focus.timer.isActive && model.focus.timer.taskID == focusTask.id, "Focus on this now starts a session on the new task")
        check(Int(model.focus.timer.duration) == 30 * 60, "the estimate is the proposed session length")
        let endsAt = model.focus.timer.endsAt
        guard case .created(let second) = model.createTask(from: NewTaskDraft(title: "Reply to Sam", estimateMinutes: 5, focusNow: true)) else {
            print("tasks selftest FAILED: creating a second focus task"); exit(1)
        }
        check(model.focus.timer.taskID == second.id && model.focus.timer.endsAt == endsAt, "a running session switches task instead of restarting")
        model.focus.stop()
        guard case .created(let long) = model.createTask(from: NewTaskDraft(title: "Rewrite the deck", estimateMinutes: 240, focusNow: true)) else {
            print("tasks selftest FAILED: creating a long task"); exit(1)
        }
        check(model.focus.timer.taskID == long.id
              && Int(model.focus.timer.duration) == model.preferences.focusSettings.minutes(for: .focus) * 60,
              "an estimate longer than a session uses the usual length")
        model.focus.stop()
        guard case .created(let quiet) = model.createTask(from: NewTaskDraft(title: "File the receipts")) else {
            print("tasks selftest FAILED: creating without focus"); exit(1)
        }
        check(!model.focus.timer.isActive && model.tasks.task(quiet.id) != nil, "without the switch no session starts")

        // A restart keeps everything, hierarchy included.
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("tasks-selftest-\(UUID().uuidString).json")
        let first = TaskStore(fileURL: file)
        let saved = BuddyTask(title: "Plan the trip", priority: .high, estimateMinutes: 60, deadline: tomorrow)
        first.add(saved)
        first.add(BuddyTask(title: "Book the train", parentID: saved.id))
        let reopened = TaskStore(fileURL: file)
        // The file keeps dates to the second, so compare fields rather than whole values.
        func same(_ a: BuddyTask, _ b: BuddyTask) -> Bool {
            a.id == b.id && a.title == b.title && a.parentID == b.parentID && a.priority == b.priority
                && a.estimateMinutes == b.estimateMinutes && a.deadline == b.deadline
                && abs(a.createdAt.timeIntervalSince(b.createdAt)) < 1 && a.updatedAt != nil && b.updatedAt != nil
        }
        check(reopened.list.tasks.count == 2 && zip(reopened.list.tasks, first.list.tasks).allSatisfy(same)
              && reopened.list.children(of: saved.id).count == 1, "tasks and subtasks survive a restart")
        try? FileManager.default.removeItem(at: file)

        print("tasks selftest: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
#endif
