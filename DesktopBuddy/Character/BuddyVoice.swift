import Foundation
import BuddyCore

/// Coco's lines. Warm, a little playful, never more than a sentence or two — and
/// written to sound right when spoken aloud as well as read.
/// Kept in one place so tone stays consistent and lines are easy to tune.
enum BuddyVoice {
    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12:
            pick("Morning! I've done my stretches. What's first today?",
                 "Good morning. Tail's wagging — what are we working on?",
                 "Morning. What's the one thing that would make today feel good?")
        case 12..<17:
            pick("Afternoon! Want to pick the next thing?",
                 "Hey you. Still here, still cheering.")
        case 17..<22:
            pick("Evening shift? Let's keep it small.",
                 "Evening. Anything left that really matters today?")
        default:
            pick("It's late. Write tomorrow's first task and let's call it?",
                 "Night owl mode. I'll keep you company.")
        }
    }

    static func taskAdded(_ title: String, openCount: Int) -> String {
        pick("Got it — “\(short(title))”.",
             "On the list.",
             openCount > 1 ? "Noted. \(openCount) things on deck." : "Noted. One thing on deck.")
    }

    static func duplicate(_ title: String) -> String {
        "“\(short(title))” is already on the list."
    }

    static func taskCompleted(remaining: Int) -> String {
        if remaining == 0 {
            return pick("That's everything! Zoomies are mandatory.",
                        "Clean sweep. Go do something nice.")
        }
        return pick("Good human. \(remaining) to go.",
                    "One down! \(remaining) left.",
                    "Done and done. \(remaining) remaining.")
    }

    static func focusStarted(task: String?, minutes: Int) -> String {
        guard let task else {
            return pick("\(minutes) minutes. I'll keep watch quietly.",
                        "Timer's running. I'm on guard duty.")
        }
        return pick("Focusing on “\(short(task))”. I'll keep guard.",
                    "\(minutes) minutes on “\(short(task))”. I'll be very quiet.")
    }

    static func focusFinished(minutes: Int, task: String?) -> String {
        if let task {
            return "Time! \(minutes) minutes on “\(short(task))”. Did it get done?"
        }
        return pick("Time! \(minutes) minutes of real focus.",
                    "That's a session! Stretch with me?")
    }

    static func breakStarted(minutes: Int) -> String {
        pick("Break time. Go look at something far away.",
             "\(minutes) minutes off. Water? Window? Walk?")
    }

    static func breakFinished() -> String {
        pick("Break's over. Ready when you are.",
             "Back to it? No rush — just click me.")
    }

    static func endedWhileAway(_ phase: String) -> String {
        "Your \(phase.lowercased()) ended while I was napping."
    }

    // MARK: Planning

    static func upNext(_ title: String, reason: DayPlanner.Reason) -> String {
        let t = short(title)
        return switch reason {
        case .overdue: "“\(t)” is overdue — want to knock it out first?"
        case .dueToday: "“\(t)” is due today. That's my pick."
        case .dueTomorrow: "“\(t)” is due tomorrow — a good one to start now."
        case .highPriority: "I'd go with “\(t)”. You marked it high priority."
        case .quickWin: "Try “\(t)” — it's a quick win."
        case .nextInLine: "“\(t)” has been waiting the longest. Start there?"
        }
    }

    static let nothingNext = "Nothing on the list yet. Want to add something?"

    // MARK: Voice

    static let listening = "I'm listening."
    static let heardNothing = "I didn't catch that. Try again?"
    static let micUnavailable = "I can't hear you — microphone access is off."

    static func heardTasks(_ count: Int) -> String {
        count == 1 ? "I heard one thing. Look right?" : "I heard \(count) things. Check them before I add them?"
    }

    static func addedTasks(_ count: Int) -> String {
        count == 1 ? "Added it." : "Added \(count) tasks."
    }

    static func noMatchingTask(_ hint: String) -> String {
        "I couldn't find “\(short(hint))” on your list, so I started a plain focus session."
    }

    static let paused = "Paused."
    static let resumed = "Back to it."
    static let stopped = "Stopped the timer."
    static let nothingToControl = "There's no session running right now."

    // MARK: -

    private static func pick(_ lines: String...) -> String {
        lines.randomElement() ?? ""
    }

    static func short(_ title: String, limit: Int = 28) -> String {
        title.count <= limit ? title : String(title.prefix(limit - 1)) + "…"
    }
}
