import Foundation

/// Reads a length typed by hand on the focus timer's clock.
///
/// Takes plain minutes ("45"), units ("45m", "90 min", "1h 30m", "1h30", "1.5 hours",
/// "1 hour and 30 minutes"), or the clock's own form ("25:00", "1:30:00"). A colon reads the
/// way the clock shows time, so "1:30" is a minute and a half. Lengths are whole minutes,
/// rounded to the nearest; nil when the text isn't a length or comes to nothing.
/// Callers clamp the result to `FocusSettings.minuteRange`.
public enum TypedLength {
    public static func minutes(from text: String) -> Int? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        guard let seconds = text.contains(":") ? clockSeconds(text) : unitSeconds(text), seconds > 0 else { return nil }
        return max(1, Int((seconds / 60).rounded()))
    }

    /// "mm:ss" or "h:mm:ss", as the countdown shows it.
    private static func clockSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers.count == parts.count else { return nil }
        // Everything after the first part is minutes or seconds of the part before.
        guard numbers.dropFirst().allSatisfy({ $0 < 60 }), parts.dropFirst().allSatisfy({ $0.count <= 2 }) else { return nil }
        return Double(numbers.reduce(0) { $0 * 60 + $1 })
    }

    /// Numbers with optional hour/minute units. A bare number is minutes, including one
    /// after an hours part ("1h 30").
    private static func unitSeconds(_ text: String) -> Double? {
        let chars = Array(text)
        var i = 0
        var hours: Double?
        var minutes: Double?
        var bare: Double?

        func isDigit(_ index: Int) -> Bool { index < chars.count && chars[index].isASCII && chars[index].isNumber }
        func isLetter(_ index: Int) -> Bool { index < chars.count && chars[index].isLetter }

        while true {
            // Separators: spaces, commas and "and".
            while i < chars.count {
                if chars[i] == " " || chars[i] == "," { i += 1; continue }
                if i + 3 <= chars.count, String(chars[i..<i + 3]) == "and", !isLetter(i + 3) { i += 3; continue }
                break
            }
            if i == chars.count { break }

            // A number, with at most one decimal point ("1.5" or "1,5").
            let start = i
            var sawPoint = false
            while i < chars.count {
                if isDigit(i) {
                    i += 1
                } else if chars[i] == "." || chars[i] == ",", !sawPoint, i > start, isDigit(i + 1) {
                    sawPoint = true
                    i += 1
                } else {
                    break
                }
            }
            guard i > start, let value = Double(String(chars[start..<i]).replacingOccurrences(of: ",", with: ".")) else { return nil }

            while i < chars.count, chars[i] == " " { i += 1 }
            let unitStart = i
            while isLetter(i) { i += 1 }
            switch String(chars[unitStart..<i]) {
            case "":
                guard bare == nil, minutes == nil else { return nil }
                if hours != nil { minutes = value } else { bare = value }
            case "h", "hr", "hrs", "hour", "hours":
                guard hours == nil, minutes == nil, bare == nil else { return nil }
                hours = value
            case "m", "min", "mins", "minute", "minutes":
                guard minutes == nil, bare == nil else { return nil }
                minutes = value
            default:
                return nil
            }
        }

        if let bare { minutes = bare }
        guard hours != nil || minutes != nil else { return nil }
        return (hours ?? 0) * 3600 + (minutes ?? 0) * 60
    }
}
