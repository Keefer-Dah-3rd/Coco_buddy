import Testing
@testable import BuddyCore

@Suite struct TypedLengthTests {
    @Test(arguments: [
        ("45", 45), ("  45  ", 45), ("5", 5), ("180", 180), ("500", 500),
        ("45m", 45), ("45 m", 45), ("45min", 45), ("45 mins", 45), ("45 minutes", 45), ("1 minute", 1),
        ("1h", 60), ("1 hr", 60), ("2 hrs", 120), ("1 hour", 60), ("2 Hours", 120),
        ("1h 30m", 90), ("1h30m", 90), ("1h30", 90), ("1h 30", 90), ("1 hour 30 minutes", 90),
        ("1 hour and 30 minutes", 90), ("1h, 30m", 90), ("1.5h", 90), ("1,5h", 90), ("1.5 hours", 90), ("0.5h", 30),
        ("25:00", 25), ("20:00", 20), ("90:00", 90), ("1:30:00", 90), ("3:00:00", 180), ("05:00", 5),
        ("12:30", 13), ("1:30", 2), ("0:20", 1), ("2.5", 3),
    ])
    func readsLengths(_ text: String, _ expected: Int) {
        #expect(TypedLength.minutes(from: text) == expected)
    }

    @Test(arguments: [
        "", "   ", "0", "0m", "00:00", "abc", "h", "m", "-5", "1 30", "30 1h", "30m 1h", "1h 1h", "45s", "45 sec",
        "1:60", "1:30:60", "1:2:3:4", ":30", "30:", "1:3a", "1.2.3", ".5h", "1 and 2", "candy",
    ])
    func refusesWhatIsNotALength(_ text: String) {
        #expect(TypedLength.minutes(from: text) == nil)
    }
}
