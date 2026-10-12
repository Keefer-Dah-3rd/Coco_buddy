import SwiftUI
import BuddyCore

/// Talk to Coco. Short replies, visible activity ("Looked at your tasks"), and nothing
/// changes in your list without a confirmation step in the panel.
struct ChatView: View {
    @Bindable var model: AppModel
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var assistant: AssistantService { model.assistant }

    var body: some View {
        VStack(spacing: 0) {
            if assistant.isReady {
                conversation
                Rectangle().fill(Theme.hairline).frame(height: 1)
                composer
            } else {
                ConnectPrompt(model: model)
            }
        }
        .onAppear { inputFocused = true }
        .onChange(of: model.panelOpenCount) { inputFocused = true }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.lg) {
                    if assistant.turns.isEmpty {
                        Starters { model.assistant.send($0) }
                    }
                    ForEach(assistant.turns) { turn in
                        TurnView(turn: turn)
                    }
                    ForEach(model.pendingCompletions, id: \.self) { id in
                        if let task = model.tasks.task(id) {
                            CompletionConfirmCard(task: task, model: model)
                        }
                    }
                    if !model.taskDrafts.isEmpty, model.draftOrigin == .chat {
                        TaskDraftReviewCard(model: model)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(Space.xl)
            }
            .scrollIndicators(.never)
            .onChange(of: assistant.turns.last?.text) { scrollToBottom(proxy) }
            .onChange(of: assistant.turns.count) { scrollToBottom(proxy) }
            .onChange(of: model.pendingCompletions.count) { scrollToBottom(proxy) }
            .onChange(of: model.taskDrafts.count) { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .bottom, spacing: Space.sm) {
                if model.voiceIn.isListening {
                    Text(model.voiceIn.transcript.isEmpty ? "Listening…" : model.voiceIn.transcript)
                        .font(.style(.body))
                        .foregroundStyle(model.voiceIn.transcript.isEmpty ? Theme.inkTertiary : Theme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 7)
                } else {
                    TextField("Message", text: $draft, prompt: Text("Ask \(Buddy.name) anything…").foregroundStyle(Theme.inkTertiary),
                              axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.style(.body))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onSubmit(send)
                        .padding(.vertical, 7)
                }
                IconKey(symbol: model.voiceIn.isListening ? "stop.fill" : "mic.fill",
                        help: model.voiceIn.isListening ? "Stop listening (⌘L)" : "Say it (⌘L)",
                        prominent: model.voiceIn.isListening) { model.toggleListening() }
                    .keyboardShortcut("l", modifiers: .command)
                if assistant.isResponding {
                    IconKey(symbol: "stop.fill", help: "Stop the reply (⌘.)", prominent: false) { assistant.stop() }
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    IconKey(symbol: "arrow.up", help: "Send (Return)", prominent: !draft.trimmingCharacters(in: .whitespaces).isEmpty) { send() }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, Space.md)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))

            HStack(spacing: Space.md) {
                Button("New chat") { model.assistant.newChat() }
                    .buttonStyle(.plain)
                    .font(.style(.monoTiny))
                    .foregroundStyle(Theme.inkSecondary)
                    .disabled(assistant.turns.isEmpty)
                    .keyboardShortcut("n", modifiers: .command)
                Spacer()
                if assistant.chatCost > 0 {
                    MonoLabel("≈ $" + String(format: assistant.chatCost < 0.01 ? "%.3f" : "%.2f", assistant.chatCost) + " this chat",
                              color: Theme.inkTertiary)
                        .help("Estimated at Anthropic's list prices")
                }
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.md)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !assistant.isResponding else { return }
        draft = ""
        model.assistant.send(text)
    }
}

// MARK: - Pieces

private struct TurnView: View {
    let turn: AssistantService.Turn

    var body: some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(turn.text)
                    .font(.style(.body))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, Space.md)
                    .padding(.vertical, 7)
                    .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        case .coco:
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(turn.activities, id: \.self) { activity in
                    HStack(spacing: 5) {
                        Circle().fill(Theme.accent).frame(width: 4, height: 4)
                        MonoLabel(activity, color: Theme.inkSecondary)
                    }
                }
                if !turn.text.isEmpty || turn.isStreaming {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("›").font(Theme.mono(13, .bold)).foregroundStyle(Theme.accent)
                        if turn.text.isEmpty {
                            ThinkingDots()
                        } else {
                            Text(turn.text)
                                .font(.style(.body))
                                .foregroundStyle(Theme.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                if let failure = turn.failure {
                    Text(failure)
                        .font(.style(.caption))
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Theme.inkSecondary).frame(width: 5, height: 5).opacity(index == phase ? 1 : 0.3)
            }
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityLabel("\(Buddy.name) is thinking")
    }
}

/// Coco can ask; only this card marks a task done.
private struct CompletionConfirmCard: View {
    let task: BuddyTask
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Mark “\(BuddyVoice.short(task.title, limit: 40))” done?")
                .font(.style(.bodySmallEmphasis))
                .foregroundStyle(Theme.ink)
            HStack(spacing: Space.sm) {
                Button { model.confirmCompletion(task.id) } label: { Label("Mark done", systemImage: "checkmark") }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true, compact: true))
                Button("Not yet") { model.declineCompletion(task.id) }
                    .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            }
        }
        .padding(Space.md)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private struct Starters: View {
    let send: (String) -> Void
    private let prompts = [
        "What should I work on next?",
        "Plan the rest of my day",
        "Break my top task into steps",
        "Help me brainstorm",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Text("Ask about your day, think something through, or get a plan. \(Buddy.name) looks at your tasks and calendar only when you ask about them.")
                .font(.style(.bodySmall))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(prompts, id: \.self) { prompt in
                Button { send(prompt) } label: {
                    HStack {
                        Text(prompt).font(.style(.bodySmall)).foregroundStyle(Theme.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(.horizontal, Space.md)
                    .frame(height: 28)
                    .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Theme.hairline))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ConnectPrompt: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: Space.lg) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
            Text("Chat needs a Claude API key.")
                .font(.style(.bodyEmphasis))
                .foregroundStyle(Theme.ink)
            Text("Add it in Connections. Everything else works without it.")
                .font(.style(.bodySmall))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Open Connections") { model.openConnections() }
                .buttonStyle(KeyButtonStyle(kind: .primary, compact: true))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(Space.xl)
    }
}

private struct IconKey: View {
    let symbol: String
    let help: String
    let prominent: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(prominent ? Theme.onAccent : Theme.inkSecondary)
                .frame(width: 26, height: 26)
                .background(prominent ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .padding(.vertical, Space.xxs)
    }
}
