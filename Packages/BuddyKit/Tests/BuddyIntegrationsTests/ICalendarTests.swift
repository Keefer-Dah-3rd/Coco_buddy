import Foundation
import Testing
@testable import BuddyIntegrations

@Suite struct ICalendarTests {
    let newYork: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    /// Shaped like Partiful's own calendar files: folded with tabs, escaped commas, UTC times,
    /// and DURATION instead of DTEND when the host set no end.
    let partifulFeed = """
    BEGIN:VCALENDAR\r
    VERSION:2.0\r
    PRODID:Partiful\r
    X-WR-CALNAME:Partiful\r
    METHOD:PUBLISH\r
    BEGIN:VEVENT\r
    UID:3ea9jKHiRgcLhkrJJHwX\r
    SUMMARY:Gigi Flea 🕸️ 4100 Bar\r
    DTSTART:20261025T210000Z\r
    DTEND:20261026T020000Z\r
    DESCRIPTION:View this event on Partiful at https://partiful.com/e/3ea9jKHiR\r
    \tgcLhkrJJHwX\\n\\nCostumes encouraged\\, free entry\r
    URL:https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX\r
    LOCATION:4100 Bar\\, 1087 Manzanita St\\, Los Angeles\\, CA\r
    STATUS:CONFIRMED\r
    BEGIN:VALARM\r
    TRIGGER:-PT1H\r
    DESCRIPTION:Reminder\r
    END:VALARM\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:EaVFNA72dpUYV2gffcdM\r
    SUMMARY:Golden Gate Walk Club\r
    DTSTART:20261018T173000Z\r
    DURATION:PT2H\r
    URL:https://partiful.com/e/EaVFNA72dpUYV2gffcdM\r
    STATUS:TENTATIVE\r
    END:VEVENT\r
    BEGIN:VEVENT\r
    UID:Cancelled000000001\r
    SUMMARY:Rained out\r
    DTSTART:20261020T230000Z\r
    STATUS:CANCELLED\r
    END:VEVENT\r
    END:VCALENDAR\r

    """

    @Test func readsAPartifulFeed() throws {
        let feed = try #require(ICalendar.parse(partifulFeed, calendar: newYork))
        #expect(feed.name == "Partiful")
        #expect(feed.producer == "Partiful")
        #expect(feed.events.count == 3)

        let flea = feed.events[0]
        #expect(flea.uid == "3ea9jKHiRgcLhkrJJHwX")
        #expect(flea.title == "Gigi Flea 🕸️ 4100 Bar")
        #expect(flea.start == utc("2026-10-25T21:00:00Z"))
        #expect(flea.end == utc("2026-10-26T02:00:00Z"))
        #expect(flea.endListed)
        #expect(flea.location == "4100 Bar, 1087 Manzanita St, Los Angeles, CA")
        #expect(flea.url?.absoluteString == "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")
        #expect(flea.description == "View this event on Partiful at https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX\n\nCostumes encouraged, free entry")
        #expect(flea.status == .confirmed)

        let walk = feed.events[1]
        #expect(walk.end == utc("2026-10-18T19:30:00Z"))
        #expect(!walk.endListed)
        #expect(walk.status == .tentative)
        #expect(walk.location == nil)

        #expect(feed.events[2].status == .cancelled)
        #expect(feed.events[2].end == feed.events[2].start)
    }

    @Test func timeZonesFloatingTimesAndWholeDays() throws {
        let text = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:a
        SUMMARY:Zoned
        DTSTART;TZID=America/Los_Angeles:20261025T140000
        DTEND;TZID=America/Los_Angeles:20261025T190000
        END:VEVENT
        BEGIN:VEVENT
        UID:b
        SUMMARY:Floating
        DTSTART:20261025T090000
        DURATION:P1DT30M
        END:VEVENT
        BEGIN:VEVENT
        UID:c
        SUMMARY:Festival
        DTSTART;VALUE=DATE:20261031
        END:VEVENT
        BEGIN:VEVENT
        UID:d
        SUMMARY;LANGUAGE=en:Quoted "param"
        DTSTART;TZID="America/Chicago":20261101T180000
        END:VEVENT
        END:VCALENDAR
        """
        let events = try #require(ICalendar.parse(text, calendar: newYork)).events
        #expect(events[0].start == utc("2026-10-25T21:00:00Z"))
        #expect(events[0].end == utc("2026-10-26T02:00:00Z"))
        #expect(events[1].start == utc("2026-10-25T13:00:00Z"))  // floating = the user's own zone
        #expect(events[1].end == utc("2026-10-26T13:30:00Z"))
        #expect(events[2].isAllDay)
        #expect(events[2].start == utc("2026-10-31T04:00:00Z"))
        #expect(events[2].end == utc("2026-11-01T04:00:00Z"))
        #expect(events[3].title == "Quoted \"param\"")
        #expect(events[3].start == utc("2026-11-02T00:00:00Z"))
    }

    @Test func notACalendarAndBrokenEvents() {
        #expect(ICalendar.parse("<html>Sign in</html>") == nil)
        let feed = ICalendar.parse("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nSUMMARY:No start\nEND:VEVENT\nEND:VCALENDAR")
        #expect(feed?.events.isEmpty == true)
    }

    @Test func durations() {
        #expect(ICalendar.duration("PT2H") == 7_200)
        #expect(ICalendar.duration("P1W") == 604_800)
        #expect(ICalendar.duration("P1DT2H3M4S") == 93_784)
        #expect(ICalendar.duration("-PT15M") == -900)
        #expect(ICalendar.duration("2H") == nil)
        #expect(ICalendar.duration("PT2") == nil)
    }
}

@Suite struct CalendarFeedLinkTests {
    @Test func acceptsSubscriptionLinks() throws {
        #expect(try CalendarFeedLink.validate("webcal://api.partiful.com/calendar/abc123.ics").get().absoluteString
                == "https://api.partiful.com/calendar/abc123.ics")
        #expect(try CalendarFeedLink.validate(" https://partiful.com/api/ical/u/abc?token=xyz ").get().absoluteString
                == "https://partiful.com/api/ical/u/abc?token=xyz")
        #expect(try CalendarFeedLink.validate("http://example.com/feed.ics").get().scheme == "https")
    }

    @Test func refusesTheWrongThings() {
        #expect(CalendarFeedLink.validate("https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX") == .failure(.invitationLink))
        #expect(CalendarFeedLink.validate("https://go.partiful.com/VtxO62x5") == .failure(.invitationLink))
        for local in ["https://localhost/feed.ics", "https://127.0.0.1/feed.ics", "https://192.168.1.10/feed.ics",
                      "https://[::1]/feed.ics", "https://printer.local/feed.ics", "https://intranet/feed.ics",
                      "https://metadata.internal/feed.ics", "https://169.254.169.254/latest"] {
            #expect(CalendarFeedLink.validate(local) == .failure(.notPublic), "\(local)")
        }
        #expect(CalendarFeedLink.validate("https://me:pw@example.com/feed.ics") == .failure(.notALink))
        #expect(CalendarFeedLink.validate("ftp://example.com/feed.ics") == .failure(.notALink))
        #expect(CalendarFeedLink.validate("") == .failure(.notALink))
        #expect(!CalendarFeedLink.mayFetch(URL(string: "https://example.com:8443/feed.ics")!))
    }
}

@Suite struct ICalendarRecurrenceTests {
    let newYork: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    func events(_ body: String) -> [ICalendar.Event] {
        ICalendar.parse("BEGIN:VCALENDAR\n" + body + "\nEND:VCALENDAR", calendar: newYork)!.events
    }

    func starts(_ list: [ICalendar.Event]) -> [String] {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return list.map { formatter.string(from: $0.start) }
    }

    @Test func weeklyWithRemovedMovedAndCancelledOccurrences() {
        // Mon/Wed/Fri 9:00 New York, like Google writes it.
        let feed = events("""
        BEGIN:VEVENT
        UID:standup@google.com
        SUMMARY:Standup
        DTSTART;TZID=America/New_York:20261005T090000
        DTEND;TZID=America/New_York:20261005T091500
        RRULE:FREQ=WEEKLY;BYDAY=MO,WE,FR
        EXDATE;TZID=America/New_York:20261014T090000
        END:VEVENT
        BEGIN:VEVENT
        UID:standup@google.com
        RECURRENCE-ID;TZID=America/New_York:20261016T090000
        SUMMARY:Standup (late)
        DTSTART;TZID=America/New_York:20261016T103000
        DTEND;TZID=America/New_York:20261016T104500
        END:VEVENT
        BEGIN:VEVENT
        UID:standup@google.com
        RECURRENCE-ID;TZID=America/New_York:20261019T090000
        SUMMARY:Standup
        DTSTART;TZID=America/New_York:20261019T090000
        STATUS:CANCELLED
        END:VEVENT
        """)
        let shown = ICalendar.expand(feed, from: utc("2026-10-12T00:00:00Z"), to: utc("2026-10-24T00:00:00Z"), calendar: newYork)
        #expect(starts(shown) == ["2026-10-12T13:00:00Z", "2026-10-16T14:30:00Z", "2026-10-21T13:00:00Z", "2026-10-23T13:00:00Z"])
        #expect(shown[1].title == "Standup (late)")
        #expect(shown[1].occurrence == utc("2026-10-16T13:00:00Z"))
        #expect(shown.allSatisfy { $0.end.timeIntervalSince($0.start) == 900 })
    }

    @Test func keepsLocalTimeAcrossDaylightSaving() {
        // US clocks go back on 2026-11-01: 9:00 New York is 13:00 UTC before, 14:00 after.
        let feed = events("""
        BEGIN:VEVENT
        UID:w
        SUMMARY:Weekly
        DTSTART;TZID=America/New_York:20261026T090000
        RRULE:FREQ=WEEKLY
        END:VEVENT
        """)
        let shown = ICalendar.expand(feed, from: utc("2026-10-20T00:00:00Z"), to: utc("2026-11-04T00:00:00Z"), calendar: newYork)
        #expect(starts(shown) == ["2026-10-26T13:00:00Z", "2026-11-02T14:00:00Z"])
    }

    @Test func monthlyAndYearlyRules() {
        let feed = events("""
        BEGIN:VEVENT
        UID:second-tuesday
        SUMMARY:Book club
        DTSTART;TZID=America/New_York:20261013T190000
        RRULE:FREQ=MONTHLY;BYDAY=2TU
        END:VEVENT
        BEGIN:VEVENT
        UID:last-friday
        SUMMARY:Payday drinks
        DTSTART;TZID=America/New_York:20261030T180000
        RRULE:FREQ=MONTHLY;BYDAY=-1FR;COUNT=3
        END:VEVENT
        BEGIN:VEVENT
        UID:month-end
        SUMMARY:Invoices
        DTSTART;TZID=America/New_York:20261031T090000
        RRULE:FREQ=MONTHLY;BYMONTHDAY=31
        END:VEVENT
        BEGIN:VEVENT
        UID:birthday
        SUMMARY:Coco's birthday
        DTSTART;VALUE=DATE:20200214
        RRULE:FREQ=YEARLY
        END:VEVENT
        """)
        let shown = ICalendar.expand(feed, from: utc("2026-10-01T00:00:00Z"), to: utc("2027-03-01T00:00:00Z"), calendar: newYork)
        let byTitle = Dictionary(grouping: shown, by: \.title)
        #expect(starts(byTitle["Book club"] ?? []) == ["2026-10-13T23:00:00Z", "2026-11-11T00:00:00Z", "2026-12-09T00:00:00Z",
                                                        "2027-01-13T00:00:00Z", "2027-02-10T00:00:00Z"])
        #expect(starts(byTitle["Payday drinks"] ?? []) == ["2026-10-30T22:00:00Z", "2026-11-27T23:00:00Z", "2026-12-25T23:00:00Z"])
        #expect(starts(byTitle["Invoices"] ?? []) == ["2026-10-31T13:00:00Z", "2026-12-31T14:00:00Z", "2027-01-31T14:00:00Z"])
        #expect(starts(byTitle["Coco's birthday"] ?? []) == ["2027-02-14T05:00:00Z"])
        #expect(byTitle["Coco's birthday"]?.first?.isAllDay == true)
    }

    @Test func dailyUntilEveryOtherDayAndUnknownRules() {
        let feed = events("""
        BEGIN:VEVENT
        UID:retreat
        SUMMARY:Retreat
        DTSTART:20261020T150000Z
        RRULE:FREQ=DAILY;INTERVAL=2;UNTIL=20261026T150000Z
        END:VEVENT
        BEGIN:VEVENT
        UID:weird
        SUMMARY:Odd rule
        DTSTART:20261021T150000Z
        RRULE:FREQ=MONTHLY;BYDAY=MO,TU;BYSETPOS=-1
        END:VEVENT
        BEGIN:VEVENT
        UID:once
        SUMMARY:Once
        DTSTART:20261022T150000Z
        END:VEVENT
        """)
        let shown = ICalendar.expand(feed, from: utc("2026-10-01T00:00:00Z"), to: utc("2026-12-01T00:00:00Z"), calendar: newYork)
        let byTitle = Dictionary(grouping: shown, by: \.title)
        #expect(starts(byTitle["Retreat"] ?? []) == ["2026-10-20T15:00:00Z", "2026-10-22T15:00:00Z", "2026-10-24T15:00:00Z", "2026-10-26T15:00:00Z"])
        #expect(byTitle["Odd rule"]?.count == 1, "an unknown rule shows its first occurrence only")
        #expect(byTitle["Once"]?.count == 1)
        // Outside the window: nothing.
        #expect(ICalendar.expand(feed, from: utc("2027-01-01T00:00:00Z"), to: utc("2027-02-01T00:00:00Z"), calendar: newYork).isEmpty)
    }
}
