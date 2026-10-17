#if DEBUG
import SwiftUI
import BuddyCore

// EXPERIMENT — Today, as the reference's "Vol. 1 — Tasks" page: display headline, a large
// light counter, then the day as hairline-ruled rows. Same intents as the real Today tab.

struct EOTodayView: View {
    let model: AppModel
    @Binding var expandedEventID: String?
    var openSection: (EOSection) -> Void

    var body: some View {
        let tasks = model.tasks.today()
        let done = tasks.filter(\.isCompleted).count
        let leftovers = model.tasks.leftovers

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(done: done, tasks: tasks)
                        .eoEntrance(0)

                    EOPullQuote(text: model.buddyLine)
                        .padding(.top, 28)
                        .eoEntrance(1)

                    EOScheduleSection(model: model, expandedEventID: $expandedEventID)
                        .padding(.top, 40)
                        .eoEntrance(2)

                    if !leftovers.isEmpty {
                        EOLeftovers(count: leftovers.count, model: model)
                            .padding(.top, EO.Space.lg)
                            .eoEntrance(3)
                    }

                    EOKicker("The List", color: EO.Ink.secondary, size: 11)
                        .padding(.top, EO.Space.xl)
                        .padding(.bottom, 4)
                        .eoEntrance(3)

                    if tasks.isEmpty {
                        EOEmptyList()
                            .eoEntrance(4)
                    } else {
                        // The planner's pick leads the list, set larger, instead of appearing twice.
                        let upNext = !model.focus.timer.isActive && model.taskDrafts.isEmpty ? model.upNext : nil
                        VStack(spacing: 0) {
                            if let upNext {
                                EOUpNextRow(task: upNext.task, reason: upNext.reason, model: model) { openSection(.focus) }
                                    .eoEntrance(4)
                            }
                            ForEach(Array(tasks.filter { $0.id != upNext?.task.id }.enumerated()), id: \.element.id) { index, task in
                                EOTaskRow(task: task, model: model) { openSection(.focus) }
                                    .eoEntrance(5 + index)
                            }
                        }
                        .animation(EO.Motion.slideUp, value: tasks.map(\.id))
                    }
                }
                .padding(.horizontal, EO.Space.page)
                .padding(.top, EO.Space.lg)
                .padding(.bottom, EO.Space.lg)
            }
            .scrollIndicators(.never)

            footer
        }
    }

    // MARK: - Header

    private func header(done: Int, tasks: [BuddyTask]) -> some View {
        let remaining = tasks.filter { !$0.isCompleted }.compactMap(\.estimateMinutes).reduce(0, +)
        let focused = model.focusLog.today.minutes
        return VStack(alignment: .leading, spacing: 0) {
            EOKicker(EOSection.today.kicker)
                .padding(.bottom, EO.Space.sm)
            EODisplay("Today")
            HStack(alignment: .firstTextBaseline, spacing: EO.Space.sm) {
                Text("\(done)")
                    .font(EO.font(EO.Size.numeral, .light))
                    .contentTransition(.numericText())
                Text("/")
                    .font(EO.font(EO.Size.item, .light))
                    .opacity(0.3)
                Text("\(tasks.count)")
                    .font(EO.font(EO.Size.numeral, .light))
                    .opacity(0.3)
                    .contentTransition(.numericText())
                Spacer()
                EOKicker("Completed", color: EO.ink.opacity(0.5), weight: .medium)
            }
            .foregroundStyle(EO.ink)
            .monospacedDigit()
            .animation(EO.Motion.slideUp, value: done)
            .animation(EO.Motion.slideUp, value: tasks.count)
            .padding(.top, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(done) of \(tasks.count) tasks completed")

            if focused > 0 || remaining > 0 {
                HStack {
                    if focused > 0 { EOKicker("Focused \(TodayView.duration(focused)) today", color: EO.ink, size: 10) }
                    Spacer()
                    if remaining > 0 { EOKicker("≈ \(TodayView.duration(remaining)) left", color: EO.Ink.secondary, size: 10) }
                }
                .padding(.top, 10)
            }
            EORule()
                .padding(.top, EO.Space.md)
        }
    }

    // MARK: - Footer: add entry / undo

    @ViewBuilder
    private var footer: some View {
        if let removed = model.recentlyRemoved {
            HStack(spacing: EO.Space.sm) {
                Text("Removed “\(BuddyVoice.short(removed.title, limit: 26))”")
                    .font(EO.font(16, .light, italic: true))
                    .foregroundStyle(EO.Ink.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Undo") { model.undoRemove() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .accent, size: 16))
                    .keyboardShortcut("z", modifiers: .command)
            }
            .padding(.horizontal, EO.Space.page)
            .padding(.vertical, 22)
            .overlay(alignment: .top) { EORule(color: EO.ink).padding(.horizontal, EO.Space.page) }
            .transition(.opacity.combined(with: .offset(y: 10)))
        } else {
            EOAddEntry(model: model)
        }
    }
}

// MARK: - Add entry

/// The reference's "Add entry…" line under a full-ink rule — with the real quick-add
/// shorthand (~30m, !!, @today) read back as you type, and the microphone.
private struct EOAddEntry: View {
    let model: AppModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickAddParser.parse(draft)
        let voice = model.voiceIn
        VStack(alignment: .leading, spacing: 8) {
            EORule(color: EO.ink)
            HStack(spacing: 12) {
                if voice.isListening {
                    Circle().fill(EO.orange).frame(width: 8, height: 8).eoPulse()
                    Text(voice.transcript.isEmpty ? "Listening… say a task or “start focus”" : voice.transcript)
                        .font(EO.font(EO.Size.lead, .light, italic: true))
                        .foregroundStyle(voice.transcript.isEmpty ? EO.Ink.faint : EO.ink)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Add entry", text: $draft, prompt: Text("Add entry…").foregroundStyle(EO.Ink.faint))
                        .eoField(italic: draft.isEmpty)
                        .focused($focused)
                        .onSubmit { if model.addTask(draft) { draft = "" } }
                    if !draft.isEmpty {
                        Text("↵").font(EO.font(14, .light)).foregroundStyle(EO.Ink.faint)
                    }
                }
                Button { model.toggleListening() } label: {
                    Image(systemName: voice.isListening ? "stop.fill" : "mic")
                        .font(.system(size: 11, weight: .regular))
                }
                .buttonStyle(EOCircleButtonStyle(diameter: 30, filled: voice.isListening))
                .keyboardShortcut("l", modifiers: .command)
                .help(voice.isListening ? "Stop listening (⌘L)" : "Talk to \(Buddy.name) (⌘L)")
                .accessibilityLabel(voice.isListening ? "Stop listening" : "Talk to \(Buddy.name)")
            }
            .padding(.top, 8)

            if !voice.isListening, let parsed, parsed.priority != .none || parsed.estimateMinutes != nil {
                HStack(spacing: EO.Space.sm) {
                    if let minutes = parsed.estimateMinutes { EOKicker("Est. \(TodayView.duration(minutes))", color: EO.Ink.secondary, size: 10) }
                    if parsed.priority != .none { EOKicker("\(parsed.priority.label) priority", size: 10) }
                }
                .transition(.opacity)
            } else {
                EOKicker("~30m for time · ! to !!! priority · @today", color: EO.Ink.faint, size: 9, weight: .medium)
            }
            if case .denied(let message) = voice.status { voiceProblem(message) }
            if case .unavailable(let message) = voice.status { voiceProblem(message) }
            if let problem = model.tasks.storageProblem {
                Text(problem).font(EO.font(12)).foregroundStyle(EO.orange)
            }
        }
        .padding(.horizontal, EO.Space.page)
        .padding(.bottom, 20)
        .animation(EO.Motion.quick, value: parsed?.estimateMinutes)
        .animation(EO.Motion.quick, value: parsed?.priority)
        .onAppear { focused = true }
        .onChange(of: model.panelOpenCount) { focused = true }
    }

    private func voiceProblem(_ message: String) -> some View {
        HStack(alignment: .top) {
            Text(message).font(EO.font(12)).foregroundStyle(EO.Ink.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss") { model.voiceIn.clearProblem() }
                .buttonStyle(EOLinkButtonStyle(arrow: ""))
        }
    }
}

// MARK: - Rows

/// "UP NEXT" — the planner's one suggestion, set larger than the rest. The row starts a
/// focus session; the arrow arrives on hover.
private struct EOUpNextRow: View {
    let task: BuddyTask
    let reason: DayPlanner.Reason
    let model: AppModel
    let openFocus: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            model.focus(on: task.id)
            openFocus()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                EOKicker("Up next · " + TaskLabels.reason(reason), size: EO.Size.micro)
                HStack(spacing: EO.Space.sm) {
                    Text(task.title)
                        .font(EO.font(EO.Size.item, .medium, italic: hovering))
                        .tracking(EO.Tracking.tight(EO.Size.item))
                        .foregroundStyle(EO.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        EOKicker("Focus", color: EO.orange, size: 10)
                        Text("→").font(EO.font(EO.Size.lead, .light))
                    }
                    .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.vertical, EO.Space.row)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
        .onHover { hovering = $0 }
        .animation(EO.Motion.hover, value: hovering)
        .help("Start a focus session on this task")
        .accessibilityLabel("Up next: \(task.title). \(TaskLabels.reason(reason)). Starts a focus session.")
    }
}

/// One task: the reference's ring + title row, 60% until hovered. Click the ring to tick,
/// the title to open the orange editor; focus and remove arrive on hover.
private struct EOTaskRow: View {
    let task: BuddyTask
    let model: AppModel
    let openFocus: () -> Void
    @State private var hovering = false

    private var inFocus: Bool { model.focus.timer.isActive && model.focus.timer.taskID == task.id }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: EO.Space.md) {
            Button { model.toggleTask(task.id) } label: { EOCheck(checked: task.isCompleted) }
                .buttonStyle(.plain)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                .accessibilityLabel(task.isCompleted ? "Mark “\(task.title)” not done" : "Mark “\(task.title)” done")

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(EO.font(EO.Size.item, .medium, italic: hovering && !task.isCompleted))
                    .tracking(EO.Tracking.tight(EO.Size.item))
                    .foregroundStyle(EO.ink)
                    .strikethrough(task.isCompleted, color: EO.Ink.muted)
                    .lineLimit(2)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.editingTaskID = task.id }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the editor")

            HStack(spacing: 14) {
                if !task.isCompleted {
                    Button { model.focus(on: task.id); openFocus() } label: { Image(systemName: "play").font(.system(size: 10)) }
                        .buttonStyle(.plain)
                        .help("Focus on this")
                        .accessibilityLabel("Focus on \(task.title)")
                }
                Button { model.removeTask(task.id) } label: { Text("✕").font(EO.font(13, .light)) }
                    .buttonStyle(.plain)
                    .help("Remove")
                    .accessibilityLabel("Remove \(task.title)")
            }
            .foregroundStyle(EO.Ink.secondary)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.vertical, 20)
        .opacity(task.isCompleted ? 0.35 : (hovering || inFocus ? 1 : 0.6))
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
        .overlay(alignment: .leading) {
            if inFocus { Rectangle().fill(EO.orange).frame(width: 2).padding(.vertical, 18).offset(x: -14) }
        }
        .onHover { hovering = $0 }
        .animation(EO.Motion.hover, value: hovering)
        .animation(EO.Motion.slideUp, value: task.isCompleted)
        .contextMenu {
            if !task.isCompleted { Button("Focus on this") { model.focus(on: task.id); openFocus() } }
            Button("Edit") { model.editingTaskID = task.id }
            Button(task.isCompleted ? "Mark not done" : "Mark done") { model.toggleTask(task.id) }
            Divider()
            Button("Remove") { model.removeTask(task.id) }
        }
    }

    @ViewBuilder
    private var meta: some View {
        let due = TaskLabels.due(task)
        let hasMeta = inFocus || (task.priority != .none && !task.isCompleted) || task.estimateMinutes != nil
            || due != nil || task.scope == .today || !task.notes.isEmpty
        if hasMeta {
            HStack(spacing: 12) {
                if inFocus { EOKicker("● In focus", size: 9) }
                if task.priority != .none, !task.isCompleted { EOKicker("\(task.priority.label) priority", size: 9) }
                if let minutes = task.estimateMinutes { EOKicker(TodayView.duration(minutes), color: EO.Ink.secondary, size: 9) }
                if let due, !task.isCompleted { EOKicker(due.text, color: due.urgent ? EO.orange : EO.Ink.secondary, size: 9) }
                if task.scope == .today { EOKicker("Today only", color: EO.Ink.secondary, size: 9) }
                if !task.notes.isEmpty { EOKicker("Notes", color: EO.Ink.muted, size: 9) }
            }
        }
    }
}

/// Unfinished "today only" items from earlier days — the user decides.
private struct EOLeftovers: View {
    let count: Int
    let model: AppModel

    var body: some View {
        HStack(spacing: EO.Space.sm) {
            VStack(alignment: .leading, spacing: 4) {
                EOKicker("Left over", size: 10)
                Text("\(count) unfinished from an earlier day")
                    .font(EO.font(16, .light, italic: true))
                    .foregroundStyle(EO.ink)
            }
            Spacer()
            Button("Carry over") { model.carryOverLeftovers() }
                .buttonStyle(EOUnderlineButtonStyle(kind: .accent, size: 15))
            Button("Let go") { model.letGoOfLeftovers() }
                .buttonStyle(EOUnderlineButtonStyle(kind: .quiet, size: 15))
        }
        .padding(.vertical, EO.Space.sm)
        .overlay(alignment: .top) { EORule(color: EO.Ink.rule) }
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.rule) }
    }
}

private struct EOEmptyList: View {
    var body: some View {
        VStack(alignment: .leading, spacing: EO.Space.sm) {
            EODisplay([.plain("A blank"), .accent("page.")], size: EO.Size.headline)
            Text("Write the first entry below and press Return. Add ~25m for an estimate, ! to !!! for priority, @today for a one-day item.")
                .font(EO.font(16, .light))
                .foregroundStyle(EO.Ink.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, EO.Space.lg)
    }
}
#endif
