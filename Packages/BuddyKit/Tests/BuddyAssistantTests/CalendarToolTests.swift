import Foundation
import Testing
@testable import BuddyAssistant
import BuddyIntegrations

@Suite struct CalendarToolTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func call(_ name: String, _ input: JSONValue) -> Result<AssistantAction, AssistantTools.InputError> {
        AssistantTools.action(name: name, input: input)
    }

    @Test func everyNewToolIsDeclared() {
        let names = AssistantTools.definitions.compactMap { $0["name"]?.string }
        for name in ["get_schedule", "find_free_time", "propose_event", "propose_event_change", "propose_event_deletion"] {
            #expect(names.contains(name))
        }
    }

    @Test func scheduleRangesAreRealOrderedAndBounded() {
        #expect(call("get_schedule", ["start_date": "2026-10-13", "end_date": "2026-10-19"])
                == .success(.getSchedule(from: CalendarDate(year: 2026, month: 10, day: 13), to: CalendarDate(year: 2026, month: 10, day: 19))))
        #expect(call("get_schedule", ["start_date": "2026-10-19", "end_date": "2026-10-13"]) != nil)
        if case .success = call("get_schedule", ["start_date": "2026-10-19", "end_date": "2026-10-13"]) { Issue.record("backwards range ran") }
        if case .success = call("get_schedule", ["start_date": "2026-02-30", "end_date": "2026-03-02"]) { Issue.record("impossible date ran") }
        if case .success = call("get_schedule", ["start_date": "2026-10-01", "end_date": "2026-11-15"]) { Issue.record("46 days ran") }
        if case .success = call("get_schedule", ["start_date": "tomorrow", "end_date": "2026-10-15"]) { Issue.record("words ran") }
    }

    @Test func freeTimeNeedsALengthAndASaneWindow() {
        let ok = call("find_free_time", ["start_date": "2026-10-15", "end_date": "2026-10-15", "duration_minutes": 30,
                                         "earliest": "12:00", "latest": "17:00"])
        guard case .success(.findFreeTime(let request)) = ok else { Issue.record("valid request failed"); return }
        #expect(request.durationMinutes == 30 && request.earliest?.minutes == 720 && request.latest?.minutes == 1020)
        if case .success = call("find_free_time", ["start_date": "2026-10-15", "end_date": "2026-10-15", "duration_minutes": 0]) {
            Issue.record("zero minutes ran")
        }
        if case .success = call("find_free_time", ["start_date": "2026-10-15", "end_date": "2026-10-15", "duration_minutes": 30,
                                                   "earliest": "17:00", "latest": "12:00"]) { Issue.record("inverted window ran") }
    }

    @Test func eventsNeedATimeAndLengthUnlessAllDay() {
        if case .success = call("propose_event", ["title": "Call", "date": "2026-10-15"]) { Issue.record("timeless event ran") }
        if case .success = call("propose_event", ["title": "Call", "date": "2026-10-15", "start_time": "14:00"]) {
            Issue.record("lengthless event ran")
        }
        guard case .success(.proposeEvent(let event)) = call("propose_event", ["title": " Design review ", "date": "2026-10-20",
                                                                               "start_time": "14:00", "duration_minutes": 60]) else {
            Issue.record("valid event failed"); return
        }
        #expect(event.title == "Design review" && event.start?.minutes == 840 && event.durationMinutes == 60 && !event.allDay)
        guard case .success(.proposeEvent(let offsite)) = call("propose_event", ["title": "Offsite", "date": "2026-10-21", "all_day": true]) else {
            Issue.record("all-day event failed"); return
        }
        #expect(offsite.allDay && offsite.start == nil)
    }

    @Test func changesMustChangeSomething() {
        if case .success = call("propose_event_change", ["event_id": "abc"]) { Issue.record("empty change ran") }
        #expect(call("propose_event_change", ["event_id": "abc", "date": "2026-10-21"])
                == .success(.proposeEventChange(EventChangeProposal(eventID: "abc", date: CalendarDate(year: 2026, month: 10, day: 21)))))
        #expect(call("propose_event_deletion", ["event_id": "abc"]) == .success(.proposeEventDeletion(eventID: "abc")))
    }

    @Test func scheduleTextIsExactAboutDaysTimesAndIDs() {
        let events = [
            CalendarEvent(id: "m1", title: "Standup", start: at(15, 9), end: at(15, 9, 30), isRecurring: true),
            CalendarEvent(id: "m2", title: "Their review", start: at(15, 14), end: at(15, 15), canEdit: false),
            CalendarEvent(id: "late", title: "Launch watch", start: at(15, 23), end: at(16, 1)),
        ]
        let text = AssistantPrompt.schedule(days: [at(15, 0), at(16, 0)], events: events,
                                            hours: WorkingHours(startHour: 9, endHour: 18), now: at(14, 12), calendar: calendar)
        #expect(text.contains("Thursday 2026-10-15:"))
        #expect(text.contains("09:00–09:30 (30m) Standup [id m1] [repeats] [editable]"))
        #expect(text.contains("[someone else's — read only]"))
        #expect(text.contains("23:00–(until Friday 2026-10-16 01:00)"))
        #expect(text.contains("Open within working hours (09:00–18:00): 09:30–14:00 (4h 30m), 15:00–18:00 (3h)"))
        #expect(text.contains("Friday 2026-10-16:\n- (from Thursday 2026-10-15 23:00)–01:00"))
        #expect(text.contains("Range total: 4 timed events"))
        #expect(text.contains("Lightest: Friday 2026-10-16"))
    }

    @Test func pastDaysDontOfferOpenTime() {
        let text = AssistantPrompt.schedule(days: [at(12, 0)], events: [], hours: WorkingHours(startHour: 9, endHour: 18),
                                            now: at(14, 12), calendar: calendar)
        #expect(text.contains("(In the past.)") && !text.contains("Open within"))
    }

    @Test func turnNoteSaysWhichDayTheCardShows() {
        let note = AssistantPrompt.turnNote(now: at(13, 10), events: [], viewing: at(16, 0), calendar: calendar)
        #expect(note.contains("2026-10-13, America/New_York"))
        #expect(note.contains("showing Friday 2026-10-16"))
        #expect(!AssistantPrompt.turnNote(now: at(13, 10), events: [], viewing: at(13, 0), calendar: calendar).contains("showing"))
    }
}
