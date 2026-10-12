import SwiftUI
import BuddyCore

/// Today's list: a counter, a one-line quick-add field and the tasks.
struct TodayView: View {
    let model: AppModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    /// Keyboard selection in the list (↑/↓ to move, Space to tick, Return to edit).
    @State private var selectedID: BuddyTask.ID?
    @FocusState private var listFocused: Bool

    var body: some View {
        let _ = model.dayToken  // recompute "today" when the date changes
        let tasks = model.tasks.today()
        let done = tasks.filter(\.isCompleted).count

        VStack(alignment: .leading, spacing: 0) {
            summary(done: done, tasks: tasks)
                .padding(.horizontal, Space.xl)
                .padding(.top, 14)
            quickAdd
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.lg)

            if !model.taskDrafts.isEmpty {
                TaskDraftReviewCard(model: model)
                    .padding(.horizontal, Space.xl)
                    .padding(.bottom, Space.lg)
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
                                    .padding(.horizontal, Space.xl)
                                    .padding(.bottom, Space.sm)
                            }
                            if model.calendar.isConnected {
                                ScheduleStrip(model: model)
                                    .padding(.horizontal, Space.xl)
                                    .padding(.bottom, Space.sm)
                            }
                            if Features.notion, model.notion.isReady, !model.notionCandidates.isEmpty {
                                NotionPickerCard(model: model)
                                    .padding(.horizontal, Space.xl)
                                    .padding(.bottom, Space.sm)
                            }
                            if !leftovers.isEmpty {
                                LeftoversBanner(count: leftovers.count, model: model)
                                    .padding(.horizontal, Space.xl)
                                    .padding(.bottom, Space.sm)
                            }
                            if model.taskDrafts.isEmpty, !model.focus.timer.isActive, let next = model.upNext {
                                UpNextCard(task: next.task, reason: next.reason, model: model)
                                    .padding(.horizontal, Space.xl)
                                    .padding(.bottom, Space.xxs)
                            }
                            ForEach(tasks) { task in
                                TaskRow(
                                    task: task,
                                    isInFocus: model.focus.timer.isActive && model.focus.timer.taskID == task.id,
                                    isSelected: listFocused && selectedID == task.id,
                                    model: model
                                )
                                .id(task.id)
                            }
                        }
                        .padding(.bottom, Space.sm)
                    }
                    .scrollIndicators(.never)
                    .focusable()
                    .focused($listFocused)
                    .focusEffectDisabled()
                    .onKeyPress(keys: [.upArrow, .downArrow, .space, .return, .delete, "f"]) { press in
                        handleListKey(press.key, tasks: tasks, proxy: proxy)
                    }
                    .accessibilityHint("Use the arrow keys to move between tasks, Space to tick, Return to edit")
                    .onAppear { reveal(model.editingTaskID, with: proxy, animated: false) }
                    .onChange(of: model.editingTaskID) { _, id in reveal(id, with: proxy, animated: true) }
                }
            }

            if let removed = model.recentlyRemoved {
                undoBar(removed)
            } else if let problem = model.tasks.storageProblem {
                Text(problem)
                    .font(.style(.caption))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, Space.xl)
                    .padding(.vertical, Space.sm)
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
        return VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(done)")
                    .foregroundStyle(Theme.ink)
                Text("/\(tasks.count)")
                    .foregroundStyle(Theme.inkTertiary)
                MonoLabel("done").padding(.leading, Space.sm)
                Spacer()
            }
            .font(.style(.displayCount).monospacedDigit())
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
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                if voice.isListening {
                    ListeningDot()
                    Text(voice.transcript.isEmpty ? "Listening… say a task or “start focus”" : voice.transcript)
                        .font(.style(.body))
                        .foregroundStyle(voice.transcript.isEmpty ? Theme.inkTertiary : Theme.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("+").font(Theme.mono(15, .semibold)).foregroundStyle(Theme.accent)
                    TextField("Add task", text: $draft, prompt: Text("Add a task… try “Draft intro ~30m !!”")
                        .foregroundStyle(Theme.inkTertiary))
                        .textFieldStyle(.plain)
                        .font(.style(.body))
                        .foregroundStyle(Theme.ink)
                        .focused($fieldFocused)
                        .onSubmit(submit)
                        .onKeyPress(.downArrow) {
                            guard let first = model.tasks.today().first else { return .ignored }
                            selectedID = selectedID ?? first.id
                            listFocused = true
                            return .handled
                        }
                    if !draft.isEmpty {
                        Text("↵").font(.style(.monoValue)).foregroundStyle(Theme.inkTertiary)
                    }
                }
                MicButton(isListening: voice.isListening) { model.toggleListening() }
            }
            .padding(.horizontal, Space.md)
            .frame(height: 34)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(fieldFocused ? Theme.ink.opacity(0.5) : .clear, lineWidth: 1))

            if voice.isListening, !voice.isOnDevice {
                MonoLabel("Transcribed by Apple's speech service")
                    .padding(.leading, Space.xxxs)
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
                HStack(spacing: Space.md) {
                    if let minutes = parsed.estimateMinutes { MonoLabel("Est. \(Self.duration(minutes))") }
                    if parsed.priority != .none { MonoLabel("\(parsed.priority.label) priority", color: Theme.accent) }
                }
                .padding(.leading, Space.xxxs)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: parsed?.estimateMinutes)
        .animation(.easeOut(duration: 0.15), value: parsed?.priority)
    }

    private func undoBar(_ task: BuddyTask) -> some View {
        HStack {
            Text("Removed “\(BuddyVoice.short(task.title, limit: 26))”")
                .font(.style(.bodySmall))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
            Spacer()
            Button("Undo") { model.undoRemove() }
                .buttonStyle(KeyButtonStyle(kind: .secondary))
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.sm)
        .background(Theme.well)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Keyboard control of the list. ↑ from the top goes back to the add field.
    private func handleListKey(_ key: KeyEquivalent, tasks: [BuddyTask], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard model.editingTaskID == nil, !tasks.isEmpty else { return .ignored }
        let index = tasks.firstIndex { $0.id == selectedID } ?? 0
        func select(_ i: Int) {
            selectedID = tasks[i].id
            withAnimation(.snappy(duration: 0.15)) { proxy.scrollTo(tasks[i].id) }
        }
        switch key {
        case .downArrow:
            select(min(tasks.count - 1, index + 1))
        case .upArrow:
            if index == 0 { listFocused = false; fieldFocused = true } else { select(index - 1) }
        case .space:
            model.toggleTask(tasks[index].id)
        case .return:
            model.editingTaskID = tasks[index].id
        case .delete:
            model.removeTask(tasks[index].id)
            let remaining = tasks.filter { $0.id != tasks[index].id }
            selectedID = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
        case "f":
            if !tasks[index].isCompleted { model.focus(on: tasks[index].id) }
        default:
            return .ignored
        }
        return .handled
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
                        RoundedRectangle(cornerRadius: Radius.bar)
                            .fill(index < done ? Theme.ink : Theme.hairline)
                    }
                }
            } else {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Radius.bar).fill(Theme.hairline)
                    RoundedRectangle(cornerRadius: Radius.bar).fill(Theme.ink)
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
        VStack(spacing: Space.lg) {
            Spacer()
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Theme.inkTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 44, height: 30)
                .overlay(Text("+").font(Theme.mono(14, .medium)).foregroundStyle(Theme.inkTertiary))
            VStack(spacing: Space.xxs) {
                Text("Nothing on the list yet.")
                    .font(.style(.bodyEmphasis))
                    .foregroundStyle(Theme.ink)
                Text("Type above and press Return.\nAdd ~25m for an estimate, ! to !!! for priority,\n@today for a one-day item.")
                    .font(.style(.bodySmall))
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
                            in: RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
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
        HStack(alignment: .top, spacing: Space.sm) {
            Text(message)
                .font(.style(.caption))
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
        .padding(.top, Space.xxxs)
    }
}

/// What Coco heard, as editable rows. Nothing is added until "Add".
struct TaskDraftReviewCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack {
                MonoLabel((model.draftOrigin == .chat ? "Suggested by \(Buddy.name)" : "Heard") + " — review before adding",
                          color: Theme.accent)
                Spacer()
            }
            ForEach($model.taskDrafts) { $draft in
                HStack(spacing: Space.sm) {
                    TextField("Task", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(.style(.body))
                        .foregroundStyle(Theme.ink)
                    if draft.priority != .none {
                        Text(String(repeating: "!", count: draft.priority.rawValue))
                            .font(.style(.monoMark))
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
                .padding(.horizontal, Space.sm)
                .frame(height: 28)
                .background(Theme.paper, in: RoundedRectangle(cornerRadius: Radius.key, style: .continuous))
            }
            HStack(spacing: Space.sm) {
                let count = model.taskDrafts.count
                Button(count == 1 ? "Add task" : "Add \(count) tasks") { model.addTaskDrafts() }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Discard") { model.discardTaskDrafts() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary))
            }
        }
        .padding(Space.md)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
        HStack(spacing: Space.md) {
            VStack(alignment: .leading, spacing: 3) {
                MonoLabel("Up next · " + TaskLabels.reason(reason), color: Theme.accent)
                Text(task.title)
                    .font(.style(.bodyEmphasis))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { model.focus(on: task.id) } label: { Label("Focus", systemImage: "play.fill") }
                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                .help("Start a focus session on this task")
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.hairline))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Up next: \(task.title). \(TaskLabels.reason(reason)).")
    }
}

/// Unfinished "today only" items from earlier days: the user decides, nothing vanishes silently.
private struct LeftoversBanner: View {
    let count: Int
    let model: AppModel

    var body: some View {
        HStack(spacing: Space.sm) {
            Text("\(count) left over")
                .font(.style(.bodySmall))
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .help("Unfinished “today only” items from an earlier day")
            Spacer(minLength: 4)
            Button("Carry over") { model.carryOverLeftovers() }
                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            Button("Let go") { model.letGoOfLeftovers() }
                .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, 7)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
