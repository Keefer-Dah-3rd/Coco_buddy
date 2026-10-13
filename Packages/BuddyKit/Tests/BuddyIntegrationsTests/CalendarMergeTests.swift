import Foundation
import Testing
@testable import BuddyIntegrations

/// One schedule from Google and Apple Calendar: the same meeting is shown once, and
/// different meetings — even close, overlapping or similarly named — never merge.
@Suite struct CalendarMergeTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func google(_ id: String, _ title: String, _ start: Date, _ end: Date, uid: String? = nil, allDay: Bool = false,
                series: String? = nil, original: Date? = nil, location: String? = nil) -> CalendarEvent {
        CalendarEvent(id: id, title: title, start: start, end: end, isAllDay: allDay, location: location,
                      isRecurring: series != nil, provider: .google, calendarID: "primary",
                      matchKeys: uid.map { [$0] } ?? [], occurrenceStart: original, seriesID: series)
    }

    func apple(_ id: String, _ title: String, _ start: Date, _ end: Date, uid: String? = nil, allDay: Bool = false,
               calendarID: String = "work", recurring: Bool = false, original: Date? = nil, location: String? = nil,
               notes: String? = nil, attendees: [String] = []) -> CalendarEvent {
        CalendarEvent(id: "apple:\(id)", title: title, start: start, end: end, isAllDay: allDay, location: location,
                      isRecurring: recurring, canEdit: false, provider: .apple, calendarID: calendarID, calendarName: "Work",
                      matchKeys: uid.map { [$0] } ?? [], occurrenceStart: original, notes: notes, attendees: attendees)
    }

    // 1. The same event in both calendars, identical details.
    @Test func sameEventInBothCalendarsShowsOnce() {
        let g = google("g1", "Design review", at(13, 10), at(13, 11), uid: "g1@google.com")
        let a = apple("A1", "Design review", at(13, 10), at(13, 11), uid: "g1@google.com")
        let merged = CalendarMerge.merge([a, g], calendar: calendar)
        #expect(merged.count == 1)
        #expect(merged[0].id == "g1")  // Google's record: the one Coco can change
        #expect(merged[0].alsoIn == [EventReference(provider: .apple, id: "apple:A1", calendarID: "work", calendarName: "Work", match: .identifier)])
        #expect(merged[0].allIDs == ["g1", "apple:A1"])
    }

    @Test func separateCopiesWithIdenticalDetailsShowOnce() {
        let g = google("g1", "Dentist", at(13, 15), at(13, 16))
        let a = apple("A1", "Dentist", at(13, 15), at(13, 16), calendarID: "home")
        let merged = CalendarMerge.merge([g, a], calendar: calendar)
        #expect(merged.count == 1)
        #expect(merged[0].alsoIn.first?.match == .details)
    }

    // 2. Slightly different titles or descriptions.
    @Test func smallTitleAndDescriptionDifferencesStillMatch() {
        let pairs = [("Design Review", "design review 🎨"), ("Sam / Keefer 1:1", "Keefer <> Sam 1:1"),
                     ("Design review", "Design review (Zoom)"), ("Café catch-up", "Cafe catch up"),
                     ("Q4 planning & budget", "Q4 planning and budget")]
        for (left, right) in pairs {
            let g = google("g", left, at(13, 10), at(13, 11))
            let a = apple("a", right, at(13, 10), at(13, 11), notes: "Agenda attached")
            #expect(CalendarMerge.merge([g, a], calendar: calendar).count == 1, "\(left) ~ \(right)")
        }
    }

    @Test func looselySimilarTitlesStaySeparate() {
        // Same time, but "Lunch" could be a different lunch: keep both rather than hide one.
        for (left, right) in [("Lunch", "Lunch with Sam"), ("Standup", "Dentist"), ("Team sync", "Board sync")] {
            let g = google("g", left, at(13, 12), at(13, 13))
            let a = apple("a", right, at(13, 12), at(13, 13))
            #expect(CalendarMerge.merge([g, a], calendar: calendar).count == 2, "\(left) vs \(right)")
        }
    }

    @Test func similarTitlesInDifferentPlacesStaySeparate() {
        let g = google("g", "Design review", at(13, 10), at(13, 11), location: "Room 4")
        let a = apple("a", "Design review (B)", at(13, 10), at(13, 11), location: "Brooklyn office")
        #expect(CalendarMerge.merge([g, a], calendar: calendar).count == 2)
    }

    @Test func differentIdentifiersNeedIdenticalTitles() {
        let g = google("g", "Design review", at(13, 10), at(13, 11), uid: "one@google.com")
        let similar = apple("a", "Design review (Zoom)", at(13, 10), at(13, 11), uid: "two@icloud.com")
        let same = apple("b", "Design Review", at(13, 10), at(13, 11), uid: "three@icloud.com", calendarID: "home")
        let merged = CalendarMerge.merge([g, similar, same], calendar: calendar)
        #expect(merged.count == 2)
        #expect(merged.first { $0.id == "g" }?.alsoIn.map(\.id) == ["apple:b"])
    }

    // 3 and 9. Different meetings on the same day, overlapping ones, back-to-back ones.
    @Test func differentMeetingsOnTheSameDayStaySeparate() {
        let events = [
            google("g1", "Standup", at(13, 9), at(13, 9, 15)),
            google("g2", "Standup", at(13, 17), at(13, 17, 15)),  // same title, later: a second standup
            apple("a1", "Standup", at(13, 9, 30), at(13, 9, 45)),  // 30 minutes later is a different event
            apple("a2", "Client call", at(13, 10), at(13, 11)),
            google("g3", "Design review", at(13, 10, 30), at(13, 11, 30)),  // overlaps the call
        ]
        let merged = CalendarMerge.merge(events, calendar: calendar)
        #expect(merged.count == 5)
        #expect(Availability.overlapping(merged).map(\.title) == ["Client call", "Design review"])
    }

    @Test func entriesInTheSameCalendarAreNeverMerged() {
        let a = google("g1", "Focus", at(13, 14), at(13, 15))
        let b = google("g2", "Focus", at(13, 14), at(13, 15))
        #expect(CalendarMerge.merge([a, b], calendar: calendar).count == 2)
        let c = apple("x", "Focus", at(13, 14), at(13, 15), uid: "same")
        let d = apple("y", "Focus", at(13, 14), at(13, 15), uid: "same")
        #expect(CalendarMerge.merge([c, d], calendar: calendar).count == 2)
    }

    @Test func copiesInTwoAppleCalendarsMerge() {
        let work = apple("w", "Offsite", at(14, 9), at(14, 17), uid: "offsite-1", calendarID: "work")
        let home = apple("h", "Offsite", at(14, 9), at(14, 17), uid: "offsite-1", calendarID: "home")
        #expect(CalendarMerge.merge([work, home], calendar: calendar).count == 1)
    }

    // 4. A repeating meeting in both calendars: merged occurrence by occurrence.
    @Test func repeatingMeetingMergesPerOccurrence() {
        var events: [CalendarEvent] = []
        for week in 0..<3 {
            let day = 13 + 7 * week
            events.append(google("weekly_\(day)", "Weekly sync", at(day, 10), at(day, 10, 30), uid: "weekly@google.com",
                                 series: "weekly", original: at(day, 10)))
            events.append(apple("W@\(day)", "Weekly sync", at(day, 10), at(day, 10, 30), uid: "weekly@google.com",
                                recurring: true, original: at(day, 10)))
        }
        let merged = CalendarMerge.merge(events, calendar: calendar)
        #expect(merged.count == 3)
        #expect(merged.map(\.id) == ["weekly_13", "weekly_20", "weekly_27"])
        #expect(merged.allSatisfy { $0.alsoIn.count == 1 && $0.alsoIn[0].match == .identifier })
    }

    @Test func twoOccurrencesOfOneSeriesNeverMerge() {
        // Same UID, a day apart (a daily series): different occurrences.
        let monday = google("d_13", "Daily", at(13, 9), at(13, 9, 15), uid: "daily", series: "d", original: at(13, 9))
        let tuesday = apple("D@14", "Daily", at(14, 9), at(14, 9, 15), uid: "daily", recurring: true, original: at(14, 9))
        #expect(CalendarMerge.merge([monday, tuesday], calendar: calendar).count == 2)
        #expect(CalendarMerge.match(monday, tuesday, calendar: calendar) == nil)
    }

    // 5. An exception: one occurrence moved.
    @Test func movedOccurrenceStillMatchesByItsOriginalTime() {
        // Moved from 10:00 to 11:30 in both calendars.
        let g = google("w_20", "Weekly sync", at(20, 11, 30), at(20, 12), uid: "weekly", series: "w", original: at(20, 10))
        let a = apple("W@20", "Weekly sync", at(20, 11, 30), at(20, 12), uid: "weekly", recurring: true, original: at(20, 10))
        #expect(CalendarMerge.merge([g, a], calendar: calendar).count == 1)

        // Moved in Google; Apple Calendar hasn't synced yet. Still one event, at Google's time.
        let stale = apple("W@20", "Weekly sync", at(20, 10), at(20, 10, 30), uid: "weekly", recurring: true, original: at(20, 10))
        let merged = CalendarMerge.merge([stale, g], calendar: calendar)
        #expect(merged.count == 1)
        #expect(merged[0].start == at(20, 11, 30))
    }

    // 6. Updated or deleted in one source.
    @Test func eventChangedInOneSourceShowsOnceAtTheServerTime() {
        let g = google("g1", "Coffee", at(15, 15), at(15, 15, 30), uid: "coffee@google.com")
        let a = apple("A", "Coffee", at(15, 14), at(15, 14, 30), uid: "coffee@google.com")  // not synced yet
        let merged = CalendarMerge.merge([a, g], calendar: calendar)
        #expect(merged.count == 1 && merged[0].start == at(15, 15))
        // Deleted in Google: the Apple copy (until it syncs) is the only one — shown once.
        #expect(CalendarMerge.merge([a], calendar: calendar).map(\.id) == ["apple:A"])
    }

    // 8. All-day events and events crossing midnight.
    @Test func allDayEventsMatchByDate() {
        let g = google("g", "Conference", at(20, 0), at(22, 0), allDay: true)  // 20–21, end exclusive
        let a = apple("a", "Conference", at(20, 0), at(22, 0), allDay: true)
        let shorter = apple("b", "Conference", at(20, 0), at(21, 0), allDay: true, calendarID: "home")
        let merged = CalendarMerge.merge([g, a, shorter], calendar: calendar)
        #expect(merged.count == 2)
        // An all-day event never merges with a timed one.
        let timed = apple("c", "Conference", at(20, 0), at(22, 0), calendarID: "other")
        #expect(CalendarMerge.match(g, timed, calendar: calendar) == nil)
    }

    @Test func eventCrossingMidnightIsOneEventOnBothDays() {
        let g = google("g", "Launch watch", at(13, 23), at(14, 1), uid: "launch")
        let a = apple("a", "Launch watch", at(13, 23), at(14, 1), uid: "launch")
        for day in [at(13, 12), at(14, 12)] {
            let shown = CalendarMerge.merge(Availability.events(on: day, from: [g, a], calendar: calendar), calendar: calendar)
            #expect(shown.map(\.id) == ["g"])
        }
    }

    // Time zones and daylight saving: instants are compared, not wall-clock text.
    @Test func sameInstantInDifferentTimeZonesMatches() {
        var g = google("g", "Call with London", at(13, 9), at(13, 10))
        g.timeZone = "America/New_York"
        var a = apple("a", "Call with London", at(13, 9), at(13, 10))  // scheduled as 14:00 London time
        a.timeZone = "Europe/London"
        let merged = CalendarMerge.merge([g, a], calendar: calendar)
        #expect(merged.count == 1 && merged[0].timeZone == "America/New_York")
    }

    @Test func daylightSavingDayEventsMatch() {
        // 2026-11-01 is the 25-hour day in New York.
        let g = google("g", "Brunch", at(1, 11, month: 11), at(1, 12, month: 11))
        let a = apple("a", "Brunch", at(1, 11, month: 11), at(1, 12, month: 11))
        let allDayG = google("h", "Fall back", at(1, 0, month: 11), at(2, 0, month: 11), allDay: true)
        let allDayA = apple("b", "Fall back", at(1, 0, month: 11), at(2, 0, month: 11), allDay: true)
        #expect(CalendarMerge.merge([g, a, allDayG, allDayA], calendar: calendar).count == 2)
    }

    @Test func estimatedEndOnlyNeedsTheSameStart() {
        let g = google("g", "Rooftop party", at(17, 19), at(17, 22), uid: "x@google.com")
        let invite = CalendarEvent(id: "partiful:abc", title: "Rooftop Party 🎉", start: at(17, 19), end: at(17, 21),
                                   canEdit: false, provider: .partiful, matchKeys: ["abc", "partiful:abc"], endIsEstimated: true)
        let merged = CalendarMerge.merge([invite, g], calendar: calendar)
        #expect(merged.count == 1 && merged[0].end == at(17, 22))
        // A Google event added from the invitation carries its key: a certain match.
        var added = google("g2", "Something else entirely", at(18, 20), at(18, 23))
        added.matchKeys = ["y@google.com", "partiful:abc"]
        #expect(CalendarMerge.match(added, invite, calendar: calendar) == .identifier)
    }

    @Test func mergedEventFillsGapsFromTheOtherCopies() {
        var g = google("g", "1:1 with Sam", at(13, 14), at(13, 14, 30), uid: "s1")
        g.isBusy = false
        let a = apple("a", "1:1 with Sam", at(13, 14), at(13, 14, 30), uid: "s1", location: "https://zoom.us/j/9",
                      notes: "Bring notes", attendees: ["Sam Lee"])
        var withLink = a
        withLink.meetingLink = URL(string: "https://zoom.us/j/9")
        let merged = CalendarMerge.merge([g, withLink], calendar: calendar)[0]
        #expect(merged.location == "https://zoom.us/j/9")
        #expect(merged.meetingLink == URL(string: "https://zoom.us/j/9"))
        #expect(merged.attendees == ["Sam Lee"] && merged.notes == "Bring notes")
        #expect(merged.isBusy)  // one copy blocks the time, so it isn't free
        #expect(merged.canEdit && merged.provider == .google)
    }

    @Test func resultDoesNotDependOnInputOrder() {
        let events = [
            google("g1", "Standup", at(13, 9), at(13, 9, 15), uid: "s"),
            apple("a1", "Standup", at(13, 9), at(13, 9, 15), uid: "s"),
            apple("a2", "Standup", at(13, 9), at(13, 9, 15), calendarID: "home"),
            google("g2", "Review", at(13, 10), at(13, 11)),
            apple("a3", "Review", at(13, 10), at(13, 11)),
            apple("a4", "Gym", at(13, 18), at(13, 19)),
        ]
        let expected = CalendarMerge.merge(events, calendar: calendar)
        #expect(expected.map(\.id) == ["g1", "g2", "apple:a4"])
        for _ in 0..<20 {
            #expect(CalendarMerge.merge(events.shuffled(), calendar: calendar) == expected)
        }
    }

    @Test func sameRecordListedTwiceCountsOnce() {
        let g = google("g1", "Standup", at(13, 9), at(13, 9, 15))
        #expect(CalendarMerge.merge([g, g], calendar: calendar).count == 1)
    }

    @Test func titleNormalization() {
        #expect(CalendarMerge.normalizedTitle("  Design   Review!! 🎨 ") == "design review")
        #expect(CalendarMerge.normalizedTitle("Invitation: Café — Q4") == "cafe q4")
        #expect(CalendarMerge.normalizedTitle("R&D") == "r and d")
        #expect(CalendarMerge.normalizedTitle("🎉") == "")
    }

    @Test func oldCachedEventsDecodeWithDefaults() throws {
        let json = #"{"id":"a","title":"Old","start":800000000,"end":800003600,"isAllDay":false,"isBusy":true,"isRecurring":false,"canEdit":true}"#
        let event = try JSONDecoder().decode(CalendarEvent.self, from: Data(json.utf8))
        #expect(event.provider == .google && event.matchKeys.isEmpty && event.alsoIn.isEmpty && !event.endIsEstimated)
        let roundTrip = try JSONDecoder().decode(CalendarEvent.self, from: JSONEncoder().encode(event))
        #expect(roundTrip == event)
    }
}

@Suite struct AppleCalendarMappingTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    func record(_ title: String = "Event", start: Date, end: Date) -> AppleEventRecord {
        AppleEventRecord(eventIdentifier: "EV1", calendarItemIdentifier: "ITEM1", externalIdentifier: "uid-1",
                         calendarID: "cal", calendarTitle: "Work", calendarColor: "#1BADF8", title: title, start: start, end: end)
    }

    @Test func timedEventKeepsItsDetails() throws {
        var r = record("  Design review ", start: at(13, 10), end: at(13, 11))
        r.timeZone = "America/New_York"
        r.location = "Room 4"
        r.lastModified = at(12, 9)
        let event = try #require(AppleCalendarMapping.event(from: r, calendar: calendar))
        #expect(event.id == "apple:EV1" && event.title == "Design review")
        #expect(event.provider == .apple && event.calendarName == "Work" && event.calendarID == "cal")
        #expect(event.matchKeys == ["uid-1"] && event.timeZone == "America/New_York" && event.location == "Room 4")
        #expect(!event.canEdit && event.isBusy && !event.isRecurring && event.occurrenceStart == nil)
        #expect(event.colorID == "#1BADF8" && event.sourceLabel == "Apple Calendar · Work")
    }

    @Test func allDayEndBecomesTheNextMidnight() throws {
        var r = record(start: at(20, 0), end: at(21, 23, 59, 59))  // EventKit: Oct 20–21
        r.isAllDay = true
        let event = try #require(AppleCalendarMapping.event(from: r, calendar: calendar))
        #expect(event.end == at(22, 0))
        #expect(Availability.events(on: at(21, 12), from: [event], calendar: calendar).count == 1)
        #expect(Availability.events(on: at(22, 12), from: [event], calendar: calendar).isEmpty)
        // Already exclusive: unchanged.
        r.end = at(22, 0)
        #expect(AppleCalendarMapping.event(from: r, calendar: calendar)?.end == at(22, 0))
    }

    @Test func repeatingOccurrencesGetTheirOwnIDs() throws {
        var first = record("Weekly sync", start: at(13, 10), end: at(13, 10, 30))
        first.isRecurring = true
        first.occurrenceDate = at(13, 10)
        first.recurrence = "weekly"
        var moved = first
        moved.start = at(20, 11)
        moved.end = at(20, 11, 30)
        moved.occurrenceDate = at(20, 10)  // originally 10:00
        let a = try #require(AppleCalendarMapping.event(from: first, calendar: calendar))
        let b = try #require(AppleCalendarMapping.event(from: moved, calendar: calendar))
        #expect(a.id != b.id && a.seriesID == b.seriesID && a.isRecurring)
        #expect(b.occurrenceStart == at(20, 10) && a.recurrence == "weekly")
    }

    @Test func cancelledAndDeclinedEventsAreLeftOut() {
        var cancelled = record(start: at(13, 10), end: at(13, 11))
        cancelled.isCancelled = true
        var declined = record(start: at(13, 10), end: at(13, 11))
        declined.isDeclined = true
        #expect(AppleCalendarMapping.event(from: cancelled, calendar: calendar) == nil)
        #expect(AppleCalendarMapping.event(from: declined, calendar: calendar) == nil)
    }

    @Test func freeTimeAndMissingTitle() throws {
        var r = record("   ", start: at(13, 10), end: at(13, 11))
        r.isFree = true
        r.externalIdentifier = ""
        let event = try #require(AppleCalendarMapping.event(from: r, calendar: calendar))
        #expect(!event.isBusy && event.title == "(No title)" && event.matchKeys.isEmpty)
    }

    @Test func videoLinksAreFoundInURLLocationOrNotes() {
        let zoom = URL(string: "https://us02web.zoom.us/j/123?pwd=x")!
        #expect(AppleCalendarMapping.meetingLink(url: zoom, location: nil, notes: nil) == zoom)
        #expect(AppleCalendarMapping.meetingLink(url: URL(string: "https://example.com"), location: "Room 4",
                                                 notes: "Join: https://meet.google.com/abc-defg-hij\nDial-in…")
                == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(AppleCalendarMapping.meetingLink(url: nil, location: "https://teams.microsoft.com/l/meetup-join/1", notes: nil) != nil)
        #expect(AppleCalendarMapping.meetingLink(url: nil, location: "https://notzoom.us.evil.com/j/1", notes: "zoom.us maybe") == nil)
    }

    @Test func recurrenceWording() {
        #expect(AppleCalendarMapping.recurrenceText(frequency: "weekly", interval: 1) == "weekly")
        #expect(AppleCalendarMapping.recurrenceText(frequency: "weekly", interval: 2) == "every 2 weeks")
        #expect(AppleCalendarMapping.recurrenceText(frequency: "daily", interval: 3) == "every 3 days")
    }

    @Test func calendarsReadByDefault() {
        #expect(AppleCalendarInfo(id: "1", title: "Work", account: "Google", kind: .calDAV, isWritable: true).isIncludedByDefault)
        #expect(!AppleCalendarInfo(id: "2", title: "Birthdays", account: "Other", kind: .birthdays, isWritable: false).isIncludedByDefault)
        #expect(!AppleCalendarInfo(id: "3", title: "US Holidays", account: "Subscribed", kind: .subscription, isWritable: false).isIncludedByDefault)
        #expect(!AppleCalendarInfo(id: "4", title: "Sam's calendar", account: "Google", kind: .calDAV, isWritable: false).isIncludedByDefault)
    }
}

@Suite struct GoogleIdentifierTests {
    @Test func googleEventsCarryCrossCalendarIdentifiers() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let json = #"""
        {"items": [
          {"id": "w_20261020T140000Z", "status": "confirmed", "summary": "Weekly sync", "iCalUID": "w@google.com",
           "recurringEventId": "w", "originalStartTime": {"dateTime": "2026-10-20T10:00:00-04:00", "timeZone": "America/New_York"},
           "start": {"dateTime": "2026-10-20T11:30:00-04:00", "timeZone": "America/New_York"},
           "end": {"dateTime": "2026-10-20T12:00:00-04:00", "timeZone": "America/New_York"},
           "updated": "2026-10-12T14:22:33.123Z"},
          {"id": "p", "status": "confirmed", "summary": "Rooftop party", "iCalUID": "p@google.com",
           "start": {"dateTime": "2026-10-17T19:00:00-04:00"}, "end": {"dateTime": "2026-10-17T22:00:00-04:00"},
           "extendedProperties": {"private": {"cocoSource": "partiful:abc"}}}
        ]}
        """#
        let events = try GoogleCalendarAPI.decodeDay(Data(json.utf8), calendar: calendar).events
        let weekly = events[0]
        #expect(weekly.matchKeys == ["w@google.com"] && weekly.seriesID == "w" && weekly.isRecurring)
        #expect(weekly.occurrenceStart == calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10)))
        #expect(weekly.timeZone == "America/New_York" && weekly.provider == .google && weekly.calendarID == "primary")
        #expect(weekly.lastModified != nil)
        #expect(events[1].matchKeys == ["p@google.com", "partiful:abc"] && events[1].occurrenceStart == nil)
        // Only what's needed: no descriptions, and of the private properties only Coco's own key.
        let fields = GoogleCalendarAPI.eventFields
        #expect(fields.contains("iCalUID") && !fields.contains("description"))
        #expect(fields.hasSuffix(",extendedProperties/private/cocoSource") && !fields.contains("extendedProperties(private)"))
    }
}
