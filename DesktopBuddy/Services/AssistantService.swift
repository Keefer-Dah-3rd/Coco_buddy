import Foundation
import Observation
import BuddyAssistant
import os

/// The chat: sends messages to Claude, streams replies, and runs the assistant's tool calls
/// through the app (never on its own). History is append-only — exactly what the API
/// returned is sent back — and lives in memory only; "New chat" forgets it.
@Observable
final class AssistantService {
    enum KeyStatus: Equatable { case missing, verifying, ready, invalid }

    /// What the assistant is doing right now — drives Coco's expression.
    enum Phase: Equatable { case idle, waiting, writing, usingTools }

    struct Turn: Identifiable, Equatable {
        enum Role { case user, coco }
        let id = UUID()
        let role: Role
        var text: String
        /// Things Coco did or looked at during this reply ("Looked at your tasks").
        var activities: [String] = []
        var failure: String?
        var isStreaming = false
    }

    /// What a tool call did, as reported back to the model and shown in the chat.
    struct ToolOutcome {
        var result: String
        var isError = false
        var activity: String?
    }

    private(set) var keyStatus: KeyStatus = .missing
    private(set) var keyProblem: String?
    private(set) var turns: [Turn] = []
    private(set) var phase: Phase = .idle
    /// Estimated spend for this chat, at list prices.
    private(set) var chatCost: Double = 0

    var isReady: Bool { keyStatus == .ready }
    var isResponding: Bool { phase != .idle }

    @ObservationIgnored var performAction: ((AssistantAction) async -> ToolOutcome)?
    @ObservationIgnored var onPhaseChanged: ((Phase) -> Void)?
    @ObservationIgnored var onReplyFinished: ((String) -> Void)?
    /// The day the schedule card is showing, when it's open — mentioned in each message's note.
    @ObservationIgnored var viewingDay: (() -> Date?)?
    @ObservationIgnored var onChatCleared: (() -> Void)?
    /// Whether the user has allowed the chat to send their data to Anthropic. Nothing is sent
    /// while this says no — whichever screen or shortcut tries.
    @ObservationIgnored var mayShare: () -> Bool = { false }

    @ObservationIgnored private var apiKey: String?
    @ObservationIgnored private var history: [JSONValue] = []
    @ObservationIgnored private var pendingNotes: [String] = []
    @ObservationIgnored private var pendingNoteKeys: [String?] = []
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "assistant")
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration)
    }()

    private static let keyAccount = "anthropic.apiKey"
    private static let maxToolRounds = 6

    init(persistent: Bool = true) {
        self.persistent = persistent
        guard persistent else { return }
        Task { [weak self] in
            guard let saved = await Keychain.stringInBackground(for: Self.keyAccount), let self, self.apiKey == nil else { return }
            self.apiKey = saved
            self.keyStatus = .ready
        }
    }

    // MARK: - Key

    /// Checks the key with a free API call before saving it to the Keychain.
    func connect(key raw: String) async {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyStatus = .verifying
        keyProblem = nil
        do {
            let (data, response) = try await session.data(for: ClaudeAPI.verifyKeyRequest(apiKey: key))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                keyStatus = status == 401 ? .invalid : (apiKey == nil ? .missing : .ready)
                keyProblem = ClaudeAPI.errorMessage(status: status, body: data)
                return
            }
            apiKey = key
            if persistent, !Keychain.set(Data(key.utf8), for: Self.keyAccount) {
                keyProblem = "Connected, but the Keychain wouldn't save the key (error \(Keychain.lastStatus)), so you'll need to paste it again next launch."
            }
            keyStatus = .ready
        } catch {
            keyStatus = apiKey == nil ? .missing : .ready
            keyProblem = "Couldn't reach Anthropic — check your connection."
        }
    }

    func disconnect() {
        newChat()
        Keychain.remove(Self.keyAccount)
        apiKey = nil
        keyStatus = .missing
        keyProblem = nil
    }

    // MARK: - Chat

    /// Something that happened in the app since the last message (e.g. the user confirmed
    /// a task). Told to Claude with the next message so it never assumes. A note with a `key`
    /// replaces an earlier one with the same key that hasn't been sent yet.
    func note(_ text: String, key: String? = nil) {
        if let key {
            if let index = pendingNoteKeys.firstIndex(of: key) {
                pendingNotes.remove(at: index)
                pendingNoteKeys.remove(at: index)
            }
        }
        pendingNotes.append(text)
        pendingNoteKeys.append(key)
    }

    func newChat() {
        stop()
        history = []
        turns = []
        pendingNotes = []
        pendingNoteKeys = []
        chatCost = 0
        onChatCleared?()
    }

    func stop() {
        task?.cancel()
    }

    func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, isReady, !isResponding, mayShare() else { return }
        turns.append(Turn(role: .user, text: text))

        let blocks: [JSONValue] = [
            ["type": "text", "text": .string(AssistantPrompt.turnNote(now: .now, events: pendingNotes, viewing: viewingDay?()))],
            ["type": "text", "text": .string(text)],
        ]
        pendingNotes = []
        pendingNoteKeys = []
        if let last = history.last, last["role"] == "user", let content = last["content"]?.array {
            // The previous message never got a reply (error or stop): append to it, so
            // turns still alternate and nothing earlier is rewritten.
            history[history.count - 1] = ["role": "user", "content": .array(content + blocks)]
        } else {
            history.append(["role": "user", "content": .array(blocks)])
        }

        turns.append(Turn(role: .coco, text: "", isStreaming: true))
        setPhase(.waiting)
        task = Task { await runTurn() }
    }

    // MARK: - The loop

    private func runTurn() async {
        defer {
            finishCurrentTurn()
            setPhase(.idle)
        }
        for _ in 0..<Self.maxToolRounds {
            setPhase(.waiting)
            var accumulator = StreamAccumulator()
            do {
                try await stream(into: &accumulator)
            } catch {
                chatCost += accumulator.usage.estimatedCost
                keepPartialText(accumulator)
                if isCancellation(error) {
                    addActivity("Stopped")
                } else {
                    currentTurn { $0.failure = message(for: error) }
                    log.error("Chat request failed: \(self.message(for: error), privacy: .public)")
                }
                return
            }
            chatCost += accumulator.usage.estimatedCost

            if accumulator.stopReason == "refusal" {
                // Declined even after the fallback model: discard any partial output.
                currentTurn { $0.text = "I can't help with that one." }
                return
            }
            let content = accumulator.content
            if !content.isEmpty {
                history.append(["role": "assistant", "content": .array(content)])
            }
            let calls = accumulator.toolCalls
            guard accumulator.stopReason == "tool_use", !calls.isEmpty else {
                if accumulator.stopReason == "max_tokens" { addActivity("Reply was cut short") }
                onReplyFinished?(turns.last?.text ?? "")
                return
            }

            setPhase(.usingTools)
            var results: [JSONValue] = []
            for call in calls {
                results.append(await runTool(id: call.id, name: call.name, input: call.input,
                                             invalidInput: accumulator.invalidToolInputs[call.id]))
            }
            // All results for this turn go back together, in one message.
            history.append(["role": "user", "content": .array(results)])
            if Task.isCancelled { addActivity("Stopped"); return }
        }
        addActivity("Stopped after several steps")
    }

    private func stream(into accumulator: inout StreamAccumulator) async throws {
        guard let apiKey else { throw ChatError.message("Add your Anthropic API key in Connections.") }
        let request = try ClaudeAPI.messagesRequest(apiKey: apiKey,
                                                    system: AssistantPrompt.system(name: Buddy.name, canChangeCalendar: Features.googleSignIn),
                                                    tools: AssistantTools.definitions(canChangeCalendar: Features.googleSignIn),
                                                    messages: history)
        let (bytes, response) = try await session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var body = Data()
            for try await byte in bytes {
                body.append(byte)
                if body.count > 64_000 { break }
            }
            if status == 401 { keyStatus = .invalid }
            throw ChatError.message(ClaudeAPI.errorMessage(status: status, body: body))
        }
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = SSE.payload(from: line) else { continue }
            switch try accumulator.apply(event) {
            case .text(let text):
                setPhase(.writing)
                currentTurn { $0.text += text }
            case .toolStarted:
                setPhase(.usingTools)
            case nil:
                break
            }
        }
    }

    private func runTool(id: String, name: String, input: JSONValue, invalidInput: String?) async -> JSONValue {
        func result(_ text: String, error: Bool) -> JSONValue {
            ["type": "tool_result", "tool_use_id": .string(id), "content": .string(text), "is_error": .bool(error)]
        }
        if let invalidInput {
            let wrapped = (try? JSONValue.object(["INVALID_JSON": .string(invalidInput)]).encoded()).flatMap { String(data: $0, encoding: .utf8) }
            return result(wrapped ?? "INVALID_JSON", error: true)
        }
        switch AssistantTools.action(name: name, input: input) {
        case .failure(let error):
            log.notice("Rejected tool call \(name, privacy: .public)")
            return result("Not run — invalid input: \(error)", error: true)
        case .success(let action):
            guard let performAction else { return result("That isn't available right now.", error: true) }
            let outcome = await performAction(action)
            if let activity = outcome.activity { addActivity(activity) }
            return result(outcome.result, error: outcome.isError)
        }
    }

    // MARK: - Helpers

    private enum ChatError: Error { case message(String) }

    private func message(for error: Error) -> String {
        switch error {
        case ChatError.message(let text): text
        case StreamAccumulator.StreamError.server(let text): "Claude stopped partway: \(text)"
        case let url as URLError where url.code == .timedOut: "Claude took too long to answer. Try again."
        case is URLError: "Can't reach Anthropic — check your connection."
        default: error.localizedDescription
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled
    }

    /// After a stop or error, keep only finished text — no half-written thinking or tool calls.
    private func keepPartialText(_ accumulator: StreamAccumulator) {
        let text = accumulator.textOnlyContent
        if !text.isEmpty { history.append(["role": "assistant", "content": .array(text)]) }
    }

    private func currentTurn(_ change: (inout Turn) -> Void) {
        guard let index = turns.indices.last, turns[index].role == .coco else { return }
        change(&turns[index])
    }

    private func addActivity(_ activity: String) {
        currentTurn { $0.activities.append(activity) }
    }

    private func finishCurrentTurn() {
        currentTurn { turn in
            turn.isStreaming = false
            if turn.text.isEmpty && turn.activities.isEmpty && turn.failure == nil { turn.text = "…" }
        }
    }

    private func setPhase(_ new: Phase) {
        guard new != phase else { return }
        phase = new
        onPhaseChanged?(new)
    }
}

#if DEBUG
extension AssistantService {
    /// Snapshot renderer only: a sample conversation, no key or network involved.
    func loadPreview(_ sample: [Turn], cost: Double) {
        keyStatus = .ready
        turns = sample
        chatCost = cost
    }
}
#endif
