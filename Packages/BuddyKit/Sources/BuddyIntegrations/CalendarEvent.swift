import Foundation

/// Where an event lives. Only Google Calendar events can be changed through Coco; the
/// others are read-only here and are changed in their own apps.
public enum CalendarProvider: String, Codable, Sendable, CaseIterable {
    case google, apple, partiful

    public var displayName: String {
        switch self {
        case .google: "Google Calendar"
        case .apple: "Apple Calendar"
        case .partiful: "Partiful"
        }
    }
}

/// One source record behind an event shown in Coco.
public struct EventReference: Codable, Equatable, Hashable, Sendable {
    /// How a record was found to be the same event as the one shown.
    public enum Match: String, Codable, Sendable {
        /// Same calendar-item identifier (iCalendar UID or invitation id) and the same
        /// occurrence: one event, synced to both places. Changing one changes the other.
        case identifier
        /// Same time and (nearly) the same title, but no shared identifier: probably a
        /// separate copy, which changing the other one won't touch.
        case details
    }

    public var provider: CalendarProvider
    public var id: String
    public var calendarID: String?
    public var calendarName: String?
    public var match: Match?

    public init(provider: CalendarProvider, id: String, calendarID: String? = nil, calendarName: String? = nil, match: Match? = nil) {
        self.provider = provider
        self.id = id
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.match = match
    }

    /// "Google Calendar", "Apple Calendar · Work", "Partiful".
    public var label: String {
        guard provider == .apple, let calendarName, !calendarName.isEmpty else { return provider.displayName }
        return "\(provider.displayName) · \(calendarName)"
    }
}

/// One event occurrence, normalized the same way whichever calendar it came from.
public struct CalendarEvent: Codable, Equatable, Identifiable, Sendable {
    /// Unique across providers. Google's own id for Google events (one per occurrence);
    /// "apple:…" and "partiful:…" for the others.
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var location: String?
    /// Video call link (Meet, Zoom, Teams…), if any.
    public var meetingLink: URL?
    /// The event on the web (Google Calendar, or the invitation page).
    public var htmlLink: URL?
    /// Google's event colour ("1"–"11"), or a calendar colour as "#RRGGBB".
    public var colorID: String?
    /// False when the event is marked "Free" — it doesn't block time.
    public var isBusy: Bool
    /// One occurrence of a repeating event.
    public var isRecurring: Bool
    /// Coco may move or delete it: a Google event the user organises (or may modify).
    public var canEdit: Bool

    // Where it came from, and what's needed to find the same event elsewhere.
    public var provider: CalendarProvider
    public var calendarID: String?
    public var calendarName: String?
    /// Stable identifiers shared across providers: the iCalendar UID, an invitation key
    /// ("partiful:<id>"). Two records sharing one, for the same occurrence, are one event.
    public var matchKeys: [String]
    /// For an occurrence of a repeating event: when it was originally scheduled (it may
    /// have been moved since). Tells occurrences of the same series apart.
    public var occurrenceStart: Date?
    /// The repeating series this occurrence belongs to, in its own provider.
    public var seriesID: String?
    /// How it repeats, in words ("weekly"), when the provider says.
    public var recurrence: String?
    /// The time zone the event was scheduled in (an identifier such as "Europe/London").
    public var timeZone: String?
    /// The description. Kept on this Mac only — never sent to the chat.
    public var notes: String?
    /// Other people's names. Kept on this Mac only, for finding "my next meeting with…".
    public var attendees: [String]
    public var lastModified: Date?
    /// No end was set, so the end shown is a default length (Partiful uses two hours).
    public var endIsEstimated: Bool
    /// The other records merged into this one because they're the same event in another
    /// calendar. Set only on events shown after de-duplication.
    public var alsoIn: [EventReference]

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                location: String? = nil, meetingLink: URL? = nil, htmlLink: URL? = nil,
                colorID: String? = nil, isBusy: Bool = true, isRecurring: Bool = false, canEdit: Bool = true,
                provider: CalendarProvider = .google, calendarID: String? = nil, calendarName: String? = nil,
                matchKeys: [String] = [], occurrenceStart: Date? = nil, seriesID: String? = nil, recurrence: String? = nil,
                timeZone: String? = nil, notes: String? = nil, attendees: [String] = [], lastModified: Date? = nil,
                endIsEstimated: Bool = false, alsoIn: [EventReference] = []) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.meetingLink = meetingLink
        self.htmlLink = htmlLink
        self.colorID = colorID
        self.isBusy = isBusy
        self.isRecurring = isRecurring
        self.canEdit = canEdit
        self.provider = provider
        self.calendarID = calendarID
        self.calendarName = calendarName
        self.matchKeys = matchKeys
        self.occurrenceStart = occurrenceStart
        self.seriesID = seriesID
        self.recurrence = recurrence
        self.timeZone = timeZone
        self.notes = notes
        self.attendees = attendees
        self.lastModified = lastModified
        self.endIsEstimated = endIsEstimated
        self.alsoIn = alsoIn
    }

    public var duration: TimeInterval { end.timeIntervalSince(start) }
    public var interval: DateInterval { DateInterval(start: start, end: max(start, end)) }

    /// This record, as a reference.
    public var reference: EventReference {
        EventReference(provider: provider, id: id, calendarID: calendarID, calendarName: calendarName)
    }

    /// Every source record behind what's shown: this one first, then the merged copies.
    public var references: [EventReference] { [reference] + alsoIn }

    /// Every id this event is known by, in any calendar.
    public var allIDs: Set<String> { Set(references.map(\.id)) }

    /// "Google Calendar", "Apple Calendar · Work", "Partiful".
    public var sourceLabel: String { reference.label }

    /// Every calendar it's in, for a tooltip: "Google Calendar + Apple Calendar · Work".
    public var sourcesDescription: String { references.map(\.label).joined(separator: " + ") }

    // Events cached before these fields existed decode with the defaults.
    private enum CodingKeys: String, CodingKey {
        case id, title, start, end, isAllDay, location, meetingLink, htmlLink, colorID, isBusy, isRecurring, canEdit
        case provider, calendarID, calendarName, matchKeys, occurrenceStart, seriesID, recurrence, timeZone, notes
        case attendees, lastModified, endIsEstimated, alsoIn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            title: try c.decode(String.self, forKey: .title),
            start: try c.decode(Date.self, forKey: .start),
            end: try c.decode(Date.self, forKey: .end),
            isAllDay: try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false,
            location: try c.decodeIfPresent(String.self, forKey: .location),
            meetingLink: try c.decodeIfPresent(URL.self, forKey: .meetingLink),
            htmlLink: try c.decodeIfPresent(URL.self, forKey: .htmlLink),
            colorID: try c.decodeIfPresent(String.self, forKey: .colorID),
            isBusy: try c.decodeIfPresent(Bool.self, forKey: .isBusy) ?? true,
            isRecurring: try c.decodeIfPresent(Bool.self, forKey: .isRecurring) ?? false,
            canEdit: try c.decodeIfPresent(Bool.self, forKey: .canEdit) ?? true,
            provider: try c.decodeIfPresent(CalendarProvider.self, forKey: .provider) ?? .google,
            calendarID: try c.decodeIfPresent(String.self, forKey: .calendarID),
            calendarName: try c.decodeIfPresent(String.self, forKey: .calendarName),
            matchKeys: try c.decodeIfPresent([String].self, forKey: .matchKeys) ?? [],
            occurrenceStart: try c.decodeIfPresent(Date.self, forKey: .occurrenceStart),
            seriesID: try c.decodeIfPresent(String.self, forKey: .seriesID),
            recurrence: try c.decodeIfPresent(String.self, forKey: .recurrence),
            timeZone: try c.decodeIfPresent(String.self, forKey: .timeZone),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            attendees: try c.decodeIfPresent([String].self, forKey: .attendees) ?? [],
            lastModified: try c.decodeIfPresent(Date.self, forKey: .lastModified),
            endIsEstimated: try c.decodeIfPresent(Bool.self, forKey: .endIsEstimated) ?? false,
            alsoIn: try c.decodeIfPresent([EventReference].self, forKey: .alsoIn) ?? [])
    }
}
