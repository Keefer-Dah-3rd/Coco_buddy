import Foundation
import Testing
import BuddyCore
import BuddyIntegrations
@testable import BuddyAssistant

@Suite struct StreamAccumulatorTests {
    /// A turn with a thinking block, a sentence, then a tool call — as the API streams it.
    let stream = [
        #"event: message_start"#,
        #"data: {"type":"message_start","message":{"id":"msg_1","model":"claude-opus-5-5","usage":{"input_tokens":1200,"cache_read_input_tokens":900,"cache_creation_input_tokens":0,"output_tokens":1}}}"#,
        #"data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":"","signature":""}}"#,
        #"data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"sig-abc"}}"#,
        #"data: {"type":"content_block_stop","index":0}"#,
        #"data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Let me look "}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"at your day."}}"#,
        #"data: {"type":"content_block_stop","index":1}"#,
        #"data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_1","name":"start_focus","input":{}}}"#,
        #"data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"minu"}}"#,
        #"data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"tes\": 25}"}}"#,
        #"data: {"type":"content_block_stop","index":2}"#,
        #"data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":80}}"#,
        #"data: {"type":"message_stop"}"#,
        #"event: ping"#,
    ]

    @Test func rebuildsTheTurnExactly() throws {
        var accumulator = StreamAccumulator()
        var updates: [StreamAccumulator.Update] = []
        for line in stream {
            if let event = SSE.payload(from: line), let update = try accumulator.apply(event) { updates.append(update) }
        }
        #expect(updates == [.text("Let me look "), .text("at your day."), .toolStarted(name: "start_focus")])
        #expect(accumulator.stopReason == "tool_use")
        #expect(accumulator.visibleText == "Let me look at your day.")
        let content = accumulator.content
        #expect(content.count == 3)
        // The thinking block keeps its signature so it can be sent back unchanged.
        #expect(content[0] == ["type": "thinking", "thinking": "", "signature": "sig-abc"])
        #expect(content[2]["input"] == ["minutes": 25])
        #expect(accumulator.toolCalls.map(\.name) == ["start_focus"])
        #expect(accumulator.usage.cacheReadTokens == 900 && accumulator.usage.outputTokens == 80)
    }

    @Test func interruptedRepliesKeepOnlyText() throws {
        var accumulator = StreamAccumulator()
        for line in stream.prefix(7) { if let event = SSE.payload(from: line) { try accumulator.apply(event) } }
        #expect(accumulator.textOnlyContent == [["type": "text", "text": "Let me look "]])
    }

    @Test func invalidToolJSONIsFlaggedNotRun() throws {
        var accumulator = StreamAccumulator()
        for raw in [
            #"{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_9","name":"propose_tasks","input":{}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"tasks\": [ oops"}}"#,
            #"{"type":"content_block_stop","index":0}"#,
        ] {
            try accumulator.apply(try JSONValue.parse(raw))
        }
        #expect(accumulator.invalidToolInputs["toolu_9"] == #"{"tasks": [ oops"#)
    }

    @Test func streamErrorsSurface() {
        var accumulator = StreamAccumulator()
        let event = try! JSONValue.parse(#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#)
        #expect(throws: StreamAccumulator.StreamError.server("Overloaded")) { try accumulator.apply(event) }
    }

    @Test func costUsesListPrices() {
        var usage = ClaudeUsage()
        usage.inputTokens = 1_000_000
        usage.outputTokens = 100_000
        #expect(abs(usage.estimatedCost - 6.0) < 0.0001)
    }
}

@Suite struct ClaudeRequestTests {
    @Test func requestFollowsCurrentGuidance() throws {
        let request = try ClaudeAPI.messagesRequest(apiKey: "sk-test", system: "sys", tools: AssistantTools.definitions,
                                                    messages: [["role": "user", "content": "hi"]])
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try JSONValue.parse(request.httpBody!)
        #expect(body["model"] == "claude-opus-5-5")
        #expect(body["stream"] == true)
        #expect(body["fallbacks"] == "default")
        #expect(body["output_config"]?["effort"] == "low")
        #expect(body["tool_choice"] == ["type": "auto"])
        #expect(body["thinking"] == nil)  // always on for this model; effort is the control
        #expect(body["tools"]?.array?.count == AssistantTools.definitions.count)
    }

    @Test func encodingIsDeterministic() throws {
        let value: JSONValue = ["b": 2, "a": ["z": true, "y": "x/y"], "n": .number(1.5)]
        #expect(String(data: try value.encoded(), encoding: .utf8) == #"{"a":{"y":"x/y","z":true},"b":2,"n":1.5}"#)
    }

    @Test func errorMessagesAreHuman() {
        #expect(ClaudeAPI.errorMessage(status: 401, body: Data()).contains("API key"))
        #expect(ClaudeAPI.errorMessage(status: 529, body: Data()).contains("overloaded"))
        let body = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad thing"}}"#.utf8)
        #expect(ClaudeAPI.errorMessage(status: 400, body: body) == "bad thing")
    }
}

@Suite struct AssistantToolTests {
    @Test func toolsAreStrictAndNeverForced() {
        for tool in AssistantTools.definitions {
            #expect(tool["strict"] == true)
            #expect(tool["input_schema"]?["additionalProperties"] == false)
        }
    }

    @Test func validCallsBecomeActions() throws {
        #expect(try AssistantTools.action(name: "get_today", input: [:]).get() == .getToday)
        let tasks: JSONValue = ["tasks": [["title": " Write intro ", "estimate_minutes": 30, "priority": "high"], ["title": "Email Sam"]]]
        #expect(try AssistantTools.action(name: "propose_tasks", input: tasks).get()
                == .proposeTasks([.init(title: "Write intro", priority: .high, estimateMinutes: 30), .init(title: "Email Sam")]))
        #expect(try AssistantTools.action(name: "start_focus", input: ["minutes": 25]).get() == .startFocus(taskID: nil, minutes: 25))
        #expect(try AssistantTools.action(name: "request_task_completion", input: ["task_id": "abc"]).get() == .requestCompletion(taskID: "abc"))
    }

    @Test func badCallsAreRejected() {
        #expect((try? AssistantTools.action(name: "run_shell", input: [:]).get()) == nil)
        #expect((try? AssistantTools.action(name: "get_today", input: ["x": 1]).get()) == nil)
        #expect((try? AssistantTools.action(name: "propose_tasks", input: ["tasks": []]).get()) == nil)
        #expect((try? AssistantTools.action(name: "propose_tasks", input: ["tasks": [["title": "  "]]]).get()) == nil)
        #expect((try? AssistantTools.action(name: "propose_tasks", input: ["tasks": [["title": "a", "priority": "urgent"]]]).get()) == nil)
        #expect((try? AssistantTools.action(name: "start_focus", input: ["minutes": 999]).get()) == nil)
        #expect((try? AssistantTools.action(name: "request_task_completion", input: [:]).get()) == nil)
    }
}

@Suite struct AssistantPromptTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "en_US")
        return c
    }()

    @Test func todaySummaryStatesWhatIsKnown() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let task = BuddyTask(title: "Write intro", priority: .high, estimateMinutes: 45, deadline: now)
        let done = BuddyTask(title: "Email Sam", completedAt: now)
        let text = AssistantPrompt.today(tasks: [task, done], focus: .init("idle"), focusedMinutesToday: 25,
                                         calendarConnected: false, events: [], now: now, calendar: calendar)
        #expect(text.contains("1 open, 1 done"))
        #expect(text.contains("[id \(task.id.uuidString)] Write intro (high priority, estimate 45 min, due today)"))
        #expect(text.contains("Done today: Email Sam"))
        #expect(text.contains("Calendar: not connected"))
    }

    @Test func systemPromptCarriesTheGroundRules() {
        let prompt = AssistantPrompt.system(name: "Coco")
        #expect(prompt.contains("get_today"))
        #expect(prompt.contains("never claim tasks were added, marked done"))
        #expect(prompt.contains("an event was created, moved or deleted unless a later note from the app confirms it"))
        #expect(prompt.contains("Never work out whether a time is free yourself"))
        #expect(prompt.contains("can't browse, message anyone, run commands"))
    }
}
