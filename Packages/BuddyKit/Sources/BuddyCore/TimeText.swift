import Foundation

/// Lengths of time as the panel shows and reads them. One place for the wording, so an
/// estimate, a session length, a booked hour and the countdown all agree.
public enum DurationText {
    /// Minutes in short form: "25m", "1h", "1h 30m".
    public static func short(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    /// Minutes read aloud (VoiceOver): "25 minutes", "1 hour", "2 hours".
    public static func spoken(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }

    /// A countdown: "24:59", or "1:04:59" for long sessions. Rounds up so a fresh 25-minute
    /// timer reads 25:00.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

extension DateFormatter {
    /// A formatter for a fixed pattern in English, unaffected by the user's locale settings:
    /// for the text the assistant reads, and the schedule's "Thu" and "Oct 24".
    public static func fixed(_ format: String, calendar: Calendar = .current, timeZone: TimeZone? = nil) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone ?? calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}
