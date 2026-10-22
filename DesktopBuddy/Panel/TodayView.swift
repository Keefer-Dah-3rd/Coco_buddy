import SwiftUI
import BuddyCore

/// Today. The day's wins and the one-line add field stay at the top; below them scroll Coco's
/// focus banner, the quick actions, the calendar and the tasks.
struct TodayView: View {
    let model: AppModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool
    /// Keyboard selection in the list (↑/↓ to move, Space to tick, Return to edit).
    @State private var selectedID: BuddyTask.ID?
    @FocusState private var listFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let _ = model.dayToken  // recompute "today" when the date changes
        let tasks = model.tasks.today()
        let rows = model.tasks.outline(collapsed: model.collapsedTaskIDs)
        let done = tasks.filter(\.isCompleted).count
        let leftovers = model.tasks.leftovers
        let hasConnections = model.agenda.isConnected || (Features.notion && model.notion.isReady)
        let nothingYet = tasks.isEmpty && leftovers.isEmpty && !hasConnections

        VStack(alignment: .leading, spacing: 0) {
            summary(done: done, tasks: tasks)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            quickAdd
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !model.taskDrafts.isEmpty {
                            TaskDraftReviewCard(model: model)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 10)
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .id("drafts")
                        }
                        SkyFocusBanner(model: model)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                        if let pending = model.pendingNotionCompletion {
                            NotionCompletionCard(model: model, task: pending)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                        if model.agenda.isConnected {
                            ScheduleStrip(model: model)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                        if Features.notion, model.notion.isReady, !model.notionCandidates.isEmpty {
                            NotionPickerCard(model: model)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                        if !leftovers.isEmpty {
                            LeftoversBanner(count: leftovers.count, model: model)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 8)
                        }
                        if model.taskDrafts.isEmpty, !model.focus.timer.isActive, let next = model.upNext {
                            UpNextCard(task: next.task, reason: next.reason, model: model)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 6)
                        }
                        if nothingYet {
                            EmptyTodayView { model.openTaskForm() }
                        } else {
                            ForEach(rows) { row in
                                TaskRow(
                                    row: row,
                                    isInFocus: model.focus.timer.isActive && model.focus.timer.taskID == row.id,
                                    isSelected: listFocused && selectedID == row.id,
                                    model: model
                                )
                                .id(row.id)
                                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                            }
                        }
                        SkyHelpRows(model: model, makePlan: { fieldFocused = true }, openChat: { model.panelTab = .chat })
                            .padding(.horizontal, 20)
                            .padding(.bottom, 10)
                    }
                    .padding(.bottom, 8)
                    .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: rows.map(\.id))
                }
                .scrollIndicators(.never)
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return, .delete, "f", "n"]) { press in
                    handleListKey(press.key, rows: rows, proxy: proxy)
                }
                .accessibilityHint("Use the arrow keys to move between tasks, Space to tick, Return to edit, N to add a subtask, left and right to fold subtasks")
                .onAppear { reveal(model.editingTaskID, with: proxy, animated: false) }
                .onChange(of: model.editingTaskID) { _, id in reveal(id, with: proxy, animated: true) }
                .onChange(of: model.taskDrafts.count) { old, new in
                    if new > old { withAnimation(.snappy) { proxy.scrollTo("drafts", anchor: .top) } }
                }
            }

            if let removed = model.recentlyRemoved {
                undoBar(removed)
            } else if let problem = model.tasks.storageProblem {
                Text(problem)
                    .font(Sky.text(11))
                    .foregroundStyle(Sky.accentText)
                    .padding(.horizontal, 20)
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
            SkyWinsCard(done: done, total: tasks.count)
            if focused.minutes > 0 || remainingMinutes > 0 {
                HStack {
                    if focused.minutes > 0 {
                        SkyKicker("Focused \(Self.duration(focused.minutes)) today", color: Sky.ink)
                    }
                    Spacer()
                    if remainingMinutes > 0 {
                        SkyKicker("≈ \(Self.duration(remainingMinutes)) left")
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
                        .font(Sky.text(13))
                        .foregroundStyle(voice.transcript.isEmpty ? Sky.faint : Sky.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Opens the full form: name, description, estimate, priority, date, parent, focus.
                    // Anything already typed here comes along.
                    Button {
                        model.openTaskForm(typed: draft)
                        draft = ""
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(SkyRoundStyle(size: 26, fill: Sky.accentPale, tint: Sky.accentText))
                    .keyboardShortcut("n", modifiers: .command)
                    .help("New task with details (⌘N)")
                    .accessibilityLabel("New task")
                    TextField("Add task", text: $draft, prompt: Text("Add a task… try “Draft intro ~30m !!”")
                        .foregroundStyle(Sky.faint))
                        .textFieldStyle(.plain)
                        .font(Sky.text(13))
                        .foregroundStyle(Sky.ink)
                        .focused($fieldFocused)
                        .onSubmit(submit)
                        .onKeyPress(.downArrow) {
                            guard let first = model.tasks.today().first else { return .ignored }
                            selectedID = selectedID ?? first.id
                            listFocused = true
                            return .handled
                        }
                    if !draft.isEmpty {
                        Text("↵")
                            .font(Sky.text(11, .medium))
                            .foregroundStyle(Sky.faint)
                    }
                }
                MicButton(isListening: voice.isListening) { model.toggleListening() }
            }
            .padding(.leading, 12)
            .padding(.trailing, 5)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).fill(Sky.well))
            .overlay(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous)
                .strokeBorder(fieldFocused ? Sky.accent.opacity(0.55) : .clear, lineWidth: 1.5))

            if voice.isListening, !voice.isOnDevice {
                SkyKicker("Transcribed by Apple's speech service")
                    .padding(.leading, 4)
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
                HStack(spacing: 12) {
                    if let minutes = parsed.estimateMinutes { SkyKicker("Est. \(Self.duration(minutes))") }
                    if parsed.priority != .none { SkyKicker("\(parsed.priority.label) priority", color: Sky.accentText) }
                }
                .padding(.leading, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: parsed?.estimateMinutes)
        .animation(.easeOut(duration: 0.15), value: parsed?.priority)
    }

    private func undoBar(_ task: BuddyTask) -> some View {
        HStack {
            Text("Removed “\(BuddyVoice.short(task.title, limit: 26))”")
                .font(Sky.text(12))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer()
            Button("Undo") { model.undoRemove() }
                .buttonStyle(.plain)
                .font(Sky.text(12, .medium))
                .foregroundStyle(Sky.accentSoft)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Sky.ink))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// Keyboard control of the list. ↑ from the top goes back to the add field; → and ← unfold and
    /// fold a parent's subtasks (← on a subtask goes to its parent); N adds a subtask.
    private func handleListKey(_ key: KeyEquivalent, rows: [TaskOutlineRow], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard model.editingTaskID == nil, model.taskForm == nil, !rows.isEmpty else { return .ignored }
        let tasks = rows.map(\.task)
        let index = tasks.firstIndex { $0.id == selectedID } ?? 0
        let row = rows[index]
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
        case "n":
            if !row.task.isCompleted { model.openTaskForm(parent: row.id) }
        case .rightArrow:
            guard row.hasSubtasks, !row.isExpanded else { return .ignored }
            withAnimation(.snappy(duration: 0.25)) { model.toggleCollapsed(row.id) }
        case .leftArrow:
            if row.hasSubtasks, row.isExpanded {
                withAnimation(.snappy(duration: 0.25)) { model.toggleCollapsed(row.id) }
            } else if let parent = row.task.parentID, let i = tasks.firstIndex(where: { $0.id == parent }) {
                select(i)
            } else {
                return .ignored
            }
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

private struct EmptyTodayView: View {
    let newTask: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: newTask) {
                RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous)
                    .strokeBorder(Sky.ring, style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .frame(width: 46, height: 32)
                    .overlay(Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).foregroundStyle(Sky.muted))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New task with details (⌘N)")
            .accessibilityLabel("New task")
            VStack(spacing: 4) {
                Text("Nothing on the list yet.")
                    .font(Sky.text(14, .semibold))
                    .foregroundStyle(Sky.ink)
                Text("Type above and press Return, or click + for\nthe full form. Add ~25m for an estimate,\n! to !!!! for priority, @today for a one-day item.")
                    .font(Sky.text(12))
                    .foregroundStyle(Sky.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 20)
    }
}

// MARK: - Voice

private struct MicButton: View {
    let isListening: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.system(size: isListening ? 9 : 11, weight: .semibold))
                .foregroundStyle(isListening ? Sky.ink : Sky.muted)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isListening ? Sky.accent : Sky.paper))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
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
            .fill(Sky.accent)
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
                .font(Sky.text(11))
                .foregroundStyle(Sky.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Settings") { NSWorkspace.shared.open(settingsURL) }
                .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(SkyRoundStyle(size: 22, fill: .clear, tint: Sky.faint))
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
            SkyKicker((model.draftOrigin == .chat ? "Suggested by \(Buddy.name)" : "Heard") + " — review before adding",
                      color: Sky.accentText)
            ForEach($model.taskDrafts) { $draft in
                HStack(spacing: 8) {
                    TextField("Task", text: $draft.title)
                        .textFieldStyle(.plain)
                        .font(Sky.text(13, .medium))
                        .foregroundStyle(Sky.ink)
                    if draft.priority != .none {
                        Text(String(repeating: "!", count: draft.priority.rawValue))
                            .font(Sky.text(11, .bold))
                            .foregroundStyle(Sky.accentText)
                    }
                    if let minutes = draft.estimateMinutes {
                        SkyKicker(TodayView.duration(minutes), color: Sky.faint)
                    }
                    Button {
                        model.taskDrafts.removeAll { $0.id == draft.id }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                    }
                    .buttonStyle(SkyRoundStyle(size: 22, fill: .clear, tint: Sky.faint))
                    .help("Leave this one out")
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous).fill(Sky.paper))
            }
            HStack(spacing: 8) {
                let count = model.taskDrafts.count
                Button(count == 1 ? "Add task" : "Add \(count) tasks") { model.addTaskDrafts() }
                    .buttonStyle(SkyButtonStyle(kind: .accent, compact: true, fillWidth: true))
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Discard") { model.discardTaskDrafts() }
                    .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.well))
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
                SkyKicker("Up next · " + (reason == .highPriority && task.priority == .urgent ? "Urgent" : TaskLabels.reason(reason)),
                          color: Sky.accentText)
                Text(task.title)
                    .font(Sky.text(13.5, .semibold))
                    .foregroundStyle(Sky.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button { model.focus(on: task.id) } label: { Label("Focus", systemImage: "play.fill") }
                .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                .help("Start a focus session on this task")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .skyCard(radius: Sky.Radius.card)
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
                .font(Sky.text(12))
                .foregroundStyle(Sky.muted)
                .lineLimit(1)
                .help("Unfinished “today only” items from an earlier day")
            Spacer(minLength: 4)
            Button("Carry over") { model.carryOverLeftovers() }
                .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            Button("Let go") { model.letGoOfLeftovers() }
                .buttonStyle(SkyButtonStyle(kind: .quiet, compact: true))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.well))
    }
}
