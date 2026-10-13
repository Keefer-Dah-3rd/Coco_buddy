import Foundation

/// What Coco reads from one Apple Calendar (EventKit) event occurrence. The app copies
/// these fields out of `EKEvent` on a background thread; turning them into a
/// `CalendarEvent` is plain code, so it's tested without calendar access.
public struct AppleEventRecord: Equatable, Sendable {
    /// `EKEvent.eventIdentifier` — the same for every occurrence of a repeating event.
    public var eventIdentifier: String?
    public var calendarItemIdentifier: String
    /// The iCalendar UID (`calendarItemExternalIdentifier`). For a Google calendar added
    /// to Calendar.app, it's the same as the Google event's iCalUID.
    public var externalIdentifier: String?
    public var calendarID: String
    public var calendarTitle: String
    /// The calendar's colour, "#RRGGBB".
    public var calendarColor: String?
    public var title: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// Nil for floating events (all-day events, mostly).
    public var timeZone: String?
    public var location: String?
    public var notes: String?
    public var url: URL?
    /// When this occurrence was originally scheduled (`EKEvent.occurrenceDate`).
    public var occurrenceDate: Date?
    public var isRecurring: Bool
    /// "weekly", "every 2 weeks"… when the event repeats.
    public var recurrence: String?
    public var isFree: Bool
    public var isCancelled: Bool
    /// The user said no to the invitation.
    public var isDeclined: Bool
    public var lastModified: Date?
    /// Other participants' names (the user left out).
    public var attendees: [String]

    public init(eventIdentifier: String?, calendarItemIdentifier: String, externalIdentifier: String? = nil,
                calendarID: String, calendarTitle: String, calendarColor: String? = nil, title: String?,
                start: Date, end: Date, isAllDay: Bool = false, timeZone: String? = nil, location: String? = nil,
                notes: String? = nil, url: URL? = nil, occurrenceDate: Date? = nil, isRecurring: Bool = false,
                recurrence: String? = nil, isFree: Bool = false, isCancelled: Bool = false, isDeclined: Bool = false,
                lastModified: Date? = nil, attendees: [String] = []) {
        self.eventIdentifier = eventIdentifier
        self.calendarItemIdentifier = calendarItemIdentifier
        self.externalIdentifier = externalIdentifier
        self.calendarID = calendarID
        self.calendarTitle = calendarTitle
        self.calendarColor = calendarColor
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.occurrenceDate = occurrenceDate
        self.isRecurring = isRecurring
        self.recurrence = recurrence
        self.isFree = isFree
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.lastModified = lastModified
        self.attendees = attendees
    }
}

/// One calendar in Calendar.app, for choosing which ones Coco reads.
public struct AppleCalendarInfo: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable { case local, calDAV, exchange, subscription, birthdays }

    public var id: String
    public var title: String
    /// The account it belongs to ("iCloud", "Google", "you@example.com", "On My Mac").
    public var account: String
    public var color: String?
    public var kind: Kind
    public var isWritable: Bool

    public init(id: String, title: String, account: String, color: String? = nil, kind: Kind, isWritable: Bool) {
        self.id = id
        self.title = title
        self.account = account
        self.color = color
        self.kind = kind
        self.isWritable = isWritable
    }

    /// Read by default: your own calendars. Birthdays, subscribed calendars (holidays,
    /// sports) and read-only calendars (often someone else's) are off until switched on.
    public var isIncludedByDefault: Bool {
        isWritable && kind != .subscription && kind != .birthdays
    }
}

public enum AppleCalendarMapping {
    /// The event as Coco shows it, or nil for one that shouldn't show: cancelled, or an
    /// invitation the user declined.
    public static func event(from record: AppleEventRecord, calendar: Calendar = .current) -> CalendarEvent? {
        guard !record.isCancelled, !record.isDeclined else { return nil }
        let title = record.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = record.eventIdentifier ?? record.calendarItemIdentifier
        // Every occurrence of a repeating event shares the identifier, so the occurrence's
        // original time makes the id unique — and stable when one occurrence is moved.
        let occurrence = record.occurrenceDate ?? record.start
        let id = "apple:" + base + (record.isRecurring ? "@\(Int(occurrence.timeIntervalSince1970))" : "")
        var end = record.end
        if record.isAllDay {
            // EventKit ends an all-day event at 23:59:59 on its last day; Google (and the
            // rest of Coco) uses the next midnight.
            let lastDay = calendar.startOfDay(for: max(record.start, record.end.addingTimeInterval(-1)))
            end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? record.end
        }
        let location = record.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = record.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEvent(
            id: id,
            title: title.isEmpty ? "(No title)" : title,
            start: record.start,
            end: end,
            isAllDay: record.isAllDay,
            location: (location?.isEmpty ?? true) ? nil : location,
            meetingLink: meetingLink(url: record.url, location: location, notes: notes),
            htmlLink: nil,
            colorID: record.calendarColor,
            isBusy: !record.isFree,
            isRecurring: record.isRecurring,
            canEdit: false,
            provider: .apple,
            calendarID: record.calendarID,
            calendarName: record.calendarTitle,
            matchKeys: record.externalIdentifier.map { $0.isEmpty ? [] : [$0] } ?? [],
            occurrenceStart: record.isRecurring ? occurrence : nil,
            seriesID: record.isRecurring ? base : nil,
            recurrence: record.recurrence,
            timeZone: record.timeZone,
            notes: (notes?.isEmpty ?? true) ? nil : notes,
            attendees: record.attendees,
            lastModified: record.lastModified)
    }

    /// Hosts whose links are video calls.
    static let videoHosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com",
                             "whereby.com", "facetime.apple.com", "meet.jit.si", "around.co", "gather.town"]

    /// The video-call link, from the event's URL field, else its location, else its notes.
    public static func meetingLink(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isVideoCall(url) { return url }
        for text in [location, notes].compactMap({ $0 }) {
            if let link = links(in: text).first(where: isVideoCall) { return link }
        }
        return nil
    }

    static func isVideoCall(_ url: URL) -> Bool {
        // A meeting link has a path (/j/123, /abc-defg-hij); a bare "zoom.us" in the notes isn't one.
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), url.path.count > 1 else { return false }
        return videoHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        return detector.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap(\.url)
    }

    /// "daily", "weekly", "every 2 weeks", "monthly", "yearly".
    public static func recurrenceText(frequency: String, interval: Int) -> String {
        let unit: (one: String, many: String)
        switch frequency {
        case "daily": unit = ("daily", "days")
        case "weekly": unit = ("weekly", "weeks")
        case "monthly": unit = ("monthly", "months")
        default: unit = ("yearly", "years")
        }
        return interval <= 1 ? unit.one : "every \(interval) \(unit.many)"
    }
}
