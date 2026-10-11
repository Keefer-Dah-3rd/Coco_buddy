import Foundation

/// The Claude Messages API, spoken over raw HTTP (there is no official Swift SDK).
///
/// Choices, from Anthropic's current guidance:
/// - `claude-opus-5-5` at **low effort**: conversational replies stay fast and cheap;
///   thinking is always on for this model and is controlled by effort, not disabled.
/// - **Server-side refusal fallback** (`fallbacks: "default"`): if a safety classifier
///   wrongly declines a benign message, Anthropic re-runs it on another Claude model.
/// - Tools use `tool_choice: auto` (forced tool use isn't accepted by this model).
/// - Top-level prompt caching; the system prompt and tool list never change mid-chat,
///   and history is append-only, so earlier turns stay cached and earlier thinking valid.
public enum ClaudeAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    public static let modelsEndpoint = URL(string: "https://api.anthropic.com/v1/models?limit=1")!
    public static let version = "2023-06-01"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    public static let model = "claude-opus-5-5"
    public static let effort = "low"
    /// Generous for a chat reply (thinking counts toward it) but bounds a runaway turn's cost.
    public static let maxTokens = 16_000

    public static func messagesRequest(apiKey: String, system: String, tools: [JSONValue], messages: [JSONValue]) throws -> URLRequest {
        let body: JSONValue = [
            "model": .string(model),
            "max_tokens": .number(Double(maxTokens)),
            "stream": true,
            "output_config": ["effort": .string(effort)],
            "fallbacks": "default",
            "cache_control": ["type": "ephemeral"],
            "system": [["type": "text", "text": .string(system)]],
            "tools": .array(tools),
            "tool_choice": ["type": "auto"],
            "messages": .array(messages),
        ]
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        headers(apiKey: apiKey).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue(fallbackBeta, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try body.encoded()
        return request
    }

    /// A free call that only checks the key works.
    public static func verifyKeyRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: modelsEndpoint)
        headers(apiKey: apiKey).forEach { request.setValue($1, forHTTPHeaderField: $0) }
        return request
    }

    static func headers(apiKey: String) -> [String: String] {
        ["x-api-key": apiKey, "anthropic-version": version]
    }

    /// `{"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}`
    public static func errorMessage(status: Int, body: Data) -> String {
        let message = (try? JSONValue.parse(body))?["error"]?["message"]?.string
        switch status {
        case 401: return "Anthropic didn't accept the API key. Check it in Connections."
        case 403: return message ?? "This API key isn't allowed to use that model."
        case 429: return "You've hit your Anthropic rate limit — try again in a moment."
        case 529: return "Claude is overloaded right now — try again in a moment."
        case 500...599: return "Anthropic had a problem (\(status)). Try again shortly."
        default: return message ?? "Request failed (\(status))."
        }
    }
}

/// Token usage for one response, and what it cost.
public struct ClaudeUsage: Equatable, Sendable {
    public var model: String = ClaudeAPI.model
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheReadTokens = 0
    public var cacheWriteTokens = 0

    public init() {}

    /// US dollars at list price. Falls back to Opus 5.5 rates for unknown models.
    public var estimatedCost: Double {
        let rates: (input: Double, output: Double, cacheRead: Double, cacheWrite: Double) =
            switch model {
            case "claude-opus-5", "claude-opus-4-8", "claude-opus-4-7": (5, 25, 0.5, 6.25)
            default: (4, 20, 0.2, 5)
            }
        let perToken = 1.0 / 1_000_000
        return (Double(inputTokens) * rates.input + Double(outputTokens) * rates.output
            + Double(cacheReadTokens) * rates.cacheRead + Double(cacheWriteTokens) * rates.cacheWrite) * perToken
    }
}

/// Rebuilds the assistant message from the server-sent event stream, block by block.
/// Blocks are kept as raw JSON (only filled in from deltas) so thinking blocks and
/// anything unfamiliar can be sent back exactly as received.
public struct StreamAccumulator: Sendable {
    public enum Update: Equatable, Sendable {
        /// Visible reply text to append.
        case text(String)
        /// A tool call began.
        case toolStarted(name: String)
    }

    public enum StreamError: Error, Equatable, Sendable {
        case server(String)
    }

    private var blocks: [Int: [String: JSONValue]] = [:]
    private var partialInputs: [Int: String] = [:]
    /// Tool calls whose input wasn't valid JSON: tool_use id → the raw text received.
    public private(set) var invalidToolInputs: [String: String] = [:]
    public private(set) var stopReason: String?
    public private(set) var usage = ClaudeUsage()
    public private(set) var visibleText = ""

    public init() {}

    /// Feeds one `data:` payload. Returns what the UI should show for it, if anything.
    @discardableResult
    public mutating func apply(_ event: JSONValue) throws -> Update? {
        switch event["type"]?.string {
        case "message_start":
            let message = event["message"]
            usage.model = message?["model"]?.string ?? usage.model
            readUsage(message?["usage"])
        case "content_block_start":
            guard let index = event["index"]?.int, var block = event["content_block"]?.object else { return nil }
            if block["type"]?.string == "tool_use" {
                block["input"] = .object([:])
                partialInputs[index] = ""
                blocks[index] = block
                return .toolStarted(name: block["name"]?.string ?? "tool")
            }
            blocks[index] = block
        case "content_block_delta":
            guard let index = event["index"]?.int, let delta = event["delta"], blocks[index] != nil else { return nil }
            switch delta["type"]?.string {
            case "text_delta":
                let text = delta["text"]?.string ?? ""
                let existing = blocks[index]?["text"]?.string ?? ""
                blocks[index]?["text"] = .string(existing + text)
                visibleText += text
                return text.isEmpty ? nil : .text(text)
            case "thinking_delta":
                let existing = blocks[index]?["thinking"]?.string ?? ""
                blocks[index]?["thinking"] = .string(existing + (delta["thinking"]?.string ?? ""))
            case "signature_delta":
                blocks[index]?["signature"] = .string(delta["signature"]?.string ?? "")
            case "input_json_delta":
                partialInputs[index, default: ""] += delta["partial_json"]?.string ?? ""
            default:
                break
            }
        case "content_block_stop":
            guard let index = event["index"]?.int, let raw = partialInputs[index] else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                blocks[index]?["input"] = .object([:])
            } else if let parsed = try? JSONValue.parse(trimmed), parsed.object != nil {
                blocks[index]?["input"] = parsed
            } else if let id = blocks[index]?["id"]?.string {
                invalidToolInputs[id] = raw
            }
            partialInputs[index] = nil
        case "message_delta":
            stopReason = event["delta"]?["stop_reason"]?.string ?? stopReason
            readUsage(event["usage"])
        case "error":
            throw StreamError.server(event["error"]?["message"]?.string ?? "The stream failed.")
        default:
            break
        }
        return nil
    }

    /// The finished content blocks in order, ready to append to history.
    public var content: [JSONValue] {
        blocks.keys.sorted().compactMap { blocks[$0].map(JSONValue.object) }
    }

    /// Text-only version, used when a reply was interrupted (no half-finished thinking or tool calls).
    public var textOnlyContent: [JSONValue] {
        visibleText.isEmpty ? [] : [["type": "text", "text": .string(visibleText)]]
    }

    public var toolCalls: [(id: String, name: String, input: JSONValue)] {
        content.compactMap { block in
            guard block["type"]?.string == "tool_use", let id = block["id"]?.string, let name = block["name"]?.string else { return nil }
            return (id, name, block["input"] ?? .object([:]))
        }
    }

    private mutating func readUsage(_ value: JSONValue?) {
        guard let value else { return }
        if let input = value["input_tokens"]?.int { usage.inputTokens = input }
        if let output = value["output_tokens"]?.int { usage.outputTokens = output }
        if let read = value["cache_read_input_tokens"]?.int { usage.cacheReadTokens = read }
        if let write = value["cache_creation_input_tokens"]?.int { usage.cacheWriteTokens = write }
    }
}

/// Extracts the JSON payload from one line of a server-sent event stream.
public enum SSE {
    public static func payload(from line: String) -> JSONValue? {
        guard line.hasPrefix("data:") else { return nil }
        let json = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard !json.isEmpty, json != "[DONE]" else { return nil }
        return try? JSONValue.parse(json)
    }
}
