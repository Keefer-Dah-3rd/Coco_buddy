import SwiftUI
import BuddyCore

/// What the new-task form holds before it's saved.
struct NewTaskDraft: Equatable, Identifiable {
    var id = UUID()
    var title = ""
    var notes = ""
    var estimateMinutes: Int?
    var priority: TaskPriority = .none
    /// The task's one date: when it's due (the same date the editor calls "Due").
    var deadline: Date?
    /// Set for a subtask.
    var parentID: BuddyTask.ID?
    var focusNow = false
}

/// The new-task form. One form for top-level tasks and subtasks: it opens over the Today list
/// from the plus button, ⌘N, or a row's "Add subtask".
struct TaskFormView: View {
    let model: AppModel
    @State private var draft: NewTaskDraft
    @State private var customEstimate: Bool
    @State private var pickingDate = false
    @State private var problem: String?
    /// Set while saving, so a double click or Return + ⌘Return can't add the task twice.
    @State private var saving = false
    @FocusState private var titleFocused: Bool

    static let estimatePresets = [5, 15, 30, 45, 60, 120]

    /// `problem` and `pickingDate` let snapshots show those states without clicking.
    init(model: AppModel, draft: NewTaskDraft, problem: String? = nil, pickingDate: Bool = false) {
        self.model = model
        _draft = State(initialValue: draft)
        _problem = State(initialValue: problem)
        _pickingDate = State(initialValue: pickingDate)
        _customEstimate = State(initialValue: draft.estimateMinutes.map { !Self.estimatePresets.contains($0) } ?? false)
    }

    private var canCreate: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleField
                    if let problem {
                        // Under the name, where the fix is, rather than at the bottom of a scrolled form.
                        Text(problem)
                            .font(Sky.text(11.5))
                            .foregroundStyle(Sky.accentText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, -6)
                            .transition(.opacity)
                    }
                    notesField
                    section("Estimate") { estimate }
                    section("Priority") { PriorityPicker(selection: $draft.priority) }
                    section("Due") { dueDate }
                    section("Under") { parentPicker }
                    focusToggle
                }
                .padding(.horizontal, 20)
                .padding(.top, 2)
                .padding(.bottom, 14)
            }
            .scrollIndicators(.never)
            actions
        }
        .background(Sky.paper)
        .animation(Sky.Motion.quick, value: customEstimate)
        .animation(Sky.Motion.quick, value: pickingDate)
        .animation(Sky.Motion.quick, value: problem)
        .onAppear { titleFocused = true }
        .onExitCommand { model.taskForm = nil }
        .onChange(of: draft.title) { problem = nil }
        .onChange(of: draft.parentID) { problem = nil }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            SkyKicker(draft.parentID == nil ? "New task" : "New subtask", color: Sky.accentText, size: 10)
            Spacer()
            Button { model.taskForm = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(SkyRoundStyle(size: 26, tint: Sky.muted))
                .help("Cancel (Esc)")
                .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var titleField: some View {
        TextField("Task name", text: $draft.title, prompt: Text("What needs doing?").foregroundStyle(Sky.faint))
            .textFieldStyle(.plain)
            .font(Sky.text(14, .semibold))
            .foregroundStyle(Sky.ink)
            .focused($titleFocused)
            .onSubmit(create)
            .skyField()
            .overlay(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous)
                .strokeBorder(titleFocused ? Sky.accent.opacity(0.55) : .clear, lineWidth: 1.5))
            .animation(Sky.Motion.quick, value: titleFocused)
            .accessibilityLabel("Task name, required")
    }

    private var notesField: some View {
        TextField("Description", text: $draft.notes,
                  prompt: Text("Description — context, links, the first step").foregroundStyle(Sky.faint),
                  axis: .vertical)
            .textFieldStyle(.plain)
            .font(Sky.text(12.5))
            .foregroundStyle(Sky.ink)
            .lineLimit(2...4)
            .skyField()
            .accessibilityLabel("Description, optional")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            SkyKicker(title, size: 10)
            content()
        }
    }

    @ViewBuilder
    private var estimate: some View {
        FlowLayout(spacing: 6) {
            ForEach(Self.estimatePresets, id: \.self) { minutes in
                let selected = !customEstimate && draft.estimateMinutes == minutes
                Button(TodayView.duration(minutes)) {
                    customEstimate = false
                    draft.estimateMinutes = selected ? nil : minutes
                }
                .buttonStyle(SkyChipStyle(selected: selected))
                .accessibilityLabel(Self.spoken(minutes))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button(customEstimate ? (draft.estimateMinutes.map(TodayView.duration) ?? "Custom") : "Custom…") {
                customEstimate.toggle()
                if customEstimate, draft.estimateMinutes.map(Self.estimatePresets.contains) ?? true {
                    draft.estimateMinutes = 90
                }
            }
            .buttonStyle(SkyChipStyle(selected: customEstimate))
            .help("Any length up to 12 hours, in 15-minute steps")
        }
        if customEstimate {
            SkyTimeSlider(title: "Estimate", minutes: Binding(
                get: { draft.estimateMinutes ?? 0 },
                set: { draft.estimateMinutes = $0 <= 0 ? nil : $0 }
            ), range: 0...(12 * 60), step: 15, majorEvery: 4, noneLabel: "—")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var dueDate: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let isToday = draft.deadline.map { calendar.isDate($0, inSameDayAs: today) } ?? false
        let isTomorrow = draft.deadline.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false
        let isOther = draft.deadline != nil && !isToday && !isTomorrow
        FlowLayout(spacing: 6) {
            dateChip("Today", selected: isToday) { draft.deadline = today; pickingDate = false }
            dateChip("Tomorrow", selected: isTomorrow) { draft.deadline = tomorrow; pickingDate = false }
            dateChip("No date", selected: draft.deadline == nil && !pickingDate) { draft.deadline = nil; pickingDate = false }
            dateChip(isOther ? draft.deadline!.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) : "Pick a date…",
                     selected: isOther || pickingDate) { pickingDate.toggle() }
        }
        if pickingDate {
            DatePicker("Due date", selection: Binding(
                get: { draft.deadline ?? tomorrow },
                set: { picked in
                    draft.deadline = calendar.startOfDay(for: picked)
                    withAnimation(Sky.Motion.quick) { pickingDate = false }
                }
            ), in: today..., displayedComponents: .date)
            .datePickerStyle(.graphical)
            .labelsHidden()
            .tint(Sky.accent)
            .frame(maxWidth: .infinity)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func dateChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(SkyChipStyle(selected: selected))
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Any open task can hold the new one; the list is shown as an outline.
    private var parentPicker: some View {
        let candidates = model.tasks.outline(collapsed: []).filter { !$0.task.isCompleted }
        let current = model.tasks.task(draft.parentID)
        return Menu {
            Button("Top level") { draft.parentID = nil }
            if !candidates.isEmpty { Divider() }
            ForEach(candidates.prefix(40)) { row in
                Button(String(repeating: "    ", count: min(row.depth, 3)) + BuddyVoice.short(row.task.title, limit: 40)) {
                    draft.parentID = row.task.id
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: current == nil ? "list.bullet" : "arrow.turn.down.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(current == nil ? Sky.muted : Sky.accentText)
                Text(current?.title ?? "Top level — not under another task")
                    .font(Sky.text(12.5, .medium))
                    .foregroundStyle(Sky.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Sky.faint)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).fill(Sky.well))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(current.map { "Subtask of \($0.title)" } ?? "Top-level task")
        .help("Put this task under another one")
    }

    private var focusToggle: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Focus on this now")
                    .font(Sky.text(13, .medium))
                    .foregroundStyle(Sky.ink)
                Text(focusCaption)
                    .font(Sky.text(11))
                    .foregroundStyle(Sky.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("Focus on this now", isOn: $draft.focusNow)
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Sky.accent)
                .labelsHidden()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous)
            .fill(draft.focusNow ? Sky.accentPale : Sky.well))
        .contentShape(Rectangle())
        .onTapGesture { draft.focusNow.toggle() }
        .animation(Sky.Motion.quick, value: draft.focusNow)
        .accessibilityElement(children: .combine)
    }

    /// What "Focus on this now" will do — the same as the row's ▶, so a running session is
    /// switched to this task rather than restarted.
    private var focusCaption: String {
        let timer = model.focus.timer
        if timer.isActive, timer.phase == .focus {
            return "Your running session switches to this task."
        }
        let minutes = draft.estimateMinutes.flatMap { FocusSettings.minuteRange.contains($0) ? $0 : nil }
            ?? model.preferences.focusSettings.minutes(for: .focus)
        return "Starts a \(minutes)-minute focus session when you create it."
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button("Cancel") { model.taskForm = nil }
                .buttonStyle(SkyButtonStyle(kind: .quiet))
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button("Create task", action: create)
                .buttonStyle(SkyButtonStyle(kind: .accent))
                .disabled(!canCreate)
                .keyboardShortcut(.return, modifiers: .command)
                .help(canCreate ? "Create task (⌘↩)" : "Give the task a name first")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .overlay(alignment: .top) { Rectangle().fill(Sky.line).frame(height: 1) }
    }

    private func create() {
        guard canCreate else { return }
        saving = true
        switch model.createTask(from: draft) {
        case .created:
            break  // the form closes; the new row highlights in the list
        case .duplicate(let existing):
            problem = "“\(BuddyVoice.short(existing.title, limit: 40))” is already on your list"
                + (draft.parentID == nil ? "." : " under that task.")
            saving = false
        case .invalid(let message):
            problem = message
            saving = false
        }
    }

    private static func spoken(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) minutes" : minutes == 60 ? "1 hour" : "\(minutes / 60) hours"
    }
}

/// Four pills, Low to Urgent. Clicking the chosen one again clears it.
struct PriorityPicker: View {
    @Binding var selection: TaskPriority

    var body: some View {
        HStack(spacing: 6) {
            ForEach([TaskPriority.low, .medium, .high, .urgent], id: \.self) { priority in
                let selected = selection == priority
                Button(priority.label) {
                    withAnimation(Sky.Motion.quick) { selection = selected ? .none : priority }
                }
                .buttonStyle(SkyChipStyle(selected: selected, strong: priority == .urgent))
                .accessibilityLabel("\(priority.label) priority")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .help("Click the chosen priority again to clear it")
    }
}

/// A small pill choice: soft orange when picked (full orange for the strong one, Urgent).
struct SkyChipStyle: ButtonStyle {
    var selected: Bool
    var strong = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Sky.text(11.5, .medium))
            .foregroundStyle(selected ? Sky.ink : Sky.muted)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule().fill(selected ? (strong ? Sky.accent : Sky.accentSoft) : Sky.well))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Sky.Motion.quick, value: selected)
            .animation(Sky.Motion.quick, value: configuration.isPressed)
    }
}

/// Lays chips out in rows, wrapping when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let last = rows[rows.count - 1]
                rows.append(Row(y: last.y + last.height + spacing))
            }
            var row = rows[rows.count - 1]
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
