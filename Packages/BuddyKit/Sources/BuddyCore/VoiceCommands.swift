import Foundation
import NaturalLanguage

/// What a spoken sentence asks for. Recognised entirely on-device with simple,
/// predictable rules — no AI involved, so nothing is guessed or sent anywhere.
public enum VoiceIntent: Equatable, Sendable {
    case startFocus(taskHint: String?)
    case startBreak
    case pause
    case resume
    case stop
    /// Tasks to show for review before anything is added.
    case addTasks([QuickAddParser.Result])
    case nothing
}

public enum VoiceCommandParser {
    public static func parse(_ transcript: String) -> VoiceIntent {
        let s = normalized(transcript)
        guard !s.isEmpty else { return .nothing }

        if let match = s.wholeMatch(of: /(?:let'?s )?(?:start|begin)(?: a| the| my)? (?:focus(?: session| timer)?|pomodoro|timer|session)(?: on (.+))?/) {
            return .startFocus(taskHint: match.1.map(String.init))
        }
        if let match = s.wholeMatch(of: /(?:let'?s |time to )?focus(?: time)?(?: on (.+))?/) {
            return .startFocus(taskHint: match.1.map(String.init))
        }
        if s.wholeMatch(of: /(?:start|take|begin|have)(?: a| my)?(?: short| long| quick)? break|break time/) != nil {
            return .startBreak
        }
        if s.wholeMatch(of: /pause(?: the)?(?: timer| focus| session)?/) != nil {
            return .pause
        }
        if s.wholeMatch(of: /(?:resume|continue|unpause)(?: the)?(?: timer| focus| session)?/) != nil {
            return .resume
        }
        if s.wholeMatch(of: /stop|(?:stop|end|cancel|finish)(?: the| my)? (?:timer|focus|session|focus session)/) != nil {
            return .stop
        }

        let tasks = TaskSplitter.split(transcript)
        return tasks.isEmpty ? .nothing : .addTasks(tasks)
    }

    /// Lowercased, punctuation stripped, "hey Coco," and "please" removed.
    static func normalized(_ text: String) -> String {
        var s = text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .components(separatedBy: CharacterSet.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'")))
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        for prefix in ["hey coco ", "ok coco ", "okay coco ", "coco ", "please "] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.hasSuffix(" please") { s.removeLast(" please".count) }
        return s
    }
}

/// Turns a spoken (or pasted) sentence into separate tasks:
///
///     "I need to finish the homepage, review three portfolio projects,
///      and send two emails today"
///     → Finish the homepage · Review three portfolio projects · Send two emails
///
/// Splits on commas, "then", "also", and on "and" only when a verb follows it,
/// so "buy salt and pepper" stays one task. Picks up spoken estimates
/// ("for 30 minutes", "about an hour") and urgency ("urgent", "high priority").
public enum TaskSplitter {
    public static func split(_ text: String) -> [QuickAddParser.Result] {
        let flattened = text.replacingOccurrences(of: "\n", with: ", ")
        var chunks: [String] = []
        for clause in flattened.split(whereSeparator: { ",;.!?".contains($0) }) {
            chunks += splitOnVerbAnd(String(clause))
        }
        // A clause with no task of its own ("…, it's urgent") modifies the one before it.
        var tasks: [QuickAddParser.Result] = []
        for part in chunks.map(parse) {
            if !part.title.isEmpty {
                tasks.append(part)
            } else if var last = tasks.popLast() {
                if part.priority != .none { last.priority = part.priority }
                last.estimateMinutes = part.estimateMinutes ?? last.estimateMinutes
                tasks.append(last)
            }
        }
        return tasks
    }

    /// One clause → title (possibly empty) plus any estimate or priority it mentions.
    private static func parse(_ chunk: String) -> QuickAddParser.Result {
        var s = " " + chunk.lowercased().trimmingCharacters(in: .whitespaces) + " "
        var original = " " + chunk.trimmingCharacters(in: .whitespaces) + " "

        // Work on the lowercased copy for matching, and cut the same ranges from the original.
        func remove(_ regex: Regex<Substring>) {
            while let match = s.firstMatch(of: regex) {
                let lower = s.distance(from: s.startIndex, to: match.range.lowerBound)
                let upper = s.distance(from: s.startIndex, to: match.range.upperBound)
                s.replaceSubrange(match.range, with: " ")
                let o1 = original.index(original.startIndex, offsetBy: lower)
                let o2 = original.index(original.startIndex, offsetBy: upper)
                original.replaceSubrange(o1..<o2, with: " ")
            }
        }

        var minutes: Int?
        if let m = s.firstMatch(of: /\s(?:for |about |around |takes |taking |maybe )*(\d+(?:\.\d+)?|an?|one|half an?) ?(minutes?|mins?|hours?|hrs?)\s/) {
            let amount: Double = switch m.1 {
            case "a", "an", "one": 1
            case "half a", "half an": 0.5
            default: Double(m.1) ?? 0
            }
            let value = m.2.hasPrefix("h") ? amount * 60 : amount
            if value >= 1, value <= 12 * 60 { minutes = Int(value.rounded()) }
            remove(/\s(?:it )?(?:for |about |around |takes |taking |maybe )*(?:\d+(?:\.\d+)?|an?|one|half an?) ?(?:minutes?|mins?|hours?|hrs?)\s/)
        }

        var priority = TaskPriority.none
        if s.firstMatch(of: /\s(?:urgent(?:ly)?|asap|important|high priority)\s/) != nil {
            priority = .high
            remove(/\s(?:it'?s |it is )?(?:urgent(?:ly)?|asap|important|high priority)\s/)
        } else if s.firstMatch(of: /\slow priority\s/) != nil {
            priority = .low
            remove(/\s(?:it'?s |it is )?low priority\s/)
        }

        // Lead-ins and trailing time words.
        remove(/^\s*(?:(?:um|uh|so|okay|ok|and|then|also|plus|oh)\s+)+/)
        remove(/^\s*(?:today\s+)?(?:i\s+(?:need|have|want|got|gotta|should|must|'ve got)\s+(?:to\s+)?|i'?ve got to\s+|i gotta\s+|remind me to\s+|(?:can you |please )?add\s+|let'?s\s+|don'?t forget to\s+)/)
        remove(/\s(?:today|tonight|this (?:morning|afternoon|evening)|later(?: today)?)\s*$/)

        var title = original.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if title.wholeMatch(of: /(?i)(?:and|then|also|um|uh|ok|okay|so|it'?s|it is)/) != nil { title = "" }
        return QuickAddParser.Result(title: title.prefix(1).uppercased() + title.dropFirst(),
                                     priority: priority, estimateMinutes: minutes)
    }

    /// Splits "finish the homepage and send emails" at "and" only when the next word is a verb.
    private static func splitOnVerbAnd(_ clause: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = clause
        var cuts: [Range<String.Index>] = []
        var previousWasAnd: Range<String.Index>?
        tagger.enumerateTags(in: clause.startIndex..<clause.endIndex, unit: .word, scheme: .lexicalClass,
                             options: [.omitWhitespace, .omitPunctuation]) { tag, range in
            if let and = previousWasAnd, tag == .verb {
                cuts.append(and)
            }
            previousWasAnd = clause[range].lowercased() == "and" ? range : nil
            return true
        }
        guard !cuts.isEmpty else { return [clause] }
        var parts: [String] = []
        var start = clause.startIndex
        for cut in cuts {
            parts.append(String(clause[start..<cut.lowerBound]))
            start = cut.upperBound
        }
        parts.append(String(clause[start...]))
        // Only keep the split if every part still reads as a task (2+ words).
        let wordy = parts.allSatisfy { $0.split(whereSeparator: \.isWhitespace).count >= 2 }
        return wordy ? parts : [clause]
    }
}
