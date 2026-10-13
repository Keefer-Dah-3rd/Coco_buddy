import Foundation

/// A new event, as the user confirmed it.
public struct EventDraft: Equatable, Sendable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    public var notes: String?
    /// The invitation it came from, kept on the event so the same one is never added twice.
    public var source: EventSource?

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, location: String? = nil, notes: String? = nil,
                source: EventSource? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.notes = notes
        self.source = source
    }

    /// The description as saved: the notes, then the invitation link (never dropped).
    public var description: String? {
        let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let source else { return notes.isEmpty ? nil : notes }
        if notes.contains(source.url.absoluteString) { return notes }
        let link = "\(source.name) invite: \(source.url.absoluteString)"
        return notes.isEmpty ? link : notes + "\n\n" + link
    }
}

/// Where an event came from: an invitation page such as a Partiful link.
public struct EventSource: Equatable, Sendable {
    public var name: String
    public var url: URL
    /// Stable id for the invitation ("partiful:<id>"), stored on the event in Google Calendar.
    public var key: String

    public init(name: String, url: URL, key: String) {
        self.name = name
        self.url = url
        self.key = key
    }
}

/// Changes to an existing event; only the fields set are sent.
public struct EventChanges: Equatable, Sendable {
    public var title: String?
    public var start: Date?
    public var end: Date?
    public var location: String?

    public init(title: String? = nil, start: Date? = nil, end: Date? = nil, location: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.location = location
    }

    public var isEmpty: Bool { title == nil && start == nil && end == nil && location == nil }
}

/// Google Calendar API v3, primary calendar: reading any date range, and — once the user
/// has allowed it — creating, changing and deleting events.
public enum GoogleCalendarAPI {
    static let base = "https://www.googleapis.com/calendar/v3/calendars/primary/events"
    /// Only the fields the buddy shows or needs to decide what it may change, plus the
    /// identifiers that recognise the same event in Apple Calendar (iCalUID, the original
    /// start of a repeating occurrence, when it was last changed, and Coco's own invitation
    /// key — no other private properties). Attendee lists, descriptions and other people's
    /// details are never requested.
    static let eventFields = "id,status,summary,start,end,location,hangoutLink,htmlLink,eventType,colorId,transparency,"
        + "recurringEventId,guestsCanModify,organizer(self),attendees(self,responseStatus),conferenceData(entryPoints(entryPointType,uri)),"
        + "iCalUID,originalStartTime,updated,extendedProperties/private/\(sourceProperty)"
    static let fields = "summary,nextPageToken,items(\(eventFields))"

    public static func eventsRequest(for day: Date, calendar: Calendar = .current, accessToken: String) -> URLRequest {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return eventsRequest(from: start, to: end, calendar: calendar, accessToken: accessToken)
    }

    /// Every event overlapping `start..<end`, repeating events expanded into their occurrences.
    public static func eventsRequest(from start: Date, to end: Date, calendar: Calendar = .current,
                                     pageToken: String? = nil, accessToken: String) -> URLRequest {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        var components = URLComponents(string: base)!
        components.queryItems = [
            URLQueryItem(name: "timeMin", value: formatter.string(from: start)),
            URLQueryItem(name: "timeMax", value: formatter.string(from: end)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "250"),
            URLQueryItem(name: "timeZone", value: calendar.timeZone.identifier),
            URLQueryItem(name: "fields", value: fields),
        ] + (pageToken.map { [URLQueryItem(name: "pageToken", value: $0)] } ?? [])
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Changing events

    public static func insertRequest(_ draft: EventDraft, calendar: Calendar = .current, accessToken: String) -> URLRequest {
        var body: [String: Any] = [
            "summary": draft.title,
            "start": time(draft.start, allDay: draft.isAllDay, calendar: calendar),
            "end": time(draft.end, allDay: draft.isAllDay, calendar: calendar),
        ]
        if let location = draft.location, !location.isEmpty { body["location"] = location }
        if let description = draft.description { body["description"] = description }
        if let source = draft.source {
            // Google shows the source as a link on the event; the private property finds it again.
            body["source"] = ["title": source.name, "url": source.url.absoluteString]
            body["extendedProperties"] = ["private": [sourceProperty: source.key]]
        }
        return jsonRequest("POST", url: eventURL(nil), body: body, accessToken: accessToken)
    }

    /// The private property Coco stores an invitation's key under.
    public static let sourceProperty = "cocoSource"

    /// Events Coco already created from this invitation (any date; cancelled ones excluded).
    public static func eventsRequest(sourceKey: String, calendar: Calendar = .current, accessToken: String) -> URLRequest {
        var components = URLComponents(string: base)!
        // Encoded fully: the property's value itself contains "=" and ":".
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        components.percentEncodedQueryItems = [
            ("privateExtendedProperty", "\(sourceProperty)=\(sourceKey)"),
            ("singleEvents", "true"),
            ("maxResults", "10"),
            ("timeZone", calendar.timeZone.identifier),
            ("fields", fields),
        ].map { URLQueryItem(name: $0.0, value: $0.1.addingPercentEncoding(withAllowedCharacters: unreserved)) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// PATCH keeps the event's id, attendees and everything not mentioned.
    public static func patchRequest(eventID: String, _ changes: EventChanges, calendar: Calendar = .current,
                                    accessToken: String) -> URLRequest {
        var body: [String: Any] = [:]
        if let title = changes.title { body["summary"] = title }
        if let location = changes.location { body["location"] = location }
        if let start = changes.start { body["start"] = time(start, allDay: false, calendar: calendar) }
        if let end = changes.end { body["end"] = time(end, allDay: false, calendar: calendar) }
        return jsonRequest("PATCH", url: eventURL(eventID), body: body, accessToken: accessToken)
    }

    public static func deleteRequest(eventID: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: eventURL(eventID, fields: false))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// The event as Google stored it — the only proof a change happened.
    public static func decodeEvent(_ data: Data, calendar: Calendar = .current) throws -> CalendarEvent {
        guard let item = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let event = event(from: item, calendar: calendar) else {
            throw IntegrationError.invalidResponse("Google didn't return the event.")
        }
        return event
    }

    private static func eventURL(_ id: String?, fields: Bool = true) -> URL {
        var path = base
        if let id { path += "/" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id) }
        var components = URLComponents(string: path)!
        if fields { components.queryItems = [URLQueryItem(name: "fields", value: eventFields)] }
        return components.url!
    }

    private static func time(_ date: Date, allDay: Bool, calendar: Calendar) -> [String: String] {
        if allDay {
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return ["date": String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)]
        }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = calendar.timeZone
        return ["dateTime": formatter.string(from: date), "timeZone": calendar.timeZone.identifier]
    }

    private static func jsonRequest(_ method: String, url: URL, body: [String: Any], accessToken: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return request
    }

    // MARK: Reading

    public struct Day: Equatable, Sendable {
        /// For the primary calendar this is the account's email address.
        public var calendarName: String?
        public var events: [CalendarEvent]
        /// More events in the range: ask again with this token.
        public var nextPageToken: String?
    }

    /// Parses an events.list response. Cancelled events, declined invitations and
    /// working-location markers are left out.
    public static func decodeDay(_ data: Data, calendar: Calendar = .current) throws -> Day {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw IntegrationError.invalidResponse("Calendar data wasn't JSON.")
        }
        let items = root["items"] as? [[String: Any]] ?? []
        let events = items.compactMap { event(from: $0, calendar: calendar) }
        return Day(calendarName: root["summary"] as? String, events: events, nextPageToken: root["nextPageToken"] as? String)
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
        // The same event seen through Apple Calendar carries the same iCalendar UID; an
        // event added from an invitation also carries the invitation's key.
        var keys: [String] = []
        if let uid = item["iCalUID"] as? String, !uid.isEmpty { keys.append(uid) }
        if let invitation = ((item["extendedProperties"] as? [String: Any])?["private"] as? [String: Any])?[sourceProperty] as? String,
           !invitation.isEmpty {
            keys.append(invitation)
        }
        let seriesID = item["recurringEventId"] as? String
        return CalendarEvent(
            id: id,
            title: (title?.isEmpty ?? true) ? "(No title)" : title!,
            start: start.date,
            end: end.date,
            isAllDay: start.allDay,
            location: item["location"] as? String,
            meetingLink: meeting,
            htmlLink: (item["htmlLink"] as? String).flatMap(URL.init(string:)),
            colorID: item["colorId"] as? String,
            isBusy: item["transparency"] as? String != "transparent",
            isRecurring: seriesID != nil,
            canEdit: (item["organizer"] as? [String: Any])?["self"] as? Bool == true || item["guestsCanModify"] as? Bool == true,
            provider: .google,
            calendarID: "primary",
            matchKeys: keys,
            occurrenceStart: seriesID == nil ? nil : moment(item["originalStartTime"], calendar: calendar)?.date,
            seriesID: seriesID,
            timeZone: (item["start"] as? [String: Any])?["timeZone"] as? String,
            lastModified: (item["updated"] as? String).flatMap(timestamp)
        )
    }

    /// An RFC 3339 time, with or without fractional seconds.
    private static func timestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
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
