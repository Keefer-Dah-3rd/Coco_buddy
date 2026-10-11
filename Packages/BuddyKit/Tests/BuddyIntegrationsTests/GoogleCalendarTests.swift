import Foundation
import Testing
@testable import BuddyIntegrations

@Suite struct GoogleOAuthTests {
    let client = GoogleOAuth.Client(clientID: "1234567890-abcdefghij.apps.googleusercontent.com")!

    @Test func pkceMatchesTheRFCTestVector() {
        // RFC 7636, Appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(PKCE().verifier.count >= 43)
    }

    @Test func redirectUsesTheReversedClientID() {
        #expect(client.callbackScheme == "com.googleusercontent.apps.1234567890-abcdefghij")
        #expect(client.redirectURI == "com.googleusercontent.apps.1234567890-abcdefghij:/oauth2redirect")
        #expect(GoogleOAuth.Client(clientID: "not a client id") == nil)
    }

    @Test func authorizationURLAsksForReadOnlyEventsWithPKCE() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: "xyz")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!
            .queryItems!.map { ($0.name, $0.value ?? "") })
        #expect(items["scope"] == "https://www.googleapis.com/auth/calendar.events.readonly")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["code_challenge"] == pkce.challenge)
        #expect(items["client_secret"] == nil)
    }

    @Test func callbackIsCheckedForState() throws {
        let good = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?state=abc&code=4/0Ax")!
        #expect(try GoogleOAuth.authorizationCode(from: good, expectedState: "abc") == "4/0Ax")
        let forged = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?state=evil&code=4/0Ax")!
        #expect(throws: IntegrationError.self) { try GoogleOAuth.authorizationCode(from: forged, expectedState: "abc") }
        let denied = URL(string: "com.googleusercontent.apps.x:/oauth2redirect?error=access_denied&state=abc")!
        #expect(throws: IntegrationError.cancelled) { try GoogleOAuth.authorizationCode(from: denied, expectedState: "abc") }
    }

    @Test func refreshKeepsThePreviousRefreshToken() throws {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let body = #"{"access_token":"ya29.new","expires_in":3599,"scope":"https://www.googleapis.com/auth/calendar.events.readonly","token_type":"Bearer"}"#
        let tokens = try GoogleOAuth.decodeTokens(Data(body.utf8), now: now, previousRefreshToken: "1//old")
        #expect(tokens == OAuthTokens(accessToken: "ya29.new", refreshToken: "1//old", expiresAt: now.addingTimeInterval(3599)))
        #expect(!tokens.isExpired(at: now) && tokens.isExpired(at: now.addingTimeInterval(3550)))
    }

    @Test func revokedRefreshTokenMeansReconnect() {
        let body = Data(#"{"error":"invalid_grant","error_description":"Token has been expired or revoked."}"#.utf8)
        #expect(IntegrationError.from(status: 400, body: body) == .unauthorized)
        #expect(IntegrationError.from(status: 401, body: Data()) == .unauthorized)
        #expect(IntegrationError.from(transport: URLError(.notConnectedToInternet)) == .offline)
    }
}

@Suite struct GoogleCalendarTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    let fixture = #"""
    {
      "summary": "keefer@example.com",
      "items": [
        {"id": "a", "status": "confirmed", "summary": "Design review",
         "start": {"dateTime": "2026-10-12T10:00:00-04:00"}, "end": {"dateTime": "2026-10-12T10:30:00-04:00"},
         "hangoutLink": "https://meet.google.com/abc-defg-hij", "htmlLink": "https://calendar.google.com/event?eid=a"},
        {"id": "b", "status": "cancelled", "summary": "Old sync",
         "start": {"dateTime": "2026-10-12T11:00:00-04:00"}, "end": {"dateTime": "2026-10-12T11:30:00-04:00"}},
        {"id": "c", "status": "confirmed", "summary": "Declined thing",
         "start": {"dateTime": "2026-10-12T12:00:00-04:00"}, "end": {"dateTime": "2026-10-12T13:00:00-04:00"},
         "attendees": [{"self": true, "responseStatus": "declined"}]},
        {"id": "d", "status": "confirmed", "summary": "Holiday", "start": {"date": "2026-10-12"}, "end": {"date": "2026-10-13"}},
        {"id": "e", "status": "confirmed", "eventType": "workingLocation", "summary": "Home",
         "start": {"date": "2026-10-12"}, "end": {"date": "2026-10-13"}},
        {"id": "f", "status": "confirmed",
         "start": {"dateTime": "2026-10-12T15:00:00.000-04:00"}, "end": {"dateTime": "2026-10-12T16:00:00-04:00"},
         "conferenceData": {"entryPoints": [{"entryPointType": "phone", "uri": "tel:+1"}, {"entryPointType": "video", "uri": "https://zoom.us/j/1"}]}}
      ]
    }
    """#

    @Test func decodesOnlyEventsThatMatter() throws {
        let day = try GoogleCalendarAPI.decodeDay(Data(fixture.utf8), calendar: calendar)
        #expect(day.calendarName == "keefer@example.com")
        #expect(day.events.map(\.id) == ["a", "d", "f"])
        #expect(day.events[0].meetingLink == URL(string: "https://meet.google.com/abc-defg-hij"))
        #expect(day.events[0].duration == 30 * 60)
        #expect(day.events[1].isAllDay)
        #expect(day.events[2].title == "(No title)")
        #expect(day.events[2].meetingLink == URL(string: "https://zoom.us/j/1"))
    }

    @Test func requestCoversExactlyOneLocalDay() {
        let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 15))!
        let request = GoogleCalendarAPI.eventsRequest(for: day, calendar: calendar, accessToken: "t")
        let query = request.url!.query!
        #expect(query.contains("timeMin=2026-10-12T00:00:00-04:00"))
        #expect(query.contains("timeMax=2026-10-13T00:00:00-04:00"))
        #expect(query.contains("singleEvents=true"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test func scheduleFindsNextMeetingFreeTimeAndReminders() throws {
        let events = try GoogleCalendarAPI.decodeDay(Data(fixture.utf8), calendar: calendar).events
        let schedule = DaySchedule(events: events)
        let nine = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 9))!
        #expect(schedule.allDayEvents.map(\.id) == ["d"])
        #expect(schedule.next(after: nine)?.id == "a")

        let six = DaySchedule.workdayEnd(after: nine, hour: 18, calendar: calendar)
        let blocks = schedule.freeBlocks(from: nine, until: six)
        let hours = blocks.map { calendar.component(.hour, from: $0.start) * 100 + calendar.component(.minute, from: $0.start) }
        #expect(hours == [900, 1030, 1600])
        #expect(blocks[1].duration == 4.5 * 3600)

        let nineFiftySix = nine.addingTimeInterval(56 * 60)
        #expect(schedule.reminderDue(at: nineFiftySix, lead: 5 * 60, alreadyReminded: [])?.id == "a")
        #expect(schedule.reminderDue(at: nineFiftySix, lead: 5 * 60, alreadyReminded: ["a"]) == nil)
        #expect(schedule.current(at: nineFiftySix.addingTimeInterval(10 * 60))?.id == "a")
    }

    @Test func workdayEndRollsToMidnightInTheEvening() {
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 20))!
        let end = DaySchedule.workdayEnd(after: evening, hour: 18, calendar: calendar)
        #expect(calendar.component(.day, from: end) == 13 && calendar.component(.hour, from: end) == 0)
    }

    @Test func customWorkdayEndBoundsFreeTime() {
        let two = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 14))!
        let schedule = DaySchedule(events: [])
        let early = schedule.freeBlocks(from: two, until: DaySchedule.workdayEnd(after: two, hour: 16, calendar: calendar))
        let late = schedule.freeBlocks(from: two, until: DaySchedule.workdayEnd(after: two, hour: 21, calendar: calendar))
        #expect(early.map(\.duration) == [2 * 3600])
        #expect(late.map(\.duration) == [7 * 3600])
    }
}
