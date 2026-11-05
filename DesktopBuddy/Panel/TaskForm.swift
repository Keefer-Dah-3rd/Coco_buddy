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
                            .skyType(.bodyWindowCaption)
                            .foregroundStyle(Sky.accentText)
                            .fixedSize(horizontal: false, vertical: true)
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
            Text(draft.parentID == nil ? "New task" : "New subtask")
                .skyType(.kickerRow)
                .foregroundStyle(Sky.accentText)
            Spacer()
            Button { model.taskForm = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(SkyRoundStyle(size: 26, tint: Sky.navy))
            .help("Cancel (Esc)")
            .accessibilityLabel("Cancel")
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var titleField: some View {
        TextField("Task name", text: $draft.title, prompt: Text(""))
            .textFieldStyle(.plain)
            .skyType(.titleEmphasis)
            .foregroundStyle(Sky.ink)
            .background(alignment: .leading) { prompt("What needs doing?", style: .titleEmphasis, showing: draft.title.isEmpty) }
            .frame(minHeight: 22)
            .focused($titleFocused)
            .onSubmit(create)
            // The orange ring shows while it's focused or has a name; an empty, unfocused name is a bare well.
            .skyField(rim: titleFocused || !draft.title.isEmpty ? Sky.accent : nil, focused: true)
            .animation(Sky.Motion.quick, value: titleFocused)
            .accessibilityLabel("Task name, required")
    }

    private var notesField: some View {
        TextField("Description", text: $draft.notes, prompt: Text(""), axis: .vertical)
            .textFieldStyle(.plain)
            .skyType(.bodyWindow)
            .foregroundStyle(Sky.ink)
            .lineLimit(2...4)
            .background(alignment: .topLeading) {
                prompt("Description — context, links, the first step", style: .bodyWindow, showing: draft.notes.isEmpty)
            }
            .skyField(rim: draft.notes.isEmpty ? Sky.accentSoft : Sky.accent)
            .accessibilityLabel("Description, optional")
    }

    /// A field's prompt in faint. Drawn behind the empty field rather than passed as its
    /// `prompt`, which macOS draws in its own placeholder grey whatever the Text's colour.
    private func prompt(_ text: String, style: SkyType, showing: Bool) -> some View {
        Text(text)
            .skyType(style)
            .foregroundStyle(Sky.faint)
            .lineLimit(1)
            .opacity(showing ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .skyType(.kickerRow)
                .foregroundStyle(Sky.muted)
            content()
        }
    }

    @ViewBuilder
    private var estimate: some View {
        FlowLayout(spacing: 6) {
            ForEach(Self.estimatePresets, id: \.self) { minutes in
                let selected = !customEstimate && draft.estimateMinutes == minutes
                Button(DurationText.short(minutes)) {
                    customEstimate = false
                    draft.estimateMinutes = selected ? nil : minutes
                }
                .buttonStyle(SkyChipStyle(selected: selected))
                .accessibilityLabel(DurationText.spoken(minutes))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button(customEstimate ? (draft.estimateMinutes.map(DurationText.short) ?? "Custom") : "Custom…") {
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
        // While the calendar is open only "Pick a date…" is lit; the calendar shows the day.
        FlowLayout(spacing: 6) {
            dateChip("Today", selected: isToday && !pickingDate) { draft.deadline = today; pickingDate = false }
            dateChip("Tomorrow", selected: isTomorrow && !pickingDate) { draft.deadline = tomorrow; pickingDate = false }
            dateChip("No date", selected: draft.deadline == nil && !pickingDate) { draft.deadline = nil; pickingDate = false }
            dateChip(isOther && !pickingDate
                        ? draft.deadline!.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) : "Pick a date…",
                     selected: isOther || pickingDate) { pickingDate.toggle() }
        }
        if pickingDate {
            MonthCalendar(selection: draft.deadline) { picked in
                draft.deadline = calendar.startOfDay(for: picked)
                withAnimation(Sky.Motion.quick) { pickingDate = false }
            }
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
        let current = model.tasks.task(draft.parentID)
        return Menu {
            ParentTaskMenuItems(candidates: model.tasks.parentCandidates()) { draft.parentID = $0 }
        } label: {
            HStack(spacing: 6) {
                Text(current == nil ? "≡" : "↳")
                    .skyType(.titleEmphasis)
                    .foregroundStyle(current == nil ? Sky.muted : Sky.accentText)
                Text(current?.title ?? "Top level — not under another task")
                    .skyType(.bodyWindowEmphasis)
                    .foregroundStyle(Sky.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.down")
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
                    .skyType(.labelButton)
                    .foregroundStyle(Sky.ink)
                Text(focusCaption)
                    .skyType(.bodyCaption)
                    .foregroundStyle(Sky.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Toggle("Focus on this now", isOn: $draft.focusNow)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Sky.confirm)
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
}

/// The choices of a "put this under…" menu: the top level, then every open task as an outline,
/// indented by depth. Shared by the new-task form and the editor.
struct ParentTaskMenuItems: View {
    let candidates: [TaskOutlineRow]
    let choose: (BuddyTask.ID?) -> Void

    @ViewBuilder
    var body: some View {
        Button("Top level") { choose(nil) }
        if !candidates.isEmpty { Divider() }
        ForEach(candidates.prefix(40)) { row in
            Button(String(repeating: "    ", count: min(row.depth, 3)) + BuddyVoice.short(row.task.title, limit: 40)) {
                choose(row.id)
            }
        }
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

/// The "Pick a date…" month: today onwards, earlier days faint and off, today in red, the
/// picked day filled orange. Figma: the Calendar in Task/DatePicker.
private struct MonthCalendar: View {
    let selection: Date?
    let pick: (Date) -> Void
    /// The first day of the month on show.
    @State private var month: Date

    private static let cell = CGSize(width: 32, height: 26)
    /// Seven days and the gaps between them; the card hugs this.
    private static let width = cell.width * 7 + 2 * 6

    init(selection: Date?, pick: @escaping (Date) -> Void) {
        self.selection = selection
        self.pick = pick
        _month = State(initialValue: Calendar.current.dateInterval(of: .month, for: selection ?? .now)?.start ?? .now)
    }

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let canGoBack = month > (calendar.dateInterval(of: .month, for: today)?.start ?? today)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 0) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .skyType(.titleEmphasis)
                    .foregroundStyle(Sky.ink)
                Spacer(minLength: 8)
                monthButton("chevron.left", "Previous month", by: -1, enabled: canGoBack)
                monthButton("chevron.right", "Next month", by: 1, enabled: true)
            }
            .frame(width: Self.width)
            HStack(spacing: 2) {
                ForEach(Array(weekdaySymbols(calendar).enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .skyType(.kicker)
                        .foregroundStyle(Sky.faint)
                        .frame(width: Self.cell.width, height: Self.cell.height)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(weeks(calendar).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 2) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            dayButton(day, calendar: calendar, today: today)
                        } else {
                            Color.clear.frame(width: Self.cell.width, height: Self.cell.height)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).fill(Sky.paper))
        .overlay(RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous).strokeBorder(Sky.line))
        .animation(Sky.Motion.quick, value: month)
    }

    private func dayButton(_ day: Date, calendar: Calendar, today: Date) -> some View {
        let picked = selection.map { calendar.isDate($0, inSameDayAs: day) } ?? false
        let past = day < today
        let isToday = calendar.isDate(day, inSameDayAs: today)
        return Button { pick(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .skyType(.bodySmall)
                .foregroundStyle(picked ? Sky.ink : past ? Sky.faint : isToday ? Sky.accentText : Sky.ink)
                .frame(width: Self.cell.width, height: Self.cell.height)
                .background(Capsule().fill(picked ? Sky.accent : .clear))
        }
        .buttonStyle(CalendarKeyStyle())
        .disabled(past)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    private func monthButton(_ symbol: String, _ label: String, by step: Int, enabled: Bool) -> some View {
        Button {
            if let next = Calendar.current.date(byAdding: .month, value: step, to: month) { month = next }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(enabled ? Sky.muted : Sky.ring)
                .frame(width: 14, height: 20)
        }
        .buttonStyle(CalendarKeyStyle())
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Two-letter weekday names ("Su", "Mo"…), starting on the locale's first weekday.
    private func weekdaySymbols(_ calendar: Calendar) -> [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols.map { String($0.prefix(2)) }
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month as rows of seven, with blanks before the 1st and after the last day.
    private func weeks(_ calendar: Calendar) -> [[Date?]] {
        guard let days = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: lead)
        cells += days.map { calendar.date(byAdding: .day, value: $0 - 1, to: month) }
        cells += Array(repeating: nil, count: (7 - cells.count % 7) % 7)
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }
}

/// A calendar key: no chrome of its own (the label draws it), a small squish when pressed.
private struct CalendarKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Sky.Motion.quick, value: configuration.isPressed)
    }
}

/// A small pill choice on an ink rim: soft orange when picked (full orange for the strong one, Urgent).
struct SkyChipStyle: ButtonStyle {
    var selected: Bool
    var strong = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .skyType(.labelButtonCompact)
            .foregroundStyle(selected ? Sky.ink : Sky.muted)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .frame(height: 28)
            .background(Capsule(style: .circular).fill(selected ? (strong ? Sky.accent : Sky.accentSoft) : Sky.well))
            .overlay(Capsule(style: .circular).strokeBorder(Sky.ink, lineWidth: 1))
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
