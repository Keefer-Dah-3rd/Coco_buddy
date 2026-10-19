import Foundation

/// What the chat shares with Anthropic, in the words the consent screen uses. App Review
/// Guideline 5.1.2(i): say what is sent and to whom, and get explicit permission first.
///
/// Raise `version` whenever the chat starts sending a new kind of data, so everyone is
/// asked again before it does.
enum AIConsent {
    static let version = 1

    static let recipient = "Anthropic, the company that makes Claude"
    static let privacyPolicy = URL(string: "https://www.anthropic.com/legal/privacy")!

    /// Sent with every message.
    static let always = [
        "What you type or say to \(Buddy.name) in the chat.",
    ]

    /// Sent only when Coco looks it up to answer — the chat shows each lookup.
    static let whenNeeded = [
        "Your tasks, with their notes, priorities and due dates, including tasks picked from Notion.",
        "Your focus timer and how long you've focused today.",
        "Calendar events from Google Calendar, Apple Calendar and Partiful: titles, times and places. A guest's name only when you ask about meetings with them.",
        "Partiful invitations you paste into the chat.",
        "What you just did that the chat should know, like confirming a task it suggested.",
    ]

    static let never = "Voice recordings, event descriptions, guest lists, and your sign-ins and keys for other services."
}
