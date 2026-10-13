import Foundation

/// Hours of the day treated as available for scheduling, in minutes after midnight.
public struct WorkingHours: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = min(max(0, start), 24 * 60)
        self.end = min(max(self.start, end), 24 * 60)
    }

    public init(startHour: Int, endHour: Int) {
        self.init(start: startHour * 60, end: endHour * 60)
    }

    /// This window on a given day. Uses wall-clock times, so a daylight-saving change that
    /// day doesn't shift 9:00 to 10:00; a time that doesn't exist that day moves forward.
    public func interval(on day: Date, calendar: Calendar) -> DateInterval? {
        let midnight = calendar.startOfDay(for: day)
        func at(_ minutes: Int) -> Date? {
            if minutes >= 24 * 60 { return calendar.date(byAdding: .day, value: 1, to: midnight) }
            return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: midnight,
                                 matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
        }
        guard let from = at(start), let until = at(end), until > from else { return nil }
        return DateInterval(start: from, end: until)
    }
}

/// Which events fall on which day, and where the open time is. Pure arithmetic on events
/// Google returned — nothing here guesses.
public enum Availability {
    /// The local day's bounds (23 or 25 hours long on daylight-saving days).
    public static func dayInterval(_ day: Date, calendar: Calendar) -> DateInterval {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// Events that touch a day: a timed event crossing midnight shows on both days, an
    /// all-day event on each of its dates (Google's end date is exclusive).
    public static func events(on day: Date, from events: [CalendarEvent], calendar: Calendar) -> [CalendarEvent] {
        let bounds = dayInterval(day, calendar: calendar)
        return events.filter { event in
            if event.end <= event.start { return bounds.contains(event.start) && event.start < bounds.end }
            return event.start < bounds.end && event.end > bounds.start
        }
        .sorted { ($0.isAllDay ? 0 : 1, $0.start) < ($1.isAllDay ? 0 : 1, $1.start) }
    }

    /// Times taken by events marked busy, merged so overlaps count once.
    public static func busy(_ events: [CalendarEvent], within window: DateInterval) -> [DateInterval] {
        let pieces = events
            .filter { $0.isBusy && $0.start < window.end && $0.end > window.start }
            .map { DateInterval(start: max($0.start, window.start), end: min($0.end, window.end)) }
            .sorted { $0.start < $1.start }
        var merged: [DateInterval] = []
        for piece in pieces {
            if let last = merged.last, piece.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, piece.end))
            } else {
                merged.append(piece)
            }
        }
        return merged
    }

    /// Open stretches inside `window`, at least `minimum` long, starting no earlier than `notBefore`.
    public static func openings(in window: DateInterval, events: [CalendarEvent], minimum: TimeInterval = 15 * 60,
                                notBefore: Date? = nil) -> [DateInterval] {
        var from = window.start
        if let notBefore, notBefore > from { from = notBefore }
        guard window.end > from else { return [] }
        let usable = DateInterval(start: from, end: window.end)
        var gaps: [DateInterval] = []
        var cursor = usable.start
        for block in busy(events, within: usable) {
            if block.start > cursor { gaps.append(DateInterval(start: cursor, end: block.start)) }
            cursor = max(cursor, block.end)
        }
        if usable.end > cursor { gaps.append(DateInterval(start: cursor, end: usable.end)) }
        return gaps.filter { $0.duration >= minimum }
    }

    /// Open stretches on one day within working hours (or a narrower window of the day).
    public static func openings(on day: Date, events: [CalendarEvent], hours: WorkingHours, minimum: TimeInterval = 15 * 60,
                                notBefore: Date? = nil, calendar: Calendar) -> [DateInterval] {
        guard let window = hours.interval(on: day, calendar: calendar) else { return [] }
        return openings(in: window, events: events, minimum: minimum, notBefore: notBefore)
    }

    /// Start times for something `duration` long: the first fitting start in each opening,
    /// on step-minute boundaries, across the given days in order. Slots never overlap an
    /// event or each other.
    public static func slots(duration: TimeInterval, days: [Date], events: [CalendarEvent], hours: WorkingHours,
                             notBefore: Date? = nil, step: Int = 15, limit: Int = 12, calendar: Calendar) -> [DateInterval] {
        guard duration > 0 else { return [] }
        var found: [DateInterval] = []
        for day in days {
            for opening in openings(on: day, events: events, hours: hours, minimum: duration, notBefore: notBefore, calendar: calendar) {
                guard let start = aligned(opening.start, step: step, calendar: calendar),
                      start.addingTimeInterval(duration) <= opening.end else { continue }
                found.append(DateInterval(start: start, duration: duration))
                if found.count >= limit { return found }
            }
        }
        return found
    }

    /// Events that overlap a proposed time and block it.
    public static func conflicts(with proposal: DateInterval, in events: [CalendarEvent], ignoring id: String? = nil) -> [CalendarEvent] {
        events.filter { $0.id != id && $0.isBusy && !$0.isAllDay && $0.start < proposal.end && $0.end > proposal.start }
    }

    /// Busy events whose times overlap another busy event.
    public static func overlapping(_ events: [CalendarEvent]) -> [CalendarEvent] {
        let timed = events.filter { $0.isBusy && !$0.isAllDay }.sorted { $0.start < $1.start }
        var clashing: [String: CalendarEvent] = [:]
        for (i, a) in timed.enumerated() {
            for b in timed[(i + 1)...] where b.start < a.end {
                clashing[a.id] = a
                clashing[b.id] = b
            }
        }
        return timed.filter { clashing[$0.id] != nil }
    }

    /// Minutes taken by busy timed events within a window, overlaps counted once.
    public static func bookedMinutes(_ events: [CalendarEvent], within window: DateInterval) -> Int {
        Int(busy(events.filter { !$0.isAllDay }, within: window).reduce(0) { $0 + $1.duration } / 60)
    }

    /// Rounds up to the next step-minute boundary of the wall clock.
    private static func aligned(_ date: Date, step: Int, calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let minute = parts.minute ?? 0
        let exact = minute % step == 0 && (parts.second ?? 0) == 0 && (parts.nanosecond ?? 0) == 0
        if exact { return date }
        let floored = calendar.date(bySettingHour: parts.hour ?? 0, minute: minute - minute % step, second: 0, of: date)
        return floored.flatMap { calendar.date(byAdding: .minute, value: step, to: $0) }
    }
}
