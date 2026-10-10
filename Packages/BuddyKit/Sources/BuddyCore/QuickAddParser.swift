import Foundation

/// Parses the quick-add field's lightweight syntax so tasks can be captured in one line:
///
///     "Draft homepage copy ~45m !!"  → title, 45 min estimate, medium priority
///
/// `~25m`, `~25`, `~1h`, `~1.5h`, `~1h30m` set an estimate. `!` / `!!` / `!!!` set
/// low / medium / high priority. Tokens are only recognised as whole words, so a
/// title like "Fix ~/.zshrc" or "Wow!" is left alone.
public enum QuickAddParser {
    public struct Result: Equatable, Sendable {
        public var title: String
        public var priority: TaskPriority
        public var estimateMinutes: Int?

        public init(title: String, priority: TaskPriority = .none, estimateMinutes: Int? = nil) {
            self.title = title
            self.priority = priority
            self.estimateMinutes = estimateMinutes
        }
    }

    public static func parse(_ input: String) -> Result? {
        var priority = TaskPriority.none
        var estimate: Int?
        var titleWords: [Substring] = []

        for word in input.split(whereSeparator: \.isWhitespace) {
            if let parsed = priorityToken(word) {
                priority = parsed
            } else if let minutes = durationToken(word) {
                estimate = minutes
            } else {
                titleWords.append(word)
            }
        }

        let title = titleWords.joined(separator: " ")
        guard !title.isEmpty else { return nil }
        return Result(title: title, priority: priority, estimateMinutes: estimate)
    }

    private static func priorityToken(_ word: Substring) -> TaskPriority? {
        switch word {
        case "!": .low
        case "!!": .medium
        case "!!!": .high
        default: nil
        }
    }

    private static func durationToken(_ word: Substring) -> Int? {
        guard word.first == "~" else { return nil }
        let body = word.dropFirst().lowercased()
        let minutes: Double?

        if let match = body.wholeMatch(of: /(\d+)h(\d+)m?/) {
            minutes = Double(match.1).map { $0 * 60 + (Double(match.2) ?? 0) }
        } else if let match = body.wholeMatch(of: /(\d+(?:\.\d+)?)h/) {
            minutes = Double(match.1).map { $0 * 60 }
        } else if let match = body.wholeMatch(of: /(\d+)(?:m|min)?/) {
            minutes = Double(match.1)
        } else {
            minutes = nil
        }

        guard let minutes, minutes >= 1, minutes <= 12 * 60 else { return nil }
        return Int(minutes.rounded())
    }
}
