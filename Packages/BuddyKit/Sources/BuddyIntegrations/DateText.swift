import Foundation

/// The date forms the services send: RFC 3339 timestamps, with or without fractional seconds
/// (Google, Notion, Partiful), and bare "YYYY-MM-DD" days (all-day events, Notion dates).
enum DateText {
    static func timestamp(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// "2026-10-12" as local midnight in `calendar`.
    static func day(_ text: String, calendar: Calendar) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
