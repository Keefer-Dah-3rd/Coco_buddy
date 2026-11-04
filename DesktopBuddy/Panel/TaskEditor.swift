import SwiftUI
import BuddyCore

/// Inline editor under a task row. Edits save as you make them — there's no
/// separate save step to forget; "Done" just closes the editor.
struct TaskEditor: View {
    let task: BuddyTask
    let model: AppModel
    @State private var draft: BuddyTask
    /// The month calendar under the Due row, opened from the date chip.
    @State private var pickingDate = false
    @FocusState private var titleFocused: Bool
    @FocusState private var notesFocused: Bool

    init(task: BuddyTask, model: AppModel) {
        self.task = task
        self.model = model
        _draft = State(initialValue: task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(SkyType.titleEmphasis.font)
                .foregroundStyle(Sky.ink)
                .focused($titleFocused)
                .onSubmit { model.editingTaskID = nil }
                .skyField(focused: titleFocused)

            TextField("Notes", text: $draft.notes, prompt: Text("Notes — links, details, the first step…")
                .foregroundStyle(Sky.faint), axis: .vertical)
                .textFieldStyle(.plain)
                .font(SkyType.bodySmall.font)
                .foregroundStyle(Sky.ink)
                .lineLimit(2...5)
                .focused($notesFocused)
                .skyField(focused: notesFocused)

            row("Priority") {
                SkySegment(selection: $draft.priority, items: [
                    .init(.none, "–"), .init(.low, "!"), .init(.medium, "!!"), .init(.high, "!!!"), .init(.urgent, "!!!!"),
                ], height: 28)
                .frame(width: 196)
                .help("Priority: none, low, medium, high, urgent — the same marks as quick-add")
                .accessibilityLabel("Priority \(draft.priority.label)")
            }

            VStack(alignment: .leading, spacing: 2) {
                SkyKicker("Estimate")
                SkyTimeSlider(title: "Estimate", minutes: estimateBinding, range: 0...(12 * 60), step: 15,
                              majorEvery: 4, noneLabel: "—")
            }

            row("Due") { deadlineControl }
            if pickingDate, let deadline = draft.deadline {
                DatePicker("Due date", selection: Binding(
                    get: { deadline },
                    set: { picked in
                        draft.deadline = Calendar.current.startOfDay(for: picked)
                        withAnimation(Sky.Motion.quick) { pickingDate = false }
                    }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.graphical)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            row("Keep") {
                SkySegment(selection: scopeBinding, items: [
                    .init(.personal, "My list"), .init(.today, "Today only"),
                ], height: 28)
                .frame(width: 180)
                .help("“My list” keeps a task until it's done. “Today only” is a temporary item for today.")
            }

            row("Under") { parentMenu }

            if task.focusMinutes > 0 {
                receipt
            }

            HStack(spacing: 8) {
                Spacer()
                Button("Remove") { model.removeTask(task.id) }
                    .buttonStyle(SkyButtonStyle(kind: .quiet))
                Button("Done") { model.editingTaskID = nil }
                    .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: draft) { _, new in save(new) }
        .animation(Sky.Motion.quick, value: pickingDate)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var deadlineControl: some View {
        if let deadline = draft.deadline {
            HStack(spacing: 6) {
                // The date as a chip; clicking it opens a month calendar under the row.
                Button { pickingDate.toggle() } label: {
                    Text(deadline.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .skyType(.bodySmall)
                        .foregroundStyle(Sky.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous).fill(Sky.well))
                        .contentShape(RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(pickingDate ? "Close the calendar" : "Pick another day")
                .accessibilityLabel("Due date")
                .accessibilityValue(deadline.formatted(date: .complete, time: .omitted))
                Button {
                    pickingDate = false
                    draft.deadline = nil
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(SkyRoundStyle(size: 22, tint: Sky.ink))
                    .help("No due date")
                    .accessibilityLabel("No due date")
            }
        } else {
            HStack(spacing: 6) {
                quickDue("Today", days: 0)
                quickDue("Tmrw", days: 1)
                quickDue("+1 wk", days: 7)
            }
        }
    }

    /// Moves this task under another one. The task itself and anything already below it aren't
    /// offered, so the list can never loop.
    private var parentMenu: some View {
        let blocked = model.tasks.list.descendantIDs(of: task.id).union([task.id])
        let candidates = model.tasks.outline(collapsed: []).filter { !$0.task.isCompleted && !blocked.contains($0.id) }
        let current = model.tasks.task(model.tasks.task(task.id)?.parentID)
        return Menu {
            Button("Top level") { model.tasks.setParent(nil, for: task.id) }
            if !candidates.isEmpty { Divider() }
            ForEach(candidates.prefix(40)) { row in
                Button(String(repeating: "    ", count: min(row.depth, 3)) + BuddyVoice.short(row.task.title, limit: 40)) {
                    model.tasks.setParent(row.id, for: task.id)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(current.map { BuddyVoice.short($0.title, limit: 22) } ?? "Top level")
                    .skyType(.labelButtonCompact)
                    .foregroundStyle(Sky.ink)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Sky.faint)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(Sky.paper))
            .overlay(Capsule().strokeBorder(Sky.line))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Put this task under another one, or back at the top level")
    }

    private func quickDue(_ title: String, days: Int) -> some View {
        Button(title) {
            let today = Calendar.current.startOfDay(for: .now)
            draft.deadline = Calendar.current.date(byAdding: .day, value: days, to: today)
        }
        .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            SkyKicker(label)
                .fixedSize()
            Spacer(minLength: 0)
            content()
        }
        .frame(minHeight: 26)
    }

    /// Day Club's focus receipt, set out like a till slip: what this task has had so far.
    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your focus receipt")
                .skyType(.receiptDisplay)
                .foregroundStyle(Sky.receiptInk)
            Text("A little structure. Plenty of breathing room.")
                .font(Sky.text(10))
                .foregroundStyle(Sky.receiptInk)
                .padding(.bottom, 6)
            receiptLine("Estimate", draft.estimateMinutes.map(TodayView.duration) ?? "—")
            receiptLine("Focused on this", TodayView.duration(task.focusMinutes))
            HStack(alignment: .lastTextBaseline) {
                Text("Total time, well spent")
                    .font(Sky.text(11))
                    .foregroundStyle(Sky.receiptInk)
                Spacer()
                Text(TodayView.duration(task.focusMinutes))
                    .font(Sky.text(18, .black))
                    .monospacedDigit()
                    .foregroundStyle(Sky.receiptOrange)
            }
            .padding(.top, 8)
            .overlay(alignment: .top) {
                // A clipped path rather than a dashed border: the border drew doubled edges.
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: 10_000, y: 0))
                }
                .stroke(Sky.receiptDash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .clipped()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.receiptCard))
        .accessibilityElement(children: .combine)
    }

    private func receiptLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Sky.text(11))
                .foregroundStyle(Sky.receiptInk)
            Spacer()
            Text(value)
                .font(Sky.text(11, .bold))
                .monospacedDigit()
                .foregroundStyle(Sky.receiptInk)
        }
        .padding(.vertical, 4)
    }

    private var scopeBinding: Binding<TaskScope> {
        Binding(get: { draft.scope }, set: { scope in
            draft.scope = scope
            // A task switched to "today only" belongs to today, not the day it was created.
            draft.plannedDay = scope == .today ? Calendar.current.startOfDay(for: .now) : nil
        })
    }

    /// The estimate in minutes, where 0 means none. The slider moves it in 15-minute steps.
    private var estimateBinding: Binding<Int> {
        Binding(
            get: { draft.estimateMinutes ?? 0 },
            set: { draft.estimateMinutes = $0 <= 0 ? nil : $0 }
        )
    }

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
