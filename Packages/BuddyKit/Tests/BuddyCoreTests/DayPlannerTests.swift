import Foundation
import Testing
@testable import BuddyCore

@Suite struct DayPlannerTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000 + 36_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }

    @Test func overdueBeatsEverything() {
        let late = BuddyTask(title: "late", deadline: day(-1))
        let urgent = BuddyTask(title: "urgent", priority: .high)
        let pick = DayPlanner.suggestion(from: [urgent, late], now: now, calendar: calendar)
        #expect(pick == .init(taskID: late.id, reason: .overdue))
    }

    @Test func dueTodayBeatsHighPriority() {
        let due = BuddyTask(title: "due", deadline: day(0))
        let urgent = BuddyTask(title: "urgent", priority: .high)
        #expect(DayPlanner.suggestion(from: [urgent, due], now: now, calendar: calendar)?.reason == .dueToday)
    }

    @Test func highPriorityThenQuickWinsThenAge() {
        let old = BuddyTask(title: "old", createdAt: day(-3))
        let quick = BuddyTask(title: "quick", estimateMinutes: 10, createdAt: day(0))
        #expect(DayPlanner.suggestion(from: [old, quick], now: now, calendar: calendar)?.reason == .quickWin)

        let high = BuddyTask(title: "high", priority: .high)
        #expect(DayPlanner.suggestion(from: [old, quick, high], now: now, calendar: calendar)?.taskID == high.id)

        let pick = DayPlanner.suggestion(from: [BuddyTask(title: "new", createdAt: day(0)), old], now: now, calendar: calendar)
        #expect(pick == .init(taskID: old.id, reason: .nextInLine))
    }

    @Test func ignoresCompletedWork() {
        let done = BuddyTask(title: "done", priority: .high, completedAt: now)
        #expect(DayPlanner.suggestion(from: [done], now: now, calendar: calendar) == nil)
    }
}

@Suite struct FocusLogTests {
    let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func summarisesTodayAndSkipsMisclicks() {
        var log = FocusLog()
        log.record(.init(taskID: nil, endedAt: now, seconds: 25 * 60, finished: true))
        log.record(.init(taskID: nil, endedAt: now, seconds: 10 * 60, finished: false))
        log.record(.init(taskID: nil, endedAt: now, seconds: 20, finished: false))
        log.record(.init(taskID: nil, endedAt: now.addingTimeInterval(-86_400 * 2), seconds: 3600, finished: true))
        #expect(log.summary(on: now) == .init(minutes: 35, sessions: 2))
    }

    @Test func forgetsOldSessions() {
        var log = FocusLog()
        log.record(.init(taskID: nil, endedAt: now.addingTimeInterval(-86_400 * 40), seconds: 600, finished: true))
        log.record(.init(taskID: nil, endedAt: now, seconds: 600, finished: true))
        #expect(log.sessions.count == 1)
    }
}

@Suite struct TodayOnlyTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let today = Date(timeIntervalSinceReferenceDate: 800_000_000 + 36_000)
    var yesterday: Date { today.addingTimeInterval(-86_400) }

    @Test func quickAddMarksTodayOnly() {
        #expect(QuickAddParser.parse("Water plants @today ~5m")
                == .init(title: "Water plants", estimateMinutes: 5, scope: .today))
    }

    @Test func leftoversCanBeCarriedOver() {
        var list = TaskList()
        let scratch = BuddyTask(title: "scratch", scope: .today, createdAt: yesterday)
        list.add(scratch)
        list.add(BuddyTask(title: "kept", createdAt: yesterday))
        #expect(list.leftovers(now: today, calendar: calendar).map(\.title) == ["scratch"])
        #expect(!list.today(now: today, calendar: calendar).contains { $0.id == scratch.id })

        list.carryOver([scratch.id], to: today, calendar: calendar)
        #expect(list.leftovers(now: today, calendar: calendar).isEmpty)
        #expect(list.today(now: today, calendar: calendar).contains { $0.id == scratch.id })
    }

    @Test func deadlinesBreakPriorityTies() {
        var list = TaskList()
        list.add(BuddyTask(title: "later", deadline: today.addingTimeInterval(86_400 * 3), createdAt: yesterday))
        list.add(BuddyTask(title: "sooner", deadline: today, createdAt: today))
        list.add(BuddyTask(title: "none", createdAt: yesterday))
        #expect(list.today(now: today, calendar: calendar).map(\.title) == ["sooner", "later", "none"])
    }
}
