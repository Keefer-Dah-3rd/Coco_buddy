import Foundation
import Testing
@testable import BuddyCore

/// Same seed, same rolls: makes the picker's randomness repeatable.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

@Suite struct DialogueTests {
    let noon = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func everyTopicHasSeveralLines() {
        for topic in Dialogue.Topic.allCases {
            #expect(Dialogue.lines(topic).count >= 2, "\(topic) needs variety")
        }
    }

    @Test func linesAreShortUniqueAndNeverSoundLikeAHelpDesk() {
        var seen = Set<String>()
        for topic in Dialogue.Topic.allCases {
            for line in Dialogue.lines(topic) {
                // Short enough for the bubble and to say aloud in one breath.
                #expect(line.count <= 90, "too long: \(line)")
                #expect(!line.isEmpty)
                #expect(seen.insert(line).inserted, "used twice: \(line)")
                for phrase in Dialogue.offVoice {
                    #expect(!line.localizedCaseInsensitiveContains(phrase), "off-voice: \(line)")
                }
                // Never guilt-trips for attention.
                for guilt in ["ignoring me", "forgot about me", "you never", "abandon"] {
                    #expect(!line.localizedCaseInsensitiveContains(guilt), "guilt-trip: \(line)")
                }
            }
        }
    }

    @Test func pickerDoesNotRepeatUntilMostOfThePoolHasHadATurn() {
        var picker = LinePicker()
        var generator = SeededGenerator(state: 7)
        let pool = Dialogue.lines(.food)
        let window = pool.count - 2
        var said: [String] = []
        for _ in 0..<40 { said.append(picker.pick(.food, using: &generator)) }
        for index in said.indices {
            let recent = said[max(0, index - window + 1)...index]
            #expect(Set(recent).count == recent.count, "repeat inside \(window) picks at \(index)")
        }
        #expect(Set(said) == Set(pool), "every line gets a turn")
    }

    @Test func poolsRememberSeparately() {
        var picker = LinePicker()
        var generator = SeededGenerator(state: 1)
        let treat = picker.pick(.treatReceived, using: &generator)
        let fetch = picker.pick(.fetchCompleted, using: &generator)
        #expect(Dialogue.lines(.treatReceived).contains(treat))
        #expect(Dialogue.lines(.fetchCompleted).contains(fetch))
    }

    @Test func geeseStayRare() {
        var picker = LinePicker()
        var generator = SeededGenerator(state: 42)
        var gooseTimes: [Date] = []
        // A chatty day: one idle comment every 10 minutes for 12 hours.
        for step in 0..<72 {
            let now = noon.addingTimeInterval(Double(step) * 600)
            if picker.idleTopic(.init(now: now, hour: 12), using: &generator) == .geese { gooseTimes.append(now) }
        }
        #expect(gooseTimes.count <= 12)
        for (a, b) in zip(gooseTimes, gooseTimes.dropFirst()) {
            #expect(b.timeIntervalSince(a) > LinePicker.gooseRest)
        }
    }

    @Test func noGeeseInTheFirstFewComments() {
        for seed in 0..<50 {
            var picker = LinePicker()
            var generator = SeededGenerator(state: UInt64(seed))
            for _ in 0..<2 { #expect(picker.idleTopic(.init(now: noon, hour: 12), using: &generator) != .geese) }
        }
    }

    @Test func idleTopicsFitTheMoment() {
        func topics(_ moment: LinePicker.Moment) -> [Dialogue.Topic] {
            var picker = LinePicker()
            var generator = SeededGenerator(state: 3)
            return (0..<300).map { _ in picker.idleTopic(moment, using: &generator) }
        }
        // Right after a treat she doesn't ask for more food.
        #expect(!topics(.init(now: noon, hour: 12, recentlyFed: true)).contains(.food))
        // Right after attention she doesn't ask for more.
        #expect(!topics(.init(now: noon, hour: 12, recentlyTogether: true)).contains(.affection))
        // Late at night she's mostly sleepy; at noon never.
        let night = topics(.init(now: noon, hour: 23))
        #expect(night.filter { $0 == .sleepy }.count > night.count / 4)
        #expect(!topics(.init(now: noon, hour: 12)).contains(.sleepy))
        // During working hours she sometimes just keeps you company.
        #expect(topics(.init(now: noon, hour: 11, working: true)).contains(.working))
        #expect(!topics(.init(now: noon, hour: 11)).contains(.working))
    }
}
