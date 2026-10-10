import Testing
@testable import BuddyCore

@Suite struct VoiceCommandTests {
    @Test(arguments: [
        ("Start focus", VoiceIntent.startFocus(taskHint: nil)),
        ("Hey Coco, start a focus session on the homepage.", .startFocus(taskHint: "the homepage")),
        ("Let's focus", .startFocus(taskHint: nil)),
        ("focus on portfolio review", .startFocus(taskHint: "portfolio review")),
        ("Take a short break", .startBreak),
        ("Pause the timer", .pause),
        ("Resume", .resume),
        ("Stop", .stop),
        ("end the session please", .stop),
    ])
    func recognisesCommands(transcript: String, intent: VoiceIntent) {
        #expect(VoiceCommandParser.parse(transcript) == intent)
    }

    @Test func finishingATaskIsNotAStopCommand() {
        guard case .addTasks(let tasks) = VoiceCommandParser.parse("Finish the homepage") else {
            Issue.record("expected tasks"); return
        }
        #expect(tasks.map(\.title) == ["Finish the homepage"])
    }

    @Test func emptyOrFillerIsNothing() {
        #expect(VoiceCommandParser.parse("   ") == .nothing)
        #expect(VoiceCommandParser.parse("um, and") == .nothing)
    }
}

@Suite struct TaskSplitterTests {
    @Test func splitsTheExampleFromTheBrief() {
        let tasks = TaskSplitter.split("I need to finish the homepage, review three portfolio projects, and send two emails today.")
        #expect(tasks.map(\.title) == ["Finish the homepage", "Review three portfolio projects", "Send two emails"])
    }

    @Test func splitsOnAndOnlyBeforeAVerb() {
        #expect(TaskSplitter.split("finish the homepage and send two emails").map(\.title)
                == ["Finish the homepage", "Send two emails"])
        #expect(TaskSplitter.split("buy salt and pepper").map(\.title) == ["Buy salt and pepper"])
    }

    @Test func picksUpSpokenEstimatesAndUrgency() {
        let tasks = TaskSplitter.split("Write the case study for about an hour, then call the printer, it's urgent")
        #expect(tasks == [
            .init(title: "Write the case study", estimateMinutes: 60),
            .init(title: "Call the printer", priority: .high),
        ])
        #expect(TaskSplitter.split("stretch for 10 minutes").first?.estimateMinutes == 10)
        #expect(TaskSplitter.split("review notes for half an hour").first?.estimateMinutes == 30)
    }

    @Test func dropsLeadInsButKeepsMeaning() {
        #expect(TaskSplitter.split("Remind me to book the dentist").map(\.title) == ["Book the dentist"])
        #expect(TaskSplitter.split("Okay so I have to email Sam").map(\.title) == ["Email Sam"])
    }
}
