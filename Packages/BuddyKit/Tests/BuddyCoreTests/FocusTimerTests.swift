import Foundation
import Testing
@testable import BuddyCore

@Suite struct FocusTimerTests {
    let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    @Test func remainingIsDerivedFromTheClockNotTicks() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 25 * 60, taskID: nil, now: t0)
        // No calls in between — simulates the Mac sleeping for 10 minutes.
        #expect(timer.remaining(at: t0.addingTimeInterval(600)) == 15 * 60)
        #expect(timer.progress(at: t0.addingTimeInterval(750)) == 0.5)
    }

    @Test func pauseFreezesRemainingAndResumeShiftsTheEndDate() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 100, taskID: nil, now: t0)
        timer.pause(now: t0.addingTimeInterval(40))
        #expect(timer.remaining(at: t0.addingTimeInterval(4000)) == 60)

        timer.resume(now: t0.addingTimeInterval(5000))
        #expect(timer.endsAt == t0.addingTimeInterval(5060))
    }

    @Test func advanceFinishesExactlyOnce() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 60, taskID: nil, now: t0)
        let early = timer.advance(to: t0.addingTimeInterval(59))
        let late = timer.advance(to: t0.addingTimeInterval(3600))
        let again = timer.advance(to: t0.addingTimeInterval(3601))
        #expect(!early && late && !again)
        #expect(timer.status == .finished(at: t0.addingTimeInterval(60)))
        #expect(timer.focusStreak == 1)
    }

    @Test func stopReportsElapsedAndDoesNotCountTowardStreak() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 600, taskID: nil, now: t0)
        let elapsed = timer.stop(now: t0.addingTimeInterval(120))
        #expect(elapsed == 120)
        #expect(timer.status == .idle)
        #expect(timer.focusStreak == 0)
    }

    @Test func clockSetBackwardsNeverShowsMoreThanTheDuration() {
        var timer = FocusTimer()
        timer.start(.focus, duration: 300, taskID: nil, now: t0)
        #expect(timer.remaining(at: t0.addingTimeInterval(-3600)) == 300)
    }

    @Test func suggestsLongBreakAfterConfiguredStreak() {
        var settings = FocusSettings()
        settings.sessionsBeforeLongBreak = 2
        var timer = FocusTimer()
        var now = t0
        for expected in [FocusPhase.shortBreak, .longBreak] {
            timer.start(.focus, duration: 10, taskID: nil, now: now)
            now.addTimeInterval(10)
            timer.advance(to: now)
            #expect(timer.suggestedNextPhase(settings: settings) == expected)
        }
        timer.start(.longBreak, duration: 10, taskID: nil, now: now)
        #expect(timer.focusStreak == 0)
    }

    @Test func breaksKeepTheFocusTask() {
        let task = UUID()
        var timer = FocusTimer()
        timer.start(.focus, duration: 10, taskID: task, now: t0)
        timer.start(.shortBreak, duration: 5, taskID: nil, now: t0)
        #expect(timer.taskID == task)
    }

    @Test func survivesAJSONRoundTrip() throws {
        var timer = FocusTimer()
        timer.start(.focus, duration: 90, taskID: UUID(), now: t0)
        let data = try JSONEncoder().encode(timer)
        #expect(try JSONDecoder().decode(FocusTimer.self, from: data) == timer)
    }
}
