import Foundation
import Testing
@testable import BuddyAssistant
import BuddyIntegrations

@Suite struct EventLinkToolTests {
    /// The user is in New York.
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let now = ISO8601DateFormatter().date(from: "2026-10-13T16:00:00Z")!
    let url = URL(string: "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")!

    func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func call(_ name: String, _ input: JSONValue) -> Result<AssistantAction, AssistantTools.InputError> {
        AssistantTools.action(name: name, input: input)
    }

    @Test func theToolIsDeclaredAndValidated() {
        let names = AssistantTools.definitions.compactMap { $0["name"]?.string }
        #expect(names.contains("read_event_link"))
        #expect(call("read_event_link", ["url": " partiful.com/e/3ea9jKHiRgcLhkrJJHwX "]) == .success(.readEventLink(url: "partiful.com/e/3ea9jKHiRgcLhkrJJHwX")))
        #expect(call("read_event_link", [:]) == .failure(.invalid("url is required")))
        #expect(call("read_event_link", ["url": "x", "extra": 1]) == .failure(.invalid("unexpected field extra")))
    }

    @Test func proposalsKeepTheInviteAndOnlyAcceptPartifulEventLinks() {
        let base: [String: JSONValue] = ["title": "Gigi Flea", "date": "2026-10-25", "start_time": "17:00", "duration_minutes": 300]
        var linked = base
        linked["source_link"] = "https://www.partiful.com/e/3ea9jKHiRgcLhkrJJHwX?c=abc"
        guard case .success(.proposeEvent(let proposal)) = call("propose_event", .object(linked)) else {
            Issue.record("expected a proposal"); return
        }
        #expect(proposal.source == EventSource(name: "Partiful", url: url, key: "partiful:3ea9jKHiRgcLhkrJJHwX"))

        for bad in ["https://example.com/e/3ea9jKHiRgcLhkrJJHwX", "https://go.partiful.com/VtxO62x5", "partiful"] {
            var input = base
            input["source_link"] = .string(bad)
            guard case .failure = call("propose_event", .object(input)) else { Issue.record("accepted \(bad)"); continue }
        }
        guard case .success(.proposeEvent(let plain)) = call("propose_event", .object(base)) else { Issue.record("plain"); return }
        #expect(plain.source == nil)
    }

    @Test func timesAreConvertedToTheUsersZoneAndBothAreShown() {
        let event = LinkedEvent(id: "3ea9jKHiRgcLhkrJJHwX", url: url, title: "Gigi Flea", start: utc("2026-10-25T21:00:00Z"),
                                end: utc("2026-10-26T02:00:00Z"), timeZone: TimeZone(identifier: "America/Los_Angeles"),
                                venue: "4100 Bar", address: "1087 Manzanita St, Los Angeles, CA 90029")
        let text = AssistantPrompt.linkedEvent(event, now: now, calendar: calendar)
        #expect(text.contains("Starts: Sun 25 Oct 2026, 2:00 PM in the event's time zone (America/Los_Angeles) = Sun 25 Oct 2026, 5:00 PM the user's time (America/New_York)"))
        #expect(text.contains("Ends: Sun 25 Oct 2026, 7:00 PM in the event's time zone"))
        #expect(text.contains("propose_event with title \"Gigi Flea\", date 2026-10-25, start_time 17:00, duration_minutes 300"))
        #expect(text.contains("location \"4100 Bar, 1087 Manzanita St, Los Angeles, CA 90029\""))
        #expect(text.contains("source_link \"https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX\""))
        #expect(text.contains("give both times"))
    }

    @Test func aLateNightEventLandsOnTheUsersDate() {
        // 10:30 PM in Los Angeles is 1:30 AM the next day in New York.
        let event = LinkedEvent(id: "x1234567", url: url, title: "Late show", start: utc("2026-10-25T05:30:00Z"),
                                end: utc("2026-10-25T07:00:00Z"), timeZone: TimeZone(identifier: "America/Los_Angeles"))
        let text = AssistantPrompt.linkedEvent(event, now: now, calendar: calendar)
        #expect(text.contains("date 2026-10-25, start_time 01:30, duration_minutes 90"))
        #expect(text.contains("Sat 24 Oct 2026, 10:30 PM in the event's time zone"))
    }

    @Test func sameZoneShowsOneTime() {
        let event = LinkedEvent(id: "x1234567", url: url, title: "Bushwick Mixer", start: utc("2026-10-13T23:00:00Z"),
                                end: utc("2026-10-14T02:00:00Z"), timeZone: TimeZone(identifier: "America/New_York"),
                                address: "Brooklyn, NY")
        let text = AssistantPrompt.linkedEvent(event, now: now, calendar: calendar)
        #expect(text.contains("Starts: Tue 13 Oct 2026, 7:00 PM (America/New_York)"))
        #expect(!text.contains("give both times"))
        #expect(text.contains("start_time 19:00, duration_minutes 180"))
    }

    @Test func missingDetailsAreNamedNotGuessed() {
        let noEnd = LinkedEvent(id: "x1234567", url: url, title: "Walk club", start: utc("2026-10-18T17:30:00Z"),
                                timeZone: TimeZone(identifier: "America/New_York"))
        let text = AssistantPrompt.linkedEvent(noEnd, now: now, calendar: calendar)
        #expect(text.contains("Ends: not listed"))
        #expect(text.contains("No end time is listed: ask how long to block"))
        #expect(!text.contains("duration_minutes "))
        #expect(text.contains("Where: not listed"))

        let noDate = LinkedEvent(id: "x1234567", url: url, title: "Secret dinner")
        let undated = AssistantPrompt.linkedEvent(noDate, now: now, calendar: calendar)
        #expect(undated.contains("Date and time: not listed"))
        #expect(!undated.contains("propose_event"))

        let noZone = LinkedEvent(id: "x1234567", url: url, title: "Picnic", start: utc("2026-10-18T17:30:00Z"), end: utc("2026-10-18T19:30:00Z"))
        #expect(AssistantPrompt.linkedEvent(noZone, now: now, calendar: calendar).contains("doesn't state a time zone"))
    }

    @Test func pastCancelledAndVeryLongEvents() {
        let past = LinkedEvent(id: "x1234567", url: url, title: "Old party", start: utc("2026-10-01T23:00:00Z"), end: utc("2026-10-02T02:00:00Z"))
        let pastText = AssistantPrompt.linkedEvent(past, now: now, calendar: calendar)
        #expect(pastText.contains("in the past"))
        #expect(!pastText.contains("propose_event"))

        let cancelled = LinkedEvent(id: "x1234567", url: url, title: "Rained out", start: utc("2026-10-20T23:00:00Z"), isCancelled: true)
        let cancelledText = AssistantPrompt.linkedEvent(cancelled, now: now, calendar: calendar)
        #expect(cancelledText.contains("CANCELLED"))
        #expect(!cancelledText.contains("propose_event"))

        let festival = LinkedEvent(id: "x1234567", url: url, title: "Festival", start: utc("2026-10-20T14:00:00Z"), end: utc("2026-10-21T14:00:00Z"))
        let longText = AssistantPrompt.linkedEvent(festival, now: now, calendar: calendar)
        #expect(longText.contains("It runs over 12 hours"))
        #expect(!longText.contains("duration_minutes 1440"))
    }

    @Test func thePromptTellsHerHowToHandleInvites() {
        let prompt = AssistantPrompt.system(name: "Coco")
        #expect(prompt.contains("call read_event_link"))
        #expect(prompt.contains("never fill in a missing date, start, end, time zone or place"))
        #expect(prompt.contains("pass the source_link"))
    }

    @Test func readOnlyCalendarsLeaveOutTheChangingTools() {
        let all = AssistantTools.definitions.compactMap { $0["name"]?.string }
        let readOnly = AssistantTools.definitions(canChangeCalendar: false).compactMap { $0["name"]?.string }
        #expect(Set(all).subtracting(readOnly) == AssistantTools.calendarChangeTools)
        #expect(readOnly.contains("get_schedule") && readOnly.contains("read_event_link") && readOnly.contains("propose_tasks"))
        #expect(AssistantTools.definitions(canChangeCalendar: true).count == all.count)

        let prompt = AssistantPrompt.system(name: "Coco", canChangeCalendar: false)
        #expect(prompt.contains("connected read-only: you can't add, move or delete events"))
        #expect(!prompt.contains("propose_event"))
        #expect(prompt.contains("never fill in a missing date"))
        #expect(prompt.contains("can't browse, message anyone, run commands"))
    }
}
