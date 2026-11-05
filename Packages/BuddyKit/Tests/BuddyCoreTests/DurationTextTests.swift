import Testing
import BuddyCore

@Suite struct DurationTextTests {
    @Test func shortForm() {
        #expect(DurationText.short(0) == "0m")
        #expect(DurationText.short(25) == "25m")
        #expect(DurationText.short(60) == "1h")
        #expect(DurationText.short(90) == "1h 30m")
        #expect(DurationText.short(120) == "2h")
    }

    @Test func spokenForm() {
        #expect(DurationText.spoken(5) == "5 minutes")
        #expect(DurationText.spoken(60) == "1 hour")
        #expect(DurationText.spoken(120) == "2 hours")
    }

    @Test func clockRoundsUpToTheSecond() {
        #expect(DurationText.clock(0) == "00:00")
        #expect(DurationText.clock(25 * 60) == "25:00")
        #expect(DurationText.clock(24 * 60 + 59.2) == "25:00")
        #expect(DurationText.clock(59.4) == "01:00")
        #expect(DurationText.clock(3661) == "1:01:01")
    }
}
