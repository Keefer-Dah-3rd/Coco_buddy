import Foundation
import Testing
@testable import BuddyIntegrations

@Suite struct CalendarRangeTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()
    let nine = WorkingHours(startHour: 9, endHour: 18)

    func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false, busy: Bool = true) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end, isAllDay: allDay, isBusy: busy)
    }

    // MARK: Requests

    @Test func rangeRequestAsksForExpandedRepeatsInTheUsersTimeZone() {
        let request = GoogleCalendarAPI.eventsRequest(from: at(12, 0), to: at(19, 0), calendar: calendar,
                                                      pageToken: "next", accessToken: "token")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["timeMin"] == "2026-10-12T00:00:00-04:00")
        #expect(items["timeMax"] == "2026-10-19T00:00:00-04:00")
        #expect(items["singleEvents"] == "true")
        #expect(items["timeZone"] == "America/New_York")
        #expect(items["pageToken"] == "next")
        #expect(items["fields"]?.contains("nextPageToken") == true)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }

    @Test func readsColourAvailabilityRepeatsAndWhoCanEdit() throws {
        let body = #"""
        {"summary": "me@example.com", "nextPageToken": "p2", "items": [
          {"id": "mine", "status": "confirmed", "summary": "Standup", "colorId": "5", "recurringEventId": "base",
           "organizer": {"self": true},
           "start": {"dateTime": "2026-10-13T09:00:00-04:00"}, "end": {"dateTime": "2026-10-13T09:15:00-04:00"}},
          {"id": "theirs", "status": "confirmed", "summary": "Their meeting", "transparency": "transparent",
           "organizer": {"email": "x@example.com"},
           "start": {"dateTime": "2026-10-13T10:00:00-04:00"}, "end": {"dateTime": "2026-10-13T11:00:00-04:00"}}
        ]}
        """#
        let page = try GoogleCalendarAPI.decodeDay(Data(body.utf8), calendar: calendar)
        #expect(page.nextPageToken == "p2")
        let mine = page.events[0], theirs = page.events[1]
        #expect(mine.colorID == "5" && mine.isRecurring && mine.canEdit && mine.isBusy)
        #expect(!theirs.canEdit && !theirs.isBusy && !theirs.isRecurring)
    }

    @Test func newEventsCarryTheirTimeZoneAndAllDayEndsAreExclusive() throws {
        let timed = GoogleCalendarAPI.insertRequest(EventDraft(title: "Design review", start: at(20, 14), end: at(20, 15),
                                                               location: "Studio", notes: "Bring sketches"),
                                                    calendar: calendar, accessToken: "t")
        #expect(timed.httpMethod == "POST")
        let body = try JSONSerialization.jsonObject(with: timed.httpBody!) as! [String: Any]
        #expect(body["summary"] as? String == "Design review")
        #expect(body["location"] as? String == "Studio" && body["description"] as? String == "Bring sketches")
        let start = body["start"] as! [String: String]
        #expect(start["dateTime"] == "2026-10-20T14:00:00-04:00" && start["timeZone"] == "America/New_York")

        let allDay = GoogleCalendarAPI.insertRequest(EventDraft(title: "Offsite", start: at(21, 0), end: at(22, 0), isAllDay: true),
                                                     calendar: calendar, accessToken: "t")
        let dayBody = try JSONSerialization.jsonObject(with: allDay.httpBody!) as! [String: Any]
        #expect((dayBody["start"] as! [String: String])["date"] == "2026-10-21")
        #expect((dayBody["end"] as! [String: String])["date"] == "2026-10-22")
    }

    @Test func changesKeepTheEventAndSendOnlyWhatChanged() throws {
        let patch = GoogleCalendarAPI.patchRequest(eventID: "abc_20261020", EventChanges(start: at(21, 10), end: at(21, 11)),
                                                   calendar: calendar, accessToken: "t")
        #expect(patch.httpMethod == "PATCH")
        #expect(patch.url!.path.hasSuffix("/events/abc_20261020"))
        let body = try JSONSerialization.jsonObject(with: patch.httpBody!) as! [String: Any]
        #expect(Set(body.keys) == ["start", "end"])
        let delete = GoogleCalendarAPI.deleteRequest(eventID: "a/b", accessToken: "t")
        #expect(delete.httpMethod == "DELETE")
        #expect(delete.url!.absoluteString.hasSuffix("/events/a%2Fb"))
    }

    @Test func aCreatedEventIsOnlyBelievedFromGooglesReply() throws {
        let reply = #"{"id": "new1", "status": "confirmed", "summary": "Call", "organizer": {"self": true},"#
            + #""start": {"dateTime": "2026-10-15T13:00:00-04:00"}, "end": {"dateTime": "2026-10-15T13:30:00-04:00"}}"#
        let event = try GoogleCalendarAPI.decodeEvent(Data(reply.utf8), calendar: calendar)
        #expect(event.id == "new1" && event.start == at(15, 13) && event.canEdit)
        #expect(throws: IntegrationError.self) { try GoogleCalendarAPI.decodeEvent(Data("{}".utf8), calendar: calendar) }
    }

    @Test func askingToChangeEventsAddsToWhatWasGranted() throws {
        let client = GoogleOAuth.Client(clientID: "1234567890-abcdefghij.apps.googleusercontent.com")!
        let url = GoogleOAuth.authorizationURL(client: client, pkce: PKCE(), state: "s", allowChanges: true)
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["scope"] == GoogleOAuth.changeScope)
        #expect(items["include_granted_scopes"] == "true")
        let body = #"{"access_token":"a","expires_in":3599,"scope":"https://www.googleapis.com/auth/calendar.events.readonly https://www.googleapis.com/auth/calendar.events"}"#
        #expect(try GoogleOAuth.decodeTokens(Data(body.utf8), now: .now).canChangeEvents)
        let noScopeRecorded = OAuthTokens(accessToken: "a", refreshToken: nil, expiresAt: .now)
        #expect(!noScopeRecorded.canChangeEvents)
    }

    // MARK: Days

    @Test func lateEventsShowOnBothDaysAndAllDayEndsAreExclusive() {
        let late = event("late", at(15, 23), at(16, 1))
        let trip = event("trip", at(16, 0), at(18, 0), allDay: true)
        let all = [late, trip]
        #expect(Availability.events(on: at(15, 12), from: all, calendar: calendar).map(\.id) == ["late"])
        #expect(Availability.events(on: at(16, 12), from: all, calendar: calendar).map(\.id) == ["trip", "late"])
        #expect(Availability.events(on: at(17, 12), from: all, calendar: calendar).map(\.id) == ["trip"])
        #expect(Availability.events(on: at(18, 12), from: all, calendar: calendar).isEmpty)
    }

    @Test func emptyDayIsOpenAllWorkingHours() {
        let open = Availability.openings(on: at(14, 0), events: [], hours: nine, calendar: calendar)
        #expect(open == [DateInterval(start: at(14, 9), end: at(14, 18))])
    }

    @Test func backToBackAndOverlappingMeetingsLeaveOnlyRealGaps() {
        let events = [
            event("a", at(14, 10), at(14, 11)),
            event("b", at(14, 11), at(14, 12)),         // back to back
            event("c", at(14, 11, 30), at(14, 12, 30)), // overlaps b
            event("free", at(14, 13), at(14, 17), busy: false),
            event("d", at(14, 14), at(14, 15)),
        ]
        let open = Availability.openings(on: at(14, 0), events: events, hours: nine, calendar: calendar)
        #expect(open == [
            DateInterval(start: at(14, 9), end: at(14, 10)),
            DateInterval(start: at(14, 12, 30), end: at(14, 14)),
            DateInterval(start: at(14, 15), end: at(14, 18)),
        ])
        #expect(Availability.bookedMinutes(events, within: Availability.dayInterval(at(14, 0), calendar: calendar)) == 210)
        #expect(Set(Availability.overlapping(events).map(\.id)) == ["b", "c"])
    }

    @Test func openingsNeverStartInThePast() {
        let open = Availability.openings(on: at(14, 0), events: [], hours: nine, notBefore: at(14, 16, 20), calendar: calendar)
        #expect(open == [DateInterval(start: at(14, 16, 20), end: at(14, 18))])
    }

    @Test func workingHoursKeepTheirClockTimesAcrossDaylightSaving() {
        // 8 March 2026: clocks go forward at 2:00 in New York; 1 November: back.
        for (month, day) in [(3, 8), (11, 1)] {
            let window = nine.interval(on: at(day, 12, month: month), calendar: calendar)!
            #expect(calendar.component(.hour, from: window.start) == 9)
            #expect(calendar.component(.hour, from: window.end) == 18)
            #expect(window.duration == 9 * 3600)
        }
        let spring = Availability.dayInterval(at(8, 12, month: 3), calendar: calendar)
        #expect(spring.duration == 23 * 3600)
    }

    @Test func slotsFitBetweenEventsWithoutOverlapping() {
        let events = [event("a", at(15, 9), at(15, 10, 10)), event("b", at(15, 11), at(15, 16, 50))]
        let slots = Availability.slots(duration: 30 * 60, days: [at(15, 0), at(16, 0)], events: events, hours: nine, calendar: calendar)
        #expect(slots.first == DateInterval(start: at(15, 10, 15), duration: 1800))
        // 16:50–18:00 is open too; then the next morning.
        #expect(slots.map(\.start) == [at(15, 10, 15), at(15, 17), at(16, 9)])
        for slot in slots {
            #expect(Availability.conflicts(with: slot, in: events).isEmpty)
        }
        for (a, b) in zip(slots, slots.dropFirst()) { #expect(a.end <= b.start) }
    }

    @Test func aFullyBookedWeekHasNoSlots() {
        let days = (12...16).map { at($0, 0) }
        let events = (12...16).map { event("d\($0)", at($0, 8), at($0, 19)) }
        #expect(Availability.slots(duration: 30 * 60, days: days, events: events, hours: nine, calendar: calendar).isEmpty)
    }

    @Test func conflictsIgnoreFreeAllDayAndTheEventBeingMoved() {
        let events = [event("a", at(15, 14), at(15, 15)), event("off", at(15, 0), at(16, 0), allDay: true),
                      event("x", at(15, 14), at(15, 14, 30), busy: false)]
        let proposal = DateInterval(start: at(15, 14, 30), end: at(15, 15, 30))
        #expect(Availability.conflicts(with: proposal, in: events).map(\.id) == ["a"])
        #expect(Availability.conflicts(with: proposal, in: events, ignoring: "a").isEmpty)
    }
}
