#if DEBUG
import SwiftUI
import BuddyCore
import BuddyIntegrations

// EXPERIMENT — chat as the reference's "Dialog" page. Same AssistantService and the same
// confirm-before-anything-changes cards; only the setting is new.

struct EOChatView: View {
    @Bindable var model: AppModel
    var openSection: (EOSection) -> Void
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

    private var assistant: AssistantService { model.assistant }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, EO.Space.pageTight)
                .padding(.top, EO.Space.lg)
                .eoEntrance(0)
            if assistant.isReady {
                conversation
                composer
            } else {
                EOChatNeedsKey(model: model)
            }
        }
        .onAppear { inputFocused = true }
        .onChange(of: model.panelOpenCount) { inputFocused = true }
    }

    private var header: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("Dialog")
                .font(EO.font(EO.Size.title, .medium))
                .tracking(EO.Tracking.tighter(EO.Size.title))
                .foregroundStyle(EO.ink)
            Spacer()
            EOKicker(status.text, color: status.color, size: EO.Size.caption)
                .eoPulse(assistant.isResponding)
        }
        .padding(.bottom, EO.Space.md)
        .overlay(alignment: .bottom) { EORule() }
    }

    private var status: (text: String, color: Color) {
        guard assistant.isReady else { return ("Offline", EO.Ink.muted) }
        switch assistant.phase {
        case .idle: return ("Active", EO.orange)
        case .waiting: return ("Thinking", EO.orange)
        case .usingTools: return ("Looking", EO.orange)
        case .writing: return ("Writing", EO.orange)
        }
    }

    // MARK: - Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: EO.Space.lg) {
                    if assistant.turns.isEmpty {
                        EOStarters { model.assistant.send($0) }
                            .eoEntrance(1)
                    }
                    ForEach(assistant.turns) { turn in
                        EOTurn(turn: turn)
                            .eoEntrance(1)
                    }
                    ForEach(model.pendingCompletions, id: \.self) { id in
                        if let task = model.tasks.task(id) {
                            EOConfirmCompletion(task: task, model: model)
                        }
                    }
                    if !model.taskDrafts.isEmpty, model.draftOrigin == .chat {
                        EOChatDrafts(model: model)
                    }
                    ForEach(model.eventRequests) { request in
                        EOEventRequest(request: request, model: model)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, EO.Space.pageTight)
                .padding(.vertical, EO.Space.lg)
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
        withAnimation(EO.Motion.slideUp) { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    // MARK: - Composer

    private var composer: some View {
        let empty = draft.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 10) {
            EORule(color: EO.ink)
            HStack(alignment: .center, spacing: 14) {
                Button { model.assistant.newChat() } label: {
                    Text("+").font(EO.font(EO.Size.item, .light)).foregroundStyle(EO.Ink.secondary)
                }
                .buttonStyle(.plain)
                .disabled(assistant.turns.isEmpty)
                .keyboardShortcut("n", modifiers: .command)
                .help("New chat (⌘N)")
                .accessibilityLabel("New chat")

                if model.voiceIn.isListening {
                    Text(model.voiceIn.transcript.isEmpty ? "Listening…" : model.voiceIn.transcript)
                        .font(EO.font(EO.Size.body, .light, italic: true))
                        .foregroundStyle(model.voiceIn.transcript.isEmpty ? EO.Ink.faint : EO.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Message", text: $draft, prompt: Text("Ask \(Buddy.name) anything…").foregroundStyle(EO.Ink.faint),
                              axis: .vertical)
                        .eoField(size: EO.Size.body)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .onSubmit(send)
                }
                Button { model.toggleListening() } label: {
                    Image(systemName: model.voiceIn.isListening ? "stop.fill" : "mic").font(.system(size: 11))
                }
                .buttonStyle(EOCircleButtonStyle(diameter: 30, filled: model.voiceIn.isListening))
                .keyboardShortcut("l", modifiers: .command)
                .help(model.voiceIn.isListening ? "Stop listening (⌘L)" : "Say it (⌘L)")

                if assistant.isResponding {
                    Button { assistant.stop() } label: { Image(systemName: "stop").font(.system(size: 11)) }
                        .buttonStyle(EOCircleButtonStyle(diameter: 36))
                        .keyboardShortcut(".", modifiers: .command)
                        .help("Stop the reply (⌘.)")
                } else {
                    Button(action: send) { Text("→") }
                        .buttonStyle(EOCircleButtonStyle(diameter: 36, filled: !empty))
                        .disabled(empty)
                        .help("Send (Return)")
                        .accessibilityLabel("Send")
                }
            }
            HStack {
                EOKicker("⌘N new · ⌘L talk", color: EO.Ink.faint, size: 9, weight: .medium)
                Spacer()
                if assistant.chatCost > 0 {
                    EOKicker("≈ $" + String(format: assistant.chatCost < 0.01 ? "%.3f" : "%.2f", assistant.chatCost) + " this chat",
                             color: EO.Ink.muted, size: 9, weight: .medium)
                        .help("Estimated at Anthropic's list prices")
                }
            }
        }
        .padding(.horizontal, EO.Space.pageTight)
        .padding(.bottom, 20)
        .animation(EO.Motion.hover, value: empty)
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !assistant.isResponding else { return }
        draft = ""
        model.assistant.send(text)
    }
}

// MARK: - Turns

private struct EOTurn: View {
    let turn: AssistantService.Turn

    var body: some View {
        switch turn.role {
        case .user:
            VStack(alignment: .leading, spacing: 8) {
                EOKicker("You", color: EO.Ink.muted, size: EO.Size.caption)
                Text("“\(turn.text)”")
                    .font(EO.font(EO.Size.lead, .light, italic: true))
                    .foregroundStyle(EO.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, EO.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .coco:
            VStack(alignment: .leading, spacing: 8) {
                EOKicker(Buddy.name, size: EO.Size.caption)
                ForEach(turn.activities, id: \.self) { activity in
                    Text("— " + activity)
                        .font(EO.font(12, .light, italic: true))
                        .foregroundStyle(EO.Ink.secondary)
                }
                if turn.text.isEmpty && turn.isStreaming {
                    EOThinking()
                } else if !turn.text.isEmpty {
                    Text(turn.text)
                        .font(EO.font(EO.Size.body, .medium))
                        .lineSpacing(5)
                        .foregroundStyle(EO.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let failure = turn.failure {
                    Text(failure)
                        .font(EO.font(13, .light, italic: true))
                        .foregroundStyle(EO.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.trailing, EO.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Three orange dots taking turns.
private struct EOThinking: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(EO.orange).frame(width: 6, height: 6)
                    .opacity(index == phase ? 1 : 0.25)
                    .offset(y: index == phase ? -2 : 0)
            }
        }
        .animation(EO.Motion.quick, value: phase)
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
        .accessibilityLabel("\(Buddy.name) is thinking")
    }
}

private struct EOStarters: View {
    let send: (String) -> Void
    private let prompts = [
        "What should I work on next?",
        "Plan the rest of my day",
        "What's on my calendar today?",
        "Break my top task into steps",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ask about your day, think something through, or get a plan. \(Buddy.name) looks at your tasks and calendars only when you ask.")
                .font(EO.font(16, .light))
                .foregroundStyle(EO.Ink.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, EO.Space.md)
            EOKicker("Begin with", color: EO.Ink.secondary, size: 10)
                .padding(.bottom, 4)
            ForEach(prompts, id: \.self) { prompt in
                EOStarterRow(text: prompt) { send(prompt) }
            }
        }
    }
}

private struct EOStarterRow: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(text)
                    .font(EO.font(EO.Size.lead, hovering ? .regular : .light, italic: hovering))
                    .foregroundStyle(EO.ink)
                Spacer()
                Text("→").font(EO.font(EO.Size.lead, .light)).foregroundStyle(EO.orange).opacity(hovering ? 1 : 0)
            }
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
        .onHover { hovering = $0 }
        .animation(EO.Motion.hover, value: hovering)
    }
}

// MARK: - Confirm cards

/// The editorial confirm block: an orange rule down the left, a kicker, the question.
private struct EOConfirmBlock<Content: View>: View {
    let kicker: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            EOKicker(kicker, size: 10)
            content
        }
        .padding(.leading, EO.Space.sm)
        .padding(.vertical, 4)
        .overlay(alignment: .leading) { Rectangle().fill(EO.orange).frame(width: 2) }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .offset(y: EO.Motion.slideDistance)))
    }
}

/// Coco can ask; only this marks a task done.
private struct EOConfirmCompletion: View {
    let task: BuddyTask
    let model: AppModel

    var body: some View {
        EOConfirmBlock(kicker: "Mark done?") {
            Text("“\(BuddyVoice.short(task.title, limit: 40))”")
                .font(EO.font(EO.Size.lead, .medium, italic: true))
                .foregroundStyle(EO.ink)
            HStack(spacing: EO.Space.md) {
                Button("Mark done") { model.confirmCompletion(task.id) }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .accent, size: 16))
                Button("Not yet") { model.declineCompletion(task.id) }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet, size: 16))
            }
        }
    }
}

/// Tasks Coco suggested in chat — editable, nothing added until Add.
private struct EOChatDrafts: View {
    @Bindable var model: AppModel

    var body: some View {
        EOConfirmBlock(kicker: "Suggested by \(Buddy.name) — review before adding") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach($model.taskDrafts) { $draft in
                    let index = model.taskDrafts.firstIndex { $0.id == draft.id } ?? 0
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d.", index + 1))
                            .font(EO.font(16, .light)).monospacedDigit().foregroundStyle(EO.Ink.secondary)
                        TextField("Task", text: $draft.title).eoField(size: 16, weight: .regular)
                        if draft.priority != .none {
                            Text(String(repeating: "!", count: draft.priority.rawValue)).font(EO.font(13, .bold)).foregroundStyle(EO.orange)
                        }
                        if let minutes = draft.estimateMinutes { EOKicker(TodayView.duration(minutes), color: EO.Ink.secondary, size: 9) }
                        Button { model.taskDrafts.removeAll { $0.id == draft.id } } label: {
                            Text("✕").font(EO.font(12, .light)).foregroundStyle(EO.Ink.muted)
                        }
                        .buttonStyle(.plain)
                        .help("Leave this one out")
                    }
                    .padding(.bottom, 6)
                    .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
                }
            }
            HStack(spacing: EO.Space.md) {
                Button(model.taskDrafts.count == 1 ? "Add task" : "Add \(model.taskDrafts.count) tasks") { model.addTaskDrafts() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .accent, size: 16))
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Discard") { model.discardTaskDrafts() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet, size: 16))
            }
        }
    }
}

/// A calendar change Coco proposed. Nothing happens in Google Calendar until confirmed,
/// and the block reports only what Google confirmed.
private struct EOEventRequest: View {
    let request: AppModel.EventRequest
    let model: AppModel

    var body: some View {
        EOConfirmBlock(kicker: heading) {
            content
            if !request.conflicts.isEmpty, case .waiting = request.state {
                ForEach(request.conflicts) { event in
                    Text("Overlaps “\(event.title)” \(AppModel.describe(event.start, event.end, allDay: false))")
                        .font(EO.font(13, .light, italic: true)).foregroundStyle(EO.orange)
                }
            }
            footer
        }
    }

    private var heading: String {
        switch request.kind {
        case .create: "Add to Google Calendar"
        case .change: "Change event"
        case .delete: "Delete event"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch request.kind {
        case .create(let draft):
            line(draft.title, AppModel.describe(draft.start, draft.end, allDay: draft.isAllDay), draft.location)
            if let source = draft.source {
                Link("From \(source.name) · keeps the invite link →", destination: source.url)
                    .font(EO.font(12, .light, italic: true)).foregroundStyle(EO.Ink.secondary)
            }
        case .change(let event, let changes):
            Text(changes.title ?? event.title)
                .font(EO.font(EO.Size.lead, .medium)).foregroundStyle(EO.ink)
            if let start = changes.start, let end = changes.end {
                Text(AppModel.describe(event.start, event.end, allDay: event.isAllDay))
                    .font(EO.font(14, .light)).foregroundStyle(EO.Ink.muted).strikethrough()
                Text("→ " + AppModel.describe(start, end, allDay: event.isAllDay))
                    .font(EO.font(14, .regular)).foregroundStyle(EO.ink)
            }
            if let location = changes.location {
                Text("Location: \(location)").font(EO.font(13, .light)).foregroundStyle(EO.Ink.secondary)
            }
            if event.isRecurring { EOKicker("Only this occurrence", color: EO.Ink.secondary, size: 9) }
            separateCopies(event)
        case .delete(let event):
            line(event.title, AppModel.describe(event.start, event.end, allDay: event.isAllDay), event.location)
            if event.isRecurring { EOKicker("Only this occurrence", color: EO.Ink.secondary, size: 9) }
            separateCopies(event)
        }
    }

    @ViewBuilder
    private func separateCopies(_ event: CalendarEvent) -> some View {
        let copies = event.alsoIn.filter { $0.match == .details }
        if !copies.isEmpty {
            Text("Only the Google Calendar event changes — the copy in \(copies.map(\.label).joined(separator: " and ")) stays as it is.")
                .font(EO.font(12, .light, italic: true)).foregroundStyle(EO.Ink.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func line(_ title: String, _ when: String, _ location: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(EO.font(EO.Size.lead, .medium)).foregroundStyle(EO.ink)
            Text(when).font(EO.font(14, .light)).foregroundStyle(EO.ink)
            if let location, !location.isEmpty {
                Text(location).font(EO.font(13, .light, italic: true)).foregroundStyle(EO.Ink.secondary).lineLimit(2)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch request.state {
        case .waiting:
            if !model.calendar.canChangeEvents {
                Text("The first time, Google asks you to let \(Buddy.name) change events.")
                    .font(EO.font(12, .light, italic: true)).foregroundStyle(EO.Ink.secondary)
            }
            HStack(spacing: EO.Space.md) {
                Button(confirmTitle) { model.confirmEventRequest(request.id) }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .accent, size: 16))
                Button("Not now") { model.declineEventRequest(request.id) }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet, size: 16))
            }
        case .working:
            EOKicker("Saving to Google Calendar…", color: EO.Ink.secondary, size: 10).eoPulse()
        case .failed(let message):
            Text("Nothing changed: \(message)").font(EO.font(13, .light, italic: true)).foregroundStyle(EO.orange)
            HStack(spacing: EO.Space.md) {
                Button("Try again") { model.confirmEventRequest(request.id) }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .accent, size: 16))
                Button("Dismiss") { model.dismissEventRequest(request.id) }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet, size: 16))
            }
        case .done(let outcome):
            HStack(alignment: .firstTextBaseline) {
                Text("✓ " + outcome).font(EO.font(14, .regular)).foregroundStyle(EO.ink).lineLimit(2)
                Spacer()
                Button("Dismiss") { model.dismissEventRequest(request.id) }
                    .buttonStyle(EOLinkButtonStyle(color: EO.Ink.secondary, arrow: ""))
            }
        }
    }

    private var confirmTitle: String {
        switch request.kind {
        case .create: "Add"
        case .change: "Change"
        case .delete: "Delete"
        }
    }
}

/// No API key yet: say so plainly, point to Connections. Everything else still works.
private struct EOChatNeedsKey: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: EO.Space.md) {
            Spacer()
            EODisplay([.plain("Chat needs"), .accent("a key.")], size: EO.Size.editorTitle)
            Text("Add a Claude API key in Connections. Tasks, focus and calendars work without it.")
                .font(EO.font(16, .light))
                .foregroundStyle(EO.Ink.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open Connections") { model.openConnections() }
                .buttonStyle(EOOutlineButtonStyle())
            Spacer()
            Spacer()
        }
        .padding(.horizontal, EO.Space.pageTight)
        .eoEntrance(1)
    }
}
#endif
