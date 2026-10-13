import Foundation

/// Finding events by a person's name or a few words — "my next meeting with Sam". Runs
/// on this Mac over the merged schedule; attendee names are compared here and only the
/// ones that match are ever mentioned to the chat.
public enum CalendarSearch {
    /// Words that don't narrow a search ("meeting with Sam" means "Sam").
    static let filler: Set<String> = ["with", "and", "the", "a", "an", "my", "our", "meeting", "meetings", "call", "next"]

    /// True when every word of the query is a word — or the start of one, for 3+ letters —
    /// in the event's title, place or attendee names.
    public static func matches(_ event: CalendarEvent, query: String) -> Bool {
        let wanted = words(query)
        guard !wanted.isEmpty else { return true }
        let haystack = Set(([event.title, event.location ?? ""] + event.attendees).flatMap(tokens))
        return wanted.allSatisfy { word in haystack.contains { found(word, in: $0) } }
    }

    /// The attendees the query names ("Sam" → "Sam Lee"), to say who the meeting is with.
    public static func matchingAttendees(_ event: CalendarEvent, query: String) -> [String] {
        let wanted = words(query)
        guard !wanted.isEmpty else { return [] }
        return event.attendees.filter { name in
            let parts = tokens(name)
            return wanted.contains { word in parts.contains { found(word, in: $0) } }
        }
    }

    static func words(_ query: String) -> [String] {
        let all = tokens(query)
        let meaningful = all.filter { !filler.contains($0) }
        return meaningful.isEmpty ? all : meaningful
    }

    private static func tokens(_ text: String) -> [String] {
        CalendarMerge.normalizedTitle(text).split(separator: " ").map(String.init)
    }

    private static func found(_ word: String, in token: String) -> Bool {
        token == word || (word.count >= 3 && token.hasPrefix(word))
    }
}
