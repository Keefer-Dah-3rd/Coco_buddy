import Foundation

/// Turns the events of several calendars into one list in which each real-world event
/// appears once. Display only: nothing here changes or deletes a source event.
///
/// Two records are the same event when:
/// - **identifier**: they share an iCalendar UID or invitation key and are the same
///   occurrence (repeating events are compared occurrence by occurrence, by the time each
///   occurrence was originally scheduled), or
/// - **details**: no shared identifier, but they start and end at the same minute, are
///   both all-day or both timed, and have the same title once case, punctuation, emoji and
///   spacing are ignored (or clearly the same title — see `titlesMatch`).
///
/// Records from the same calendar are never merged — two entries in one calendar are two
/// entries. When in doubt, both stay: a meeting shown twice beats a meeting hidden.
public enum CalendarMerge {
    /// The merged events, each with the other records it stands for in `alsoIn`.
    /// Order: all-day first, then by start, like `Availability.events(on:)`.
    public static func merge(_ events: [CalendarEvent], calendar: Calendar = .current) -> [CalendarEvent] {
        // The same record listed twice (e.g. from overlapping fetches) counts once.
        var seen = Set<String>()
        let records = events
            .filter { seen.insert("\($0.provider.rawValue)|\($0.id)").inserted }
            .sorted(by: processingOrder)

        var groups: [[CalendarEvent]] = []
        var matches: [[EventReference.Match]] = []
        for record in records {
            var best: (group: Int, match: EventReference.Match)?
            for (index, group) in groups.enumerated() where !group.contains(where: { sameCalendar($0, record) }) {
                guard let match = group.lazy.compactMap({ Self.match($0, record, calendar: calendar) })
                    .min(by: { rank($0) < rank($1) }) else { continue }
                if best == nil || rank(match) < rank(best!.match) { best = (index, match) }
                if match == .identifier { break }
            }
            if let best {
                groups[best.group].append(record)
                matches[best.group].append(best.match)
            } else {
                groups.append([record])
                matches.append([.identifier])
            }
        }
        return zip(groups, matches).map { combine($0.0, matches: $0.1) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.id) < ($1.isAllDay ? 0 : 1, $1.start, $1.id) }
    }

    /// Whether two records are the same event, and how sure that is. Nil: different events.
    public static func match(_ a: CalendarEvent, _ b: CalendarEvent, calendar: Calendar = .current) -> EventReference.Match? {
        guard !sameCalendar(a, b) else { return nil }
        let sharedKey = !Set(a.matchKeys).isDisjoint(with: b.matchKeys)
        if sharedKey && sameOccurrence(a, b) { return .identifier }
        // A shared key on a repeating event but a different occurrence: a different event.
        if sharedKey && (a.isRecurring || b.isRecurring) { return nil }

        guard a.isAllDay == b.isAllDay, sameTimes(a, b, calendar: calendar) else { return nil }
        let left = normalizedTitle(a.title), right = normalizedTitle(b.title)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        if left == right { return .details }
        // Both have identifiers and they differ: only an identical title is enough.
        let conflictingIDs = !a.matchKeys.isEmpty && !b.matchKeys.isEmpty && !sharedKey
        guard !conflictingIDs, titlesMatch(left, right), placesCompatible(a.location, b.location) else { return nil }
        return .details
    }

    /// Lowercased, accents folded, "&" read as "and", everything but letters, digits and
    /// single spaces dropped, and an invitation prefix ("Invitation: ", "Fwd: ") removed.
    public static func normalizedTitle(_ title: String) -> String {
        var text = title.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "&", with: " and ")
        for prefix in ["updated invitation:", "invitation:", "fwd:", "fw:", "re:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let kept = text.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(kept).split(separator: " ").joined(separator: " ")
    }

    /// Normalized titles that are clearly the same: the same words in any order, or one
    /// title's words (at least two) all inside the other's, covering most of it.
    /// "Design review" ~ "Design review (Zoom)"; "Lunch" is NOT ~ "Lunch with Sam".
    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        let wordsA = Set(a.split(separator: " ")), wordsB = Set(b.split(separator: " "))
        if wordsA == wordsB { return true }
        let (small, large) = wordsA.count <= wordsB.count ? (wordsA, wordsB) : (wordsB, wordsA)
        return small.count >= 2 && small.isSubset(of: large) && Double(small.count) / Double(large.count) >= 0.6
    }

    // MARK: - Rules

    private static func sameCalendar(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        a.provider == b.provider && a.calendarID == b.calendarID
    }

    /// The same occurrence of a shared identifier. Single events: always (an identifier
    /// names one event, even if one copy hasn't caught up with a move yet). Repeating
    /// events: the same originally-scheduled time.
    private static func sameOccurrence(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        if !a.isRecurring && !b.isRecurring { return true }
        return sameMinute(a.occurrenceStart ?? a.start, b.occurrenceStart ?? b.start)
    }

    /// Same start and end to the minute (an estimated end isn't compared). All-day events:
    /// the same dates.
    private static func sameTimes(_ a: CalendarEvent, _ b: CalendarEvent, calendar: Calendar) -> Bool {
        if a.isAllDay {
            return calendar.isDate(a.start, inSameDayAs: b.start)
                && calendar.isDate(a.end.addingTimeInterval(-1), inSameDayAs: b.end.addingTimeInterval(-1))
        }
        return sameMinute(a.start, b.start) && (a.endIsEstimated || b.endIsEstimated || sameMinute(a.end, b.end))
    }

    private static func sameMinute(_ a: Date, _ b: Date) -> Bool { abs(a.timeIntervalSince(b)) < 60 }

    /// Places that can't be told apart: either missing, or one contains the other.
    private static func placesCompatible(_ a: String?, _ b: String?) -> Bool {
        let left = normalizedTitle(a ?? ""), right = normalizedTitle(b ?? "")
        return left.isEmpty || right.isEmpty || left.contains(right) || right.contains(left)
    }

    private static func rank(_ match: EventReference.Match) -> Int { match == .identifier ? 0 : 1 }

    /// Google first (it's the record Coco can change), then Apple, then Partiful; then
    /// time and id, so the same input always gives the same result.
    private static func processingOrder(_ a: CalendarEvent, _ b: CalendarEvent) -> Bool {
        (providerRank(a.provider), a.start, a.calendarID ?? "", a.id) < (providerRank(b.provider), b.start, b.calendarID ?? "", b.id)
    }

    private static func providerRank(_ provider: CalendarProvider) -> Int {
        switch provider {
        case .google: 0
        case .apple: 1
        case .partiful: 2
        }
    }

    // MARK: - Combining

    /// The shown event: the first record (Google's when there is one — the record Coco can
    /// change, straight from the server), with details only the other copies have filled in.
    private static func combine(_ group: [CalendarEvent], matches: [EventReference.Match]) -> CalendarEvent {
        var event = group[0]
        let others = group.dropFirst()
        event.alsoIn = zip(others, matches.dropFirst()).map { record, match in
            var reference = record.reference
            reference.match = match
            return reference
        }
        for other in others {
            if event.location?.isEmpty ?? true { event.location = other.location }
            if event.meetingLink == nil { event.meetingLink = other.meetingLink }
            if event.htmlLink == nil { event.htmlLink = other.htmlLink }
            if event.colorID == nil { event.colorID = other.colorID }
            if event.timeZone == nil { event.timeZone = other.timeZone }
            if event.notes?.isEmpty ?? true { event.notes = other.notes }
            if event.recurrence == nil { event.recurrence = other.recurrence }
            if event.endIsEstimated && !other.endIsEstimated, !event.isAllDay, sameMinute(event.start, other.start) {
                event.end = other.end
                event.endIsEstimated = false
            }
            // If any copy blocks the time, it's not free.
            event.isBusy = event.isBusy || other.isBusy
            for name in other.attendees where !event.attendees.contains(name) { event.attendees.append(name) }
            for key in other.matchKeys where !event.matchKeys.contains(key) { event.matchKeys.append(key) }
        }
        return event
    }
}
