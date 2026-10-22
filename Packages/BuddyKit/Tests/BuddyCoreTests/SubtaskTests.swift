import Foundation
import Testing
@testable import BuddyCore

@Suite struct SubtaskTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Redesign portfolio › Audit, Update, Publish — added a second apart so their order is fixed.
    func portfolio() -> (TaskList, parent: BuddyTask, audit: BuddyTask, update: BuddyTask, publish: BuddyTask) {
        var list = TaskList()
        let parent = BuddyTask(title: "Redesign portfolio", createdAt: now)
        let audit = BuddyTask(title: "Audit existing case studies", createdAt: now + 1, parentID: parent.id)
        let update = BuddyTask(title: "Update the Buz case study", createdAt: now + 2, parentID: parent.id)
        let publish = BuddyTask(title: "Publish the changes", createdAt: now + 3, parentID: parent.id)
        for task in [parent, publish, audit, update] { list.add(task) }
        return (list, parent, audit, update, publish)
    }

    @Test func subtasksFollowTheirParentInTheOrderTheyWereAdded() {
        let (list, parent, audit, update, publish) = portfolio()
        let rows = list.outline(now: now, calendar: calendar)
        #expect(rows.map(\.id) == [parent.id, audit.id, update.id, publish.id])
        #expect(rows.map(\.depth) == [0, 1, 1, 1])
        #expect(rows[0].subtaskCount == 3)
        #expect(rows[0].hasSubtasks)
        #expect(!rows[1].hasSubtasks)
    }

    @Test func collapsingHidesSubtasksButKeepsTheCount() {
        let (list, parent, _, _, _) = portfolio()
        let rows = list.outline(now: now, collapsed: [parent.id], calendar: calendar)
        #expect(rows.map(\.id) == [parent.id])
        #expect(rows[0].isExpanded == false)
        #expect(rows[0].subtaskCount == 3)
    }

    @Test func subtasksCompleteOnTheirOwnAndTheParentSummaryFollows() {
        var (list, parent, audit, update, publish) = portfolio()
        list.setCompleted(audit.id, true, at: now + 10)
        var rows = list.outline(now: now + 20, calendar: calendar)
        #expect(rows[0].completedSubtaskCount == 1)
        #expect(list.task(parent.id)?.isCompleted == false)

        list.setCompleted(update.id, true, at: now + 11)
        list.setCompleted(publish.id, true, at: now + 12)
        rows = list.outline(now: now + 20, calendar: calendar)
        #expect(rows[0].completedSubtaskCount == 3)
        // Finishing every subtask never finishes the parent by itself.
        #expect(list.task(parent.id)?.isCompleted == false)
    }

    @Test func aTaskCantBeItsOwnParentOrSitUnderItsOwnSubtask() {
        var (list, parent, audit, _, _) = portfolio()
        let deeper = BuddyTask(title: "Pick the screenshots", createdAt: now + 4, parentID: audit.id)
        list.add(deeper)

        #expect(list.setParent(parent.id, for: parent.id) == .isSelf)
        #expect(list.setParent(audit.id, for: parent.id) == .isDescendant)
        #expect(list.setParent(deeper.id, for: parent.id) == .isDescendant)
        #expect(list.setParent(UUID(), for: audit.id) == .notFound)
        #expect(list.task(parent.id)?.parentID == nil)

        // Moving a subtask to the top level, or under a sibling, is fine.
        #expect(list.setParent(nil, for: deeper.id) == nil)
        #expect(list.task(deeper.id)?.parentID == nil)
        #expect(list.parentProblem(audit.id, for: deeper.id) == nil)
    }

    @Test func sameTitleIsAllowedUnderDifferentParentsButNotTwiceInOnePlace() {
        var (list, parent, _, _, _) = portfolio()
        let other = BuddyTask(title: "Launch newsletter", createdAt: now)
        list.add(other)
        let publishAgain = BuddyTask(title: "publish  the changes", parentID: other.id)
        #expect(list.add(publishAgain) == .added(publishAgain))
        let duplicate = BuddyTask(title: "Publish the changes", parentID: parent.id)
        guard case .duplicate = list.add(duplicate) else {
            Issue.record("Expected a duplicate under the same parent")
            return
        }
    }

    @Test func aMissingParentIsDroppedRatherThanSaved() {
        var list = TaskList()
        let orphan = BuddyTask(title: "Floating", parentID: UUID())
        list.add(orphan)
        #expect(list.task(orphan.id)?.parentID == nil)
    }

    @Test func removingAParentKeepsItsSubtasksAndUndoPutsThemBack() {
        var (list, parent, audit, update, publish) = portfolio()
        let children = list.children(of: parent.id).map(\.id)
        let removed = list.remove(parent.id)
        #expect(removed?.id == parent.id)
        #expect(list.tasks.count == 3)
        #expect([audit, update, publish].allSatisfy { list.task($0.id)?.parentID == nil })

        list.restore(parent, children: children)
        #expect([audit, update, publish].allSatisfy { list.task($0.id)?.parentID == parent.id })
    }

    @Test func aSubtaskWhoseParentFinishedOnAnEarlierDayStandsOnItsOwn() {
        var (list, parent, audit, _, _) = portfolio()
        list.setCompleted(parent.id, true, at: now)
        let nextDay = now + 86_400
        let rows = list.outline(now: nextDay, calendar: calendar)
        #expect(!rows.contains { $0.id == parent.id })
        #expect(rows.first { $0.id == audit.id }?.depth == 0)
    }

    @Test func tasksSavedBeforeSubtasksExistedStillLoad() throws {
        let old = """
        {"tasks":[{"id":"6B1F2F3A-1111-4222-8333-944455556666","title":"Old task","notes":"","priority":3,
        "scope":"personal","createdAt":780000000,"focusMinutes":0}]}
        """
        let list = try JSONDecoder().decode(TaskList.self, from: Data(old.utf8))
        #expect(list.tasks.first?.parentID == nil)
        #expect(list.tasks.first?.updatedAt == nil)
        #expect(list.tasks.first?.priority == .high)
    }

    @Test func urgentIsTheTopPriority() {
        #expect(TaskPriority.urgent > .high)
        #expect(QuickAddParser.parse("Ship it !!!!")?.priority == .urgent)
        #expect(TaskPriority.urgent.label == "Urgent")
    }
}
