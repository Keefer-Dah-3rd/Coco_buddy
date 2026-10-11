import SwiftUI
import BuddyCore

/// Today's list: a counter, a one-line quick-add field and the tasks.
struct TodayView: View {
    let model: AppModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let tasks = model.tasks.today()
        let done = tasks.filter(\.isCompleted).count

        VStack(alignment: .leading, spacing: 0) {
            summary(done: done, tasks: tasks)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            quickAdd
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            if !model.taskDrafts.isEmpty {
                TaskDraftReviewCard(model: model)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            let leftovers = model.tasks.leftovers
            let hasConnections = model.calendar.isConnected || (Features.notion && model.notion.isReady)
            if tasks.isEmpty && leftovers.isEmpty && !hasConnections {
                EmptyTodayView()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if let pending = model.pendingNotionCompletion {
                                NotionCompletionCard(model: model, task: pending)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                            if model.calendar.isConnected {
                                ScheduleStrip(model: model)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                            if Features.notion, model.notion.isReady, !model.notionCandidates.isEmpty {
                                NotionPickerCard(model: model)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                            if !leftovers.isEmpty {
                                LeftoversBanner(count: leftovers.count, model: model)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 8)
                            }
                            if model.taskDrafts.isEmpty, !model.focus.timer.isActive, let next = model.upNext {
                                UpNextCard(task: next.task, reason: next.reason, model: model)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 4)
                            }
                            ForEach(tasks) { task in
                                TaskRow(
                                    task: task,
                                    isInFocus: model.focus.timer.isActive && model.focus.timer.taskID == task.id,
                                    model: model
                                )
                                .id(task.id)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollIndicators(.never)
                    .onAppear { reveal(model.editingTaskID, with: proxy, animated: false) }
                    .onChange(of: model.editingTaskID) { _, id in reveal(id, with: proxy, animated: true) }
                }
            }

            if let removed = model.recentlyRemoved {
                undoBar(removed)
            } else if let problem = model.tasks.storageProblem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
        .animation(.snappy(duration: 0.25), value: model.taskDrafts.isEmpty)
        .animation(.snappy(duration: 0.25), value: model.tasks.leftovers.isEmpty)
        .onAppear { fieldFocused = true }
        .onChange(of: model.panelOpenCount) { fieldFocused = true }
    }

    // MARK: - Pieces

    private func summary(done: Int, tasks: [BuddyTask]) -> some View {
        let remainingMinutes = tasks.filter { !$0.isCompleted }.compactMap(\.estimateMinutes).reduce(0, +)
        let focused = model.focusLog.today
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(done)")
                    .foregroundStyle(Theme.ink)
                Text("/\(tasks.count)")
                    .foregroundStyle(Theme.inkTertiary)
                MonoLabel("done").padding(.leading, 8)
                Spacer()
            }
            .font(.system(size: 30, weight: .semibold).monospacedDigit())
            .contentTransition(.numericText())
            .animation(.snappy, value: done)

            SegmentMeter(done: done, total: tasks.count)

            if focused.minutes > 0 || remainingMinutes > 0 {
                HStack {
                    if focused.minutes > 0 {
                        MonoLabel("Focused \(Self.duration(focused.minutes)) today", color: Theme.ink)
                    }
                    Spacer()
                    if remainingMinutes > 0 {
                        MonoLabel("≈ \(Self.duration(remainingMinutes)) left")
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(done) of \(tasks.count) tasks done. \(focused.minutes) minutes focused today.")
    }

    private var quickAdd: some View {
        let parsed = QuickAddParser.parse(draft)
        let voice = model.voiceIn
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if voice.isListening {
                    ListeningDot()
                    Text(voice.transcript.isEmpty ? "Listening… say a task or “start focus”" : voice.transcript)
                        .font(.system(size: 13))
                        .foregroundStyle(voice.transcript.isEmpty ? Theme.inkTertiary : Theme.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("+").font(Theme.mono(15, .semibold)).foregroundStyle(Theme.accent)
                    TextField("Add task", text: $draft, prompt: Text("Add a task… try “Draft intro ~30m !!”")
                        .foregroundStyle(Theme.inkTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                        .focused($fieldFocused)
                        .onSubmit(submit)
                    if !draft.isEmpty {
                        Text("↵").font(Theme.mono(11)).foregroundStyle(Theme.inkTertiary)
                    }
                }
                MicButton(isListening: voice.isListening) { model.toggleListening() }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(fieldFocused ? Theme.ink.opacity(0.5) : .clear, lineWidth: 1))

            if voice.isListening, !voice.isOnDevice {
                MonoLabel("Transcribed by Apple's speech service")
                    .padding(.leading, 2)
            }
            switch voice.status {
            case .denied(let message), .unavailable(let message):
                VoiceProblem(message: message, settingsURL: message.contains("Microphone")
                             ? VoiceInput.microphoneSettingsURL : VoiceInput.speechSettingsURL) {
                    voice.clearProblem()
                }
            default:
                EmptyView()
            }

            // Live read-back of the shorthand, so the syntax teaches itself.
            if !voice.isListening, let parsed, parsed.priority != .none || parsed.estimateMinutes != nil {
                HStack(spacing: 10) {
                    if let minutes = parsed.estimateMinutes { MonoLabel("Est. \(Self.duration(minutes))") }
                    if parsed.priority != .none { MonoLabel("\(parsed.priority.label) priority", color: Theme.accent) }
                }
                .padding(.leading, 2)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: parsed?.estimateMinutes)
        .animation(.easeOut(duration: 0.15), value: parsed?.priority)
    }

    private func undoBar(_ task: BuddyTask) -> some View {
        HStack {
            Text("Removed “\(BuddyVoice.short(task.title, limit: 26))”")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Spacer()
            Button("Undo") { model.undoRemove() }
                .buttonStyle(KeyButtonStyle(kind: .secondary))
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.well)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Keeps an open editor in view.
    private func reveal(_ id: BuddyTask.ID?, with proxy: ScrollViewProxy, animated: Bool) {
        guard let id else { return }
        if animated {
            withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
        } else {
            proxy.scrollTo(id, anchor: .top)
        }
    }

    private func submit() {
        if model.addTask(draft) { draft = "" }
    }

    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes)m" : minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }
}

/// One block per task — an LED-style meter. Becomes a continuous bar for long lists.
private struct SegmentMeter: View {
    let done: Int
    let total: Int

    var body: some View {
        GeometryReader { proxy in
            if total == 0 {
                Rectangle().fill(Theme.hairline).frame(height: 1).frame(maxHeight: .infinity)
            } else if total <= 16 {
                HStack(spacing: 3) {
                    ForEach(0..<total, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < done ? Theme.ink : Theme.hairline)
                    }
                }
            } else {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.hairline)
                    RoundedRectangle(cornerRadius: 1.5).fill(Theme.ink)
                        .frame(width: proxy.size.width * CGFloat(done) / CGFloat(total))
                }
            }
        }
        .frame(height: 6)
        .animation(.snappy, value: done)
        .animation(.snappy, value: total)
    }
}

private struct EmptyTodayView: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 44, height: 30)
                .overlay(Text("+").font(Theme.mono(14, .medium)).foregroundStyle(Theme.inkTertiary))
            VStack(spacing: 4) {
                Text("Nothing on the list yet.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                Text("Type above and press Return.\nAdd ~25m for an estimate, ! to !!! for priority,\n@today for a one-day item.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Voice

private struct MicButton: View {
    let isListening: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: isListening ? 9 : 11, weight: .semibold))
                .foregroundStyle(isListening ? Theme.onAccent : (hovering ? Theme.ink : Theme.inkSecondary))
                .frame(width: 24, height: 24)
                .background(isListening ? Theme.accent : (hovering ? Theme.hairline : .clear),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .keyboardShortcut("l", modifiers: .command)
        .help(isListening ? "Stop listening (⌘L)" : "Talk to \(Buddy.name) (⌘L)")
        .accessibilityLabel(isListening ? "Stop listening" : "Talk to \(Buddy.name)")
    }
}

/// Pulses while the microphone is open — the on-screen twin of Coco's glowing tag.
private struct ListeningDot: View {
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .opacity(pulse ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
            .accessibilityLabel("Microphone on")
    }
}

private struct VoiceProblem: View {
    let message: String
    let settingsURL: URL
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Settings") { NSWorkspace.shared.open(settingsURL) }
                .buttonStyle(KeyButtonStyle(kind: .secondary))
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.inkTertiary)
                .help("Dismiss")
        }
        .padding(.top, 2)
    }
}

/// What Coco heard, as editable rows. Nothing is added until "Add".
struct TaskDraftReviewCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                MonoLabel((model.draftOrigin == .chat ? "Suggested by \(Buddy.name)" : "Heard") + " — review before adding",
                          color: Theme.accent)
                Spacer()
            }
            ForEach($model.taskDrafts) { $draft in
                HStack(spacing: 8) {
                    TextField("Task", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.ink)
                    if draft.priority != .none {
                        Text(String(repeating: "!", count: draft.priority.rawValue))
                            .font(Theme.mono(10, .bold))
                            .foregroundStyle(Theme.accent)
                    }
                    if let minutes = draft.estimateMinutes {
                        MonoLabel(TodayView.duration(minutes), color: Theme.inkTertiary)
                    }
                    Button {
                        model.taskDrafts.removeAll { $0.id == draft.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.inkTertiary)
                    .help("Leave this one out")
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            HStack(spacing: 8) {
                let count = model.taskDrafts.count
                Button(count == 1 ? "Add task" : "Add \(count) tasks") { model.addTaskDrafts() }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Discard") { model.discardTaskDrafts() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary))
            }
        }
        .padding(10)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Planning

/// One suggestion, with the rule that picked it — never more than one, so it helps
/// you decide instead of adding another list to read.
private struct UpNextCard: View {
    let task: BuddyTask
    let reason: DayPlanner.Reason
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                MonoLabel("Up next · " + TaskLabels.reason(reason), color: Theme.accent)
                Text(task.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { model.focus(on: task.id) } label: { Label("Focus", systemImage: "play.fill") }
                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                .help("Start a focus session on this task")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next: \(task.title). \(TaskLabels.reason(reason)).")
    }
}

/// Unfinished "today only" items from earlier days: the user decides, nothing vanishes silently.
private struct LeftoversBanner: View {
    let count: Int
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("\(count) left over")
                .font(.system(size: 12))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .help("Unfinished “today only” items from an earlier day")
            Spacer(minLength: 4)
            Button("Carry over") { model.carryOverLeftovers() }
                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            Button("Let go") { model.letGoOfLeftovers() }
                .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
