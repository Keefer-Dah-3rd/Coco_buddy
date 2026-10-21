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
            if assistant.isReady && model.hasAIConsent {
                conversation
                Rectangle().fill(Sky.line).frame(height: 1)
                composer
            } else if assistant.isReady {
                AIConsentCard(model: model)
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
                VStack(alignment: .leading, spacing: 14) {
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
                    ForEach(model.eventRequests) { request in
                        EventRequestCard(request: request, model: model)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
            }
            .scrollIndicators(.never)
            .onChange(of: assistant.turns.last?.text) { scrollToBottom(proxy) }
            .onChange(of: assistant.turns.count) { scrollToBottom(proxy) }
            .onChange(of: model.pendingCompletions.count) { scrollToBottom(proxy) }
            .onChange(of: model.taskDrafts.count) { scrollToBottom(proxy) }
            .onChange(of: model.eventRequests.count) { scrollToBottom(proxy) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                if model.voiceIn.isListening {
                    Text(model.voiceIn.transcript.isEmpty ? "Listening…" : model.voiceIn.transcript)
                        .font(Sky.text(13))
                        .foregroundStyle(model.voiceIn.transcript.isEmpty ? Sky.faint : Sky.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                } else {
                    TextField("Message", text: $draft, prompt: Text("Ask \(Buddy.name) anything…").foregroundStyle(Sky.faint),
                              axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Sky.text(13))
                        .foregroundStyle(Sky.ink)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onSubmit(send)
                        .padding(.vertical, 8)
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
            .padding(.leading, 14)
            .padding(.trailing, 5)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).fill(Sky.well))

            HStack(spacing: 12) {
                Button("New chat") { model.assistant.newChat() }
                    .buttonStyle(.plain)
                    .font(Sky.text(11, .medium))
                    .foregroundStyle(Sky.muted)
                    .disabled(assistant.turns.isEmpty)
                    .keyboardShortcut("n", modifiers: .command)
                Spacer()
                if assistant.chatCost > 0 {
                    SkyKicker("≈ $" + String(format: assistant.chatCost < 0.01 ? "%.3f" : "%.2f", assistant.chatCost) + " this chat")
                        .help("Estimated at Anthropic's list prices")
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
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
                    .font(Sky.text(13))
                    .foregroundStyle(Sky.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Sky.bubbleYou))
            }
        case .coco:
            HStack(alignment: .top, spacing: 9) {
                // Coco's voice: a pale disc with her chevron, the same mark as the speech line.
                Text("›")
                    .font(Sky.text(13, .bold))
                    .foregroundStyle(Sky.accentText)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Sky.accentPale))
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(turn.activities, id: \.self) { activity in
                        HStack(spacing: 5) {
                            Circle().fill(Sky.accent).frame(width: 4, height: 4)
                            SkyKicker(activity)
                        }
                    }
                    if !turn.text.isEmpty || turn.isStreaming {
                        if turn.text.isEmpty {
                            ThinkingDots()
                                .padding(.top, 5)
                        } else {
                            Text(turn.text)
                                .font(Sky.text(13))
                                .foregroundStyle(Sky.ink)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 2)
                        }
                    }
                    if let failure = turn.failure {
                        Text(failure)
                            .font(Sky.text(11))
                            .foregroundStyle(Sky.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // App Review asks AI chat apps for a way to report a reply. Opens an email to
                    // support with the reply quoted; nothing is sent unless the user sends it.
                    if !turn.isStreaming, !turn.text.isEmpty, let report = Support.reportReply(turn.text) {
                        Button { NSWorkspace.shared.open(report) } label: {
                            Text("Report").font(Sky.text(11)).foregroundStyle(Sky.faint)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                        .help("Report this reply — opens an email to \(Support.email)")
                        .accessibilityLabel("Report this reply")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ThinkingDots: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Sky.muted).frame(width: 5, height: 5).opacity(index == phase ? 1 : 0.3)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Mark “\(BuddyVoice.short(task.title, limit: 40))” done?")
                .font(Sky.text(13, .semibold))
                .foregroundStyle(Sky.ink)
            HStack(spacing: 8) {
                Button { model.confirmCompletion(task.id) } label: { Label("Mark done", systemImage: "checkmark") }
                    .buttonStyle(SkyButtonStyle(kind: .accent, compact: true, fillWidth: true))
                Button("Not yet") { model.declineCompletion(task.id) }
                    .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            }
        }
        .padding(12)
        .skyCard(radius: Sky.Radius.card)
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask about your day, think something through, or get a plan. \(Buddy.name) looks at your tasks and calendar only when you ask about them.")
                .font(Sky.text(12))
                .foregroundStyle(Sky.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(prompts, id: \.self) { prompt in
                SkyActionRow(title: prompt, symbol: "arrow.up.right") { send(prompt) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.well))
    }
}

/// Asked once, before anything is sent: what the chat shares with Anthropic, and when.
struct AIConsentCard: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Before you chat")
                        .font(Sky.display(20))
                        .tracking(-0.4)
                        .foregroundStyle(Sky.ink)
                    Text("To answer you, \(Buddy.name) sends some of your information to \(AIConsent.recipient), using your API key. Here's exactly what.")
                        .font(Sky.text(12))
                        .foregroundStyle(Sky.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                group("Every message", AIConsent.always)
                group("Only when \(Buddy.name) needs it to answer", AIConsent.whenNeeded)
                VStack(alignment: .leading, spacing: 6) {
                    SkyKicker("Never sent")
                    Text(AIConsent.never)
                        .font(Sky.text(12))
                        .foregroundStyle(Sky.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("The chat shows each time \(Buddy.name) looks something up. Anthropic handles it under its privacy policy, and usage is billed to your Anthropic account. Chats stay in memory on this Mac and are gone when you quit. You can turn this off any time in Settings › Privacy & data.")
                    .font(Sky.text(11))
                    .foregroundStyle(Sky.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Anthropic's privacy policy", destination: AIConsent.privacyPolicy)
                    .font(Sky.text(11, .medium))
                    .foregroundStyle(Sky.accentText)
                HStack(spacing: 8) {
                    Button("Allow") { model.allowAIChat() }
                        .buttonStyle(SkyButtonStyle(kind: .accent, compact: true, fillWidth: true))
                        .accessibilityLabel("Allow the chat to send this to Anthropic")
                    Button("Not now") { model.panelTab = .today }
                        .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                        .accessibilityLabel("Not now: keep the chat off")
                }
            }
            .padding(20)
        }
        .scrollIndicators(.never)
    }

    private func group(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SkyKicker(title)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Sky.accent).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                    Text(item)
                        .font(Sky.text(12))
                        .foregroundStyle(Sky.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct ConnectPrompt: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(Sky.accentText)
                .frame(width: 52, height: 52)
                .background(Circle().fill(Sky.accentPale))
            Text("Chat needs a Claude API key.")
                .font(Sky.text(14, .semibold))
                .foregroundStyle(Sky.ink)
            Text("Add it in Connections. Everything else works without it.")
                .font(Sky.text(12))
                .foregroundStyle(Sky.muted)
                .multilineTextAlignment(.center)
            Button("Open Connections") { model.openConnections() }
                .buttonStyle(SkyButtonStyle(kind: .accent, compact: true))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(20)
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
                .foregroundStyle(prominent ? Sky.ink : Sky.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(prominent ? Sky.accent : Sky.paper))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .padding(.vertical, 4)
    }
}
