import Foundation
import Testing
@testable import BuddyCore

@Suite struct QuickAddParserTests {
    @Test(arguments: [
        ("Draft homepage ~45m !!", "Draft homepage", TaskPriority.medium, 45),
        ("Review portfolio ~1h", "Review portfolio", .none, 60),
        ("Deep work ~1h30m !!!", "Deep work", .high, 90),
        ("Call mum ~1.5h !", "Call mum", .low, 90),
        ("Stretch ~10", "Stretch", .none, 10),
    ] as [(String, String, TaskPriority, Int)])
    func parsesTokens(input: String, title: String, priority: TaskPriority, minutes: Int) {
        let result = QuickAddParser.parse(input)
        #expect(result == .init(title: title, priority: priority, estimateMinutes: minutes))
    }

    @Test func leavesLookalikesInTheTitle() {
        let result = QuickAddParser.parse("Fix ~/.zshrc alias, wow!")
        #expect(result?.title == "Fix ~/.zshrc alias, wow!")
        #expect(result?.estimateMinutes == nil)
        #expect(result?.priority == TaskPriority.none)
    }

    @Test func rejectsEmptyTitles() {
        #expect(QuickAddParser.parse("   ") == nil)
        #expect(QuickAddParser.parse("~30m !!") == nil)
    }

    @Test func ignoresAbsurdDurations() {
        #expect(QuickAddParser.parse("Nap ~0m")?.estimateMinutes == nil)
        #expect(QuickAddParser.parse("Nap ~99h")?.estimateMinutes == nil)
    }
}

@Suite struct TaskListTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let today = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var yesterday: Date { today.addingTimeInterval(-86_400) }

    @Test func preventsDuplicateOpenTasks() {
        var list = TaskList()
        list.add(BuddyTask(title: "Send  emails"))
        let result = list.add(BuddyTask(title: "send emails "))
        guard case .duplicate = result else { Issue.record("expected duplicate"); return }
        #expect(list.tasks.count == 1)
    }

    @Test func allowsReAddingACompletedTitle() {
        var list = TaskList()
        let first = BuddyTask(title: "Stretch")
        list.add(first)
        list.setCompleted(first.id, true, at: today)
        guard case .added = list.add(BuddyTask(title: "Stretch")) else { Issue.record("expected added"); return }
    }

    @Test func unfinishedWorkRollsOverAndIsNeverAutoCompleted() {
        var list = TaskList()
        list.add(BuddyTask(title: "Old personal", createdAt: yesterday))
        list.add(BuddyTask(title: "Old scratch", scope: .today, createdAt: yesterday))
        let done = BuddyTask(title: "Done yesterday", createdAt: yesterday, completedAt: yesterday)
        list.add(done)

        let titles = list.today(now: today, calendar: calendar).map(\.title)
        #expect(titles == ["Old personal"])
        #expect(list.tasks.allSatisfy { $0.title == "Done yesterday" || !$0.isCompleted })
    }

    @Test func ordersOpenByPriorityThenAgeWithCompletedLast() {
        var list = TaskList()
        list.add(BuddyTask(title: "low", priority: .low, createdAt: today))
        list.add(BuddyTask(title: "high", priority: .high, createdAt: today.addingTimeInterval(10)))
        let finished = BuddyTask(title: "finished", priority: .high, createdAt: today)
        list.add(finished)
        list.setCompleted(finished.id, true, at: today)

        #expect(list.today(now: today, calendar: calendar).map(\.title) == ["high", "low", "finished"])
    }

    @Test func completionOnlyChangesWhenAsked() {
        var list = TaskList()
        let task = BuddyTask(title: "x")
        list.add(task)
        let completed = list.setCompleted(task.id, true, at: today)
        let completedAgain = list.setCompleted(task.id, true, at: today)
        let reopened = list.setCompleted(task.id, false, at: today)
        #expect(completed && !completedAgain && reopened)
        #expect(list.task(task.id)?.completedAt == nil)
    }
}
