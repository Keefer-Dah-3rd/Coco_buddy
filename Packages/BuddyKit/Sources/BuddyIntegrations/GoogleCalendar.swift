import Foundation

public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// Video call link (Meet or another conferencing entry point), if any.
    public var meetingLink: URL?
    /// The event in Google Calendar on the web.
    public var htmlLink: URL?

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                location: String? = nil, meetingLink: URL? = nil, htmlLink: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.meetingLink = meetingLink
        self.htmlLink = htmlLink
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Google Calendar API v3 — read-only, primary calendar, one day at a time.
public enum GoogleCalendarAPI {
    /// Only the fields the buddy shows. Attendee lists, descriptions and other people's
    /// details are never requested.
    static let fields = "summary,items(id,status,summary,start,end,location,hangoutLink,htmlLink,eventType,"
        + "attendees(self,responseStatus),conferenceData(entryPoints(entryPointType,uri)))"

    public static func eventsRequest(for day: Date, calendar: Calendar = .current, accessToken: String) -> URLRequest {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "100"),
            URLQueryItem(name: "fields", value: fields),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    public struct Day: Equatable, Sendable {
        /// For the primary calendar this is the account's email address.
        public var calendarName: String?
        public var events: [CalendarEvent]
    }

    /// Parses an events.list response. Cancelled events, declined invitations and
    /// working-location markers are left out.
    public static func decodeDay(_ data: Data, calendar: Calendar = .current) throws -> Day {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IntegrationError.invalidResponse("Calendar data wasn't JSON.")
        }
        let items = root["items"] as? [[String: Any]] ?? []
        let events = items.compactMap { event(from: $0, calendar: calendar) }
        return Day(calendarName: root["summary"] as? String, events: events)
    }

    static func event(from item: [String: Any], calendar: Calendar) -> CalendarEvent? {
        guard let id = item["id"] as? String,
              item["status"] as? String != "cancelled",
              item["eventType"] as? String != "workingLocation" else { return nil }
        let attendees = item["attendees"] as? [[String: Any]] ?? []
        if attendees.contains(where: { $0["self"] as? Bool == true && $0["responseStatus"] as? String == "declined" }) {
            return nil
        }
        guard let start = moment(item["start"], calendar: calendar),
              let end = moment(item["end"], calendar: calendar) else { return nil }

        var meeting = (item["hangoutLink"] as? String).flatMap(URL.init(string:))
        if meeting == nil, let points = (item["conferenceData"] as? [String: Any])?["entryPoints"] as? [[String: Any]] {
            meeting = points.first { $0["entryPointType"] as? String == "video" }
                .flatMap { $0["uri"] as? String }.flatMap(URL.init(string:))
        }
        let title = (item["summary"] as? String).map { $0.trimmingCharacters(in: .whitespaces) }
        return CalendarEvent(
            id: id,
            title: (title?.isEmpty ?? true) ? "(No title)" : title!,
            start: start.date,
            end: end.date,
            isAllDay: start.allDay,
            location: item["location"] as? String,
            meetingLink: meeting,
            htmlLink: (item["htmlLink"] as? String).flatMap(URL.init(string:))
        )
    }

    /// `{"dateTime": "2026-10-10T09:30:00-04:00"}` or, for all-day events, `{"date": "2026-10-10"}`.
    private static func moment(_ value: Any?, calendar: Calendar) -> (date: Date, allDay: Bool)? {
        guard let object = value as? [String: Any] else { return nil }
        if let text = object["dateTime"] as? String {
            let formatter = ISO8601DateFormatter()
            if let date = formatter.date(from: text) { return (date, false) }
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.date(from: text).map { ($0, false) }
        }
        if let text = object["date"] as? String {
            let parts = text.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
            return (date, true)
        }
        return nil
    }
}

/// Today's timed events and the gaps between them.
public struct DaySchedule: Equatable, Sendable {
    /// Timed events, sorted by start.
    public let events: [CalendarEvent]
    public let allDayEvents: [CalendarEvent]

    public init(events: [CalendarEvent]) {
        self.events = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        self.allDayEvents = events.filter(\.isAllDay)
    }

    public func current(at now: Date) -> CalendarEvent? {
        events.first { $0.start <= now && now < $0.end }
    }

    /// The next event that hasn't started yet.
    public func next(after now: Date) -> CalendarEvent? {
        events.first { $0.start > now }
    }

    /// The meeting to remind about: one starting within `lead` that hasn't been reminded yet.
    public func reminderDue(at now: Date, lead: TimeInterval, alreadyReminded: Set<String>) -> CalendarEvent? {
        events.first { event in
            let until = event.start.timeIntervalSince(now)
            return until > 0 && until <= lead && !alreadyReminded.contains(event.id)
        }
    }

    /// Open stretches between `from` and `until` at least `minimum` long — time for focused work.
    public func freeBlocks(from: Date, until: Date, minimum: TimeInterval = 15 * 60) -> [DateInterval] {
        guard until > from else { return [] }
        var blocks: [DateInterval] = []
        var cursor = from
        for event in events where event.end > from && event.start < until {
            if event.start > cursor, event.start.timeIntervalSince(cursor) >= minimum {
                blocks.append(DateInterval(start: cursor, end: event.start))
            }
            cursor = max(cursor, event.end)
        }
        if until.timeIntervalSince(cursor) >= minimum {
            blocks.append(DateInterval(start: cursor, end: until))
        }
        return blocks
    }

    /// The end of the working day used for free-time maths: `hour` o'clock, or midnight if that's passed.
    public static func workdayEnd(after now: Date, hour: Int = 18, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: start) ?? start
        return end > now ? end : calendar.date(byAdding: .day, value: 1, to: start)!
    }
}
