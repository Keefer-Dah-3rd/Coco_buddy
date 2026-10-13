import Foundation

/// "in 15m", "later today", "tomorrow" — how far off an event is, for the schedule card.
/// Days are counted on the calendar (midnight to midnight), so a daylight-saving change
/// never makes tomorrow "in 2 days".
public enum RelativeTiming {
    /// For an event today: "now", "in 15m", "in 1h 20m", or "later today" when 3+ hours off.
    public static func untilStart(of start: Date, now: Date) -> String {
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "in \(minutes)m" }
        if minutes < 180 { return minutes % 60 == 0 ? "in \(minutes / 60)h" : "in \(minutes / 60)h \(minutes % 60)m" }
        return "later today"
    }

    /// For an event on another day: "Tomorrow", a weekday within the week ahead ("Thu"),
    /// or a date ("Oct 24").
    public static func day(of date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case 2..<7: return weekday(date, calendar: calendar)
        default: return monthDay(date, calendar: calendar)
        }
    }

    /// Minutes left in an event that's happening: "20m left", "1h 5m left".
    public static func remaining(until end: Date, now: Date) -> String {
        let minutes = max(1, Int((end.timeIntervalSince(now) / 60).rounded(.up)))
        if minutes < 60 { return "\(minutes)m left" }
        return minutes % 60 == 0 ? "\(minutes / 60)h left" : "\(minutes / 60)h \(minutes % 60)m left"
    }

    private static func weekday(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private static func monthDay(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
