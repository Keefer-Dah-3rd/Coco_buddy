#if DEBUG
import SwiftUI
import BuddyCore

// EXPERIMENT — the reference's two full-page moments: the orange "Edit Entry" sheet and
// the centered voice review. Same behaviour as the real ones: edits save as you make them,
// and heard tasks are only added on confirm.

/// The task editor as a full orange page sliding up over the panel.
struct EOEditorSheet: View {
    let task: BuddyTask
    let model: AppModel
    @State private var draft: BuddyTask
    @FocusState private var titleFocused: Bool

    init(task: BuddyTask, model: AppModel) {
        self.task = task
        self.model = model
        _draft = State(initialValue: task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                EOKicker("Edit Entry", color: EO.paper.opacity(0.6))
                Spacer()
                Button { close() } label: { Text("✕").font(EO.font(EO.Size.lead, .light)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(EO.paper.opacity(0.6))
                    .help("Close (Esc)")
                    .accessibilityLabel("Close the editor")
            }
            .padding(.bottom, EO.Space.xl)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("Title", text: $draft.title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(EO.font(EO.Size.editorTitle, .medium))
                        .tracking(EO.Tracking.tighter(EO.Size.editorTitle))
                        .foregroundStyle(EO.paper)
                        .lineLimit(1...3)
                        .focused($titleFocused)
                        .onSubmit(close)
                        .padding(.bottom, EO.Space.lg)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(EO.paper.opacity(titleFocused ? 1 : 0.2)).frame(height: 1)
                                .animation(EO.Motion.quick, value: titleFocused)
                        }
                        .eoEntrance(0)

                    TextField("Notes", text: $draft.notes, prompt: Text("Notes — links, details, the first step…")
                        .foregroundStyle(EO.paper.opacity(0.45)), axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(EO.font(16, .light, italic: draft.notes.isEmpty))
                        .foregroundStyle(EO.paper)
                        .lineLimit(1...4)
                        .padding(.top, EO.Space.md)
                        .eoEntrance(1)

                    VStack(alignment: .leading, spacing: EO.Space.lg) {
                        field("Priority") {
                            EOTextTabs(selection: $draft.priority,
                                       options: [(.none, "None"), (.low, "Low"), (.medium, "Medium"), (.high, "High")],
                                       onOrange: true)
                        }
                        .eoEntrance(2)

                        field("Estimate") {
                            HStack(spacing: EO.Space.lg) {
                                stepper("−", help: "15 minutes less") { stepEstimate(-15) }
                                    .disabled(draft.estimateMinutes == nil)
                                estimate
                                stepper("+", help: "15 minutes more") { stepEstimate(15) }
                            }
                        }
                        .eoEntrance(3)

                        field("Due") { dueControl }
                            .eoEntrance(4)

                        field("Keep") {
                            EOTextTabs(selection: scopeBinding, options: [(.personal, "My list"), (.today, "Today only")], onOrange: true)
                        }
                        .eoEntrance(5)
                    }
                    .padding(.top, EO.Space.xl)
                }
            }
            .scrollIndicators(.never)

            VStack(spacing: EO.Space.sm) {
                Button("Save Entry", action: close)
                    .buttonStyle(EOOutlineButtonStyle(onOrange: true))
                    .keyboardShortcut(.return, modifiers: .command)
                HStack {
                    if task.focusMinutes > 0 {
                        EOKicker("Focused \(TodayView.duration(task.focusMinutes)) on this", color: EO.paper.opacity(0.6), size: 9)
                    }
                    Spacer()
                    Button("Remove entry") { model.removeTask(task.id) }
                        .buttonStyle(EOLinkButtonStyle(color: EO.paper.opacity(0.7), arrow: ""))
                }
            }
            .padding(.top, EO.Space.md)
        }
        .padding(EO.Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(EO.orange)
        .environment(\.colorScheme, .dark)  // paper-on-orange text fields and carets
        .onAppear { titleFocused = true }
        .onChange(of: draft) { _, new in save(new) }
    }

    private var estimate: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            if let minutes = draft.estimateMinutes {
                Text(minutes >= 60 ? "\(minutes / 60)" : "\(minutes)")
                    .font(EO.font(EO.Size.headline, .medium))
                    .tracking(EO.Tracking.tighter(EO.Size.headline))
                    .contentTransition(.numericText())
                Text(minutes >= 60 ? (minutes % 60 == 0 ? "h" : "h \(minutes % 60)m") : "m")
                    .font(EO.font(EO.Size.lead, .light))
                    .opacity(0.6)
            } else {
                Text("—").font(EO.font(EO.Size.headline, .light)).opacity(0.6)
            }
        }
        .foregroundStyle(EO.paper)
        .frame(minWidth: 96)
        .animation(EO.Motion.quick, value: draft.estimateMinutes)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(draft.estimateMinutes.map { "Estimate \(TodayView.duration($0))" } ?? "No estimate")
    }

    @ViewBuilder
    private var dueControl: some View {
        let today = Calendar.current.startOfDay(for: .now)
        let choice = Binding<Int?>(
            get: {
                guard let deadline = draft.deadline else { return nil }
                return Calendar.current.dateComponents([.day], from: today, to: deadline).day
            },
            set: { days in
                draft.deadline = days.flatMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            })
        VStack(alignment: .leading, spacing: 10) {
            // A date that isn't one of the presets shows as its own, selected, choice.
            let presets: [(Int?, String)] = [(nil, "None"), (0, "Today"), (1, "Tomorrow"), (7, "+1 week")]
            let custom: [(Int?, String)] = draft.deadline.flatMap { deadline in
                choice.wrappedValue.flatMap { [0, 1, 7].contains($0) ? nil : [($0, deadline.formatted(.dateTime.weekday(.abbreviated).day()))] }
            } ?? []
            EOTextTabs(selection: choice, options: presets + custom, size: 17, onOrange: true, spacing: 14)
            if let deadline = draft.deadline {
                DatePicker("Due date", selection: Binding(get: { deadline },
                                                          set: { draft.deadline = Calendar.current.startOfDay(for: $0) }),
                           displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
            }
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: EO.Space.sm) {
            EOKicker(label, color: EO.paper.opacity(0.6))
            content()
        }
    }

    private func stepper(_ glyph: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(EO.font(EO.Size.title, .light)).frame(minWidth: 24)
        }
        .buttonStyle(EOStepStyle())
        .help(help)
        .accessibilityLabel(help)
    }

    private var scopeBinding: Binding<TaskScope> {
        Binding(get: { draft.scope }, set: { scope in
            draft.scope = scope
            draft.plannedDay = scope == .today ? Calendar.current.startOfDay(for: .now) : nil
        })
    }

    private func stepEstimate(_ minutes: Int) {
        let next = (draft.estimateMinutes ?? 0) + minutes
        draft.estimateMinutes = next <= 0 ? nil : min(next, 12 * 60)
    }

    private func close() { model.editingTaskID = nil }

    /// Same fields, same store call as the real editor.
    private func save(_ edited: BuddyTask) {
        model.tasks.update(task.id) { stored in
            stored.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
            stored.notes = edited.notes
            stored.priority = edited.priority
            stored.estimateMinutes = edited.estimateMinutes
            stored.deadline = edited.deadline
            stored.scope = edited.scope
            stored.plannedDay = edited.plannedDay
        }
    }
}

/// "−" / "+" at 60% that come up to full on hover.
private struct EOStepStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Styled(configuration: configuration)
    }

    private struct Styled: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .foregroundStyle(EO.paper.opacity(!isEnabled ? 0.25 : hovering ? 1 : 0.6))
                .scaleEffect(configuration.isPressed ? 0.85 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(EO.Motion.quick, value: hovering)
        }
    }
}

/// What Coco heard, as the reference's centered review: pulsing "!", a two-line question,
/// numbered editable entries, Confirm / Discard. Nothing is added until Confirm.
struct EOVoiceReviewSheet: View {
    @Bindable var model: AppModel

    var body: some View {
        let count = model.taskDrafts.count
        VStack(spacing: 0) {
            Spacer(minLength: EO.Space.xl)
            Text("!")
                .font(EO.font(EO.Size.title, .light))
                .foregroundStyle(EO.orange)
                .frame(width: 80, height: 80)
                .overlay(Circle().strokeBorder(EO.orange, lineWidth: 1))
                .eoPulse()
                .padding(.bottom, EO.Space.xl)
                .eoEntrance(0)

            Text(count == 1 ? "Heard 1 task.\nAdd it?" : "Heard \(count) tasks.\nAdd them?")
                .font(EO.font(EO.Size.headline, .medium))
                .tracking(EO.Tracking.tight(EO.Size.headline))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .foregroundStyle(EO.ink)
                .padding(.bottom, EO.Space.xl)
                .eoEntrance(1)

            VStack(alignment: .leading, spacing: EO.Space.sm) {
                ForEach($model.taskDrafts) { $draft in
                    let index = model.taskDrafts.firstIndex { $0.id == draft.id } ?? 0
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%02d.", index + 1))
                            .font(EO.font(EO.Size.body, .light))
                            .foregroundStyle(EO.Ink.secondary)
                            .monospacedDigit()
                        TextField("Task", text: $draft.title)
                            .eoField(size: EO.Size.body)
                            .tracking(EO.Tracking.wide(EO.Size.body))
                        if draft.priority != .none {
                            Text(String(repeating: "!", count: draft.priority.rawValue))
                                .font(EO.font(14, .bold)).foregroundStyle(EO.orange)
                        }
                        if let minutes = draft.estimateMinutes {
                            EOKicker(TodayView.duration(minutes), color: EO.Ink.secondary, size: 9)
                        }
                        Button { model.taskDrafts.removeAll { $0.id == draft.id } } label: {
                            Text("✕").font(EO.font(12, .light)).foregroundStyle(EO.Ink.muted)
                        }
                        .buttonStyle(.plain)
                        .help("Leave this one out")
                    }
                    .padding(.bottom, 8)
                    .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
                    .eoEntrance(2 + index)
                }
            }
            .frame(maxWidth: 320)
            .padding(.bottom, EO.Space.xxl)

            HStack(spacing: EO.Space.md) {
                Button(count == 1 ? "Confirm" : "Confirm \(count)") { model.addTaskDrafts() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .accent))
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Discard") { model.discardTaskDrafts() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet))
            }
            .eoEntrance(5)
            Spacer(minLength: EO.Space.xl)
        }
        .padding(.horizontal, EO.Space.page)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                EO.paper
                EODotGrid()
                EOTopRule()
            }
        }
        .animation(EO.Motion.slideUp, value: model.taskDrafts.map(\.id))
    }
}
#endif
