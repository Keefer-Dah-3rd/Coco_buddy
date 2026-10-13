import Foundation
import BuddyCore

/// Coco's lines for things the app does: a playful, food-motivated corgi who still gets the
/// information across. Every line is a sentence or two and sounds right spoken aloud.
/// Her personality pools (snacks, walks, geese, play…) live in `Dialogue` in BuddyCore;
/// this file adds the task, focus and planning lines, which need the details.
enum BuddyVoice {
    /// Remembers what she said lately, so lines don't come round again too soon.
    private static var picker = LinePicker()
    private static var lastTemplate: [String: Int] = [:]

    static func line(_ topic: Dialogue.Topic) -> String { picker.pick(topic) }

    /// A topic for an unprompted comment, suited to the moment (see `LinePicker.idleTopic`).
    static func idleLine(_ moment: LinePicker.Moment) -> String { picker.pick(picker.idleTopic(moment)) }

    static func greeting(at date: Date = .now) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: line(.greetingMorning)
        case 12..<17: line(.greetingAfternoon)
        case 17..<22: line(.greetingEvening)
        default: line(.greetingNight)
        }
    }

    static func taskAdded(_ title: String, openCount: Int) -> String {
        pick("taskAdded",
             "Got it! “\(short(title))”.",
             "On the list. I'm guarding it.",
             openCount > 1 ? "Noted. \(openCount) things on deck." : "Noted. One thing on deck.",
             "Ooh, a new one. “\(short(title))”.")
    }

    static func duplicate(_ title: String) -> String {
        pick("duplicate",
             "“\(short(title))” is already on the list. I sniffed it.",
             "Wait wait wait. “\(short(title))” is already there.")
    }

    static func taskCompleted(remaining: Int) -> String {
        if remaining == 0 {
            return pick("allDone",
                        "That's everything! Zoomies are mandatory.",
                        "Clean sweep! Walk? Snack? Both?",
                        "All done. Go do something nice. I recommend a walk.")
        }
        return pick("taskCompleted",
                    "Good human. \(remaining) to go.",
                    "One down! \(remaining) left.",
                    "Oh! Oh! Oh! Done! \(remaining) to go.",
                    "Nailed it. \(remaining) remaining.")
    }

    static func focusStarted(task: String?, minutes: Int) -> String {
        guard let task else {
            return pick("focusStarted",
                        "\(minutes) minutes. I'll keep watch quietly.",
                        "Timer's running. I'm on guard duty.",
                        "\(minutes) minutes. I'll be a very quiet loaf.")
        }
        return pick("focusStartedTask",
                    "Focusing on “\(short(task))”. I'll keep guard.",
                    "\(minutes) minutes on “\(short(task))”. Shh. I'm being very quiet.")
    }

    static func focusFinished(minutes: Int, task: String?) -> String {
        if let task {
            return pick("focusFinishedTask",
                        "Time! \(minutes) minutes on “\(short(task))”. Did it get done?",
                        "Done! \(minutes) minutes on “\(short(task))”. Finished, or more to go?")
        }
        return pick("focusFinished",
                    "Time! \(minutes) minutes of real focus.",
                    "That's a session! Stretch with me?",
                    "Time's up! You did great. I did great too. I napped.")
    }

    static func breakStarted(minutes: Int) -> String {
        pick("breakStarted",
             "Break time. Go look at something far away.",
             "\(minutes) minutes off. Water? Window? Walk?",
             "Break! Stretch those human legs. Snack optional. Snack encouraged.")
    }

    static func breakFinished() -> String {
        pick("breakFinished",
             "Break's over. Ready when you are.",
             "Back to it? No rush. Just click me.",
             "Break's done. Tail's ready. Are you?")
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
    static let welcomeDone = "All set! Click me whenever you want to plan. Or play."

    // MARK: Connections

    static func meetingSoon(_ title: String, minutes: Int) -> String {
        minutes <= 1 ? "“\(short(title))” is starting now." : "“\(short(title))” starts in \(minutes) minutes."
    }

    static func addedFromNotion(_ count: Int) -> String {
        count == 1 ? "Brought it over from Notion." : "Brought \(count) over from Notion."
    }

    static let askNotionCompletion = "Want me to mark it done in Notion too?"
    static let notionUpdated = "Marked done in Notion."

    static func notionUpdateFailed(_ reason: String) -> String {
        "I couldn't update Notion — \(reason) It's still done here."
    }

    // MARK: Voice

    static let listening = "Ears up. I'm listening."
    static let heardNothing = "I didn't catch that. Ears were up, though. Try again?"
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

    /// A random line from the choices, never the same one twice in a row for `key`.
    private static func pick(_ key: String, _ lines: String...) -> String {
        guard lines.count > 1 else { return lines.first ?? "" }
        var choices = Array(lines.indices)
        if let last = lastTemplate[key] { choices.removeAll { $0 == last } }
        let index = choices.randomElement() ?? 0
        lastTemplate[key] = index
        return lines[index]
    }

    static func short(_ title: String, limit: Int = 28) -> String {
        title.count <= limit ? title : String(title.prefix(limit - 1)) + "…"
    }
}
