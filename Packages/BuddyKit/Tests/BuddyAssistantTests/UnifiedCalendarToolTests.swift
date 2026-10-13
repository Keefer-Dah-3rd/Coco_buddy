import Foundation
import Testing
@testable import BuddyAssistant
@testable import BuddyIntegrations

/// What the chat is told about a schedule merged from several calendars: counts after
/// merging, where events live, what's read-only, and nothing private beyond what's asked.
@Suite struct UnifiedCalendarToolTests {
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

    @Test func findEventsIsDeclaredAndValidated() {
        let names = AssistantTools.definitions.compactMap { $0["name"]?.string }
        #expect(names.contains("find_events"))
        #expect(call("find_events", [:]) == .success(.findEvents(query: nil, daysAhead: 14, limit: 5)))
        #expect(call("find_events", ["query": "  Sam ", "days_ahead": 31, "limit": 1]) == .success(.findEvents(query: "Sam", daysAhead: 31, limit: 1)))
        for bad: JSONValue in [["days_ahead": 60], ["limit": 0], ["query": 3], ["calendar": "work"]] {
            if case .success = call("find_events", bad) { Issue.record("ran with \(bad)") }
        }
    }

    @Test func mergedEventsAreDescribedOnceWithWhereTheyLive() {
        let google = CalendarEvent(id: "g1", title: "Design review", start: at(14, 10), end: at(14, 11), provider: .google, calendarID: "primary")
        let apple = CalendarEvent(id: "apple:A", title: "Design review", start: at(14, 10), end: at(14, 11), canEdit: false,
                                  provider: .apple, calendarID: "work", calendarName: "Work", notes: "Secret agenda", attendees: ["Sam Lee"])
        let dentist = CalendarEvent(id: "apple:D", title: "Dentist", start: at(14, 15), end: at(14, 16), canEdit: false,
                                    provider: .apple, calendarID: "home", calendarName: "Home")
        let merged = CalendarMerge.merge([google, apple, dentist], calendar: calendar)
        let text = AssistantPrompt.schedule(days: [at(14, 0)], events: merged, hours: WorkingHours(startHour: 9, endHour: 18),
                                            now: at(13, 9), calendar: calendar)
        #expect(text.contains("Total: 2 timed events"))
        #expect(text.components(separatedBy: "Design review").count == 2)
        #expect(text.contains("[id g1]") && text.contains("[editable] [also in Apple Calendar · Work]"))
        #expect(text.contains("Dentist @") == false && text.contains("[Apple Calendar · Home — read only in Coco]"))
        // Notes and attendee names never go to the chat in a schedule.
        #expect(!text.contains("Secret agenda") && !text.contains("Sam Lee"))
    }

    @Test func todayNamesTheCalendarsFreeTimeAndWhatsNext() {
        let events = [
            CalendarEvent(id: "a", title: "Standup", start: at(13, 9), end: at(13, 9, 15)),
            CalendarEvent(id: "b", title: "Dentist", start: at(13, 15), end: at(13, 16), provider: .apple, calendarName: "Home"),
        ]
        let tomorrow = CalendarEvent(id: "c", title: "1:1 with Sam", start: at(14, 14), end: at(14, 14, 30))
        let text = AssistantPrompt.today(tasks: [], focus: .init("not running"), focusedMinutesToday: 0, calendarConnected: true,
                                         events: events, now: at(13, 12), workdayEndHour: 18,
                                         sources: "Google Calendar and Apple Calendar", problems: ["Apple Calendar: offline"],
                                         upcoming: [tomorrow], calendar: calendar)
        #expect(text.contains("Calendars: Google Calendar and Apple Calendar (an event in more than one is listed once)."))
        #expect(text.contains("Couldn't read Apple Calendar: offline — what follows may be incomplete."))
        // get_today writes times in the Mac's own clock format (12- or 24-hour).
        #expect(text.contains("Free stretches (20+ min) before end of day: ") && text.contains("(5h in all)"))
        #expect(text.contains("Next after today:\n- Wednesday 2026-10-14 ") && text.hasSuffix("1:1 with Sam"))

        let booked = AssistantPrompt.today(tasks: [], focus: .init("not running"), focusedMinutesToday: 0, calendarConnected: true,
                                           events: [CalendarEvent(id: "x", title: "Offsite", start: at(13, 8), end: at(13, 19))],
                                           now: at(13, 12), workdayEndHour: 18, calendar: calendar)
        #expect(booked.contains("No free stretch of 20+ min left before end of day."))
    }

    @Test func foundEventsMentionOnlyTheMatchingPerson() {
        let one = CalendarEvent(id: "a", title: "1:1", start: at(14, 14), end: at(14, 14, 30), attendees: ["Sam Lee", "Priya Shah"])
        #expect(CalendarSearch.matches(one, query: "meeting with Sam"))
        let text = AssistantPrompt.foundEvents([one], query: "Sam", through: at(27, 0), now: at(13, 12), calendar: calendar)
        #expect(text.contains("Events matching “Sam”") && text.contains("1:1") && text.contains("— with Sam Lee"))
        #expect(!text.contains("Priya"))
        #expect(AssistantPrompt.foundEvents([], query: "Sam", through: at(27, 0), now: at(13, 12), calendar: calendar)
                .hasPrefix("No events matching “Sam”"))
        #expect(AssistantPrompt.foundEvents([], query: nil, through: at(27, 0), now: at(13, 12), calendar: calendar)
                .hasPrefix("Nothing on the calendar"))
    }
}

@Suite struct CalendarSearchTests {
    func event(_ title: String, location: String? = nil, attendees: [String] = []) -> CalendarEvent {
        CalendarEvent(id: title, title: title, start: .now, end: .now.addingTimeInterval(1800), location: location, attendees: attendees)
    }

    @Test func matchesTitlePlaceAndPeople() {
        #expect(CalendarSearch.matches(event("1:1 with Sam"), query: "sam"))
        #expect(CalendarSearch.matches(event("Sync", attendees: ["Samantha Ortiz"]), query: "Sam"))  // a name's start
        #expect(CalendarSearch.matches(event("Cleaning", location: "Dr. Patel Dental"), query: "dental"))
        #expect(CalendarSearch.matches(event("Café chat"), query: "cafe"))
        #expect(!CalendarSearch.matches(event("Sync", attendees: ["Priya Shah"]), query: "Sam"))
        #expect(!CalendarSearch.matches(event("Samples review"), query: "Sa"))  // too short to be a prefix
        #expect(!CalendarSearch.matches(event("Lunch with Sam"), query: "Sam Lee"))  // every word must match
        #expect(CalendarSearch.matchingAttendees(event("x", attendees: ["Sam Lee", "Priya Shah"]), query: "my meeting with sam") == ["Sam Lee"])
    }
}

@Suite struct RelativeTimingTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    @Test func untilStart() {
        let now = at(10, 13, 9)
        #expect(RelativeTiming.untilStart(of: now.addingTimeInterval(14 * 60 + 5), now: now) == "in 15m")
        #expect(RelativeTiming.untilStart(of: now.addingTimeInterval(80 * 60), now: now) == "in 1h 20m")
        #expect(RelativeTiming.untilStart(of: now.addingTimeInterval(120 * 60), now: now) == "in 2h")
        #expect(RelativeTiming.untilStart(of: now.addingTimeInterval(4 * 3600), now: now) == "later today")
        #expect(RelativeTiming.untilStart(of: now.addingTimeInterval(-60), now: now) == "now")
        #expect(RelativeTiming.remaining(until: now.addingTimeInterval(65 * 60), now: now) == "1h 5m left")
    }

    @Test func daysCountByCalendarNotHours() {
        let lateEvening = at(10, 13, 23, 30)
        #expect(RelativeTiming.day(of: at(10, 14, 0, 30), now: lateEvening, calendar: calendar) == "Tomorrow")
        #expect(RelativeTiming.day(of: at(10, 16, 9), now: lateEvening, calendar: calendar) == "Fri")
        #expect(RelativeTiming.day(of: at(10, 24, 9), now: lateEvening, calendar: calendar) == "Oct 24")
        // Across the fall-back night (Nov 1 has 25 hours), tomorrow is still tomorrow.
        #expect(RelativeTiming.day(of: at(11, 2, 0, 10), now: at(11, 1, 0, 5), calendar: calendar) == "Tomorrow")
        #expect(RelativeTiming.day(of: at(3, 9, 23), now: at(3, 8, 0, 30), calendar: calendar) == "Tomorrow")  // spring forward
    }
}
