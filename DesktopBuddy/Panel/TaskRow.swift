import SwiftUI
import BuddyCore

/// One line of the Today outline. Subtasks sit indented under their parent with a guide line;
/// a parent shows how many of its subtasks are done and folds them away.
struct TaskRow: View {
    let row: TaskOutlineRow
    let isInFocus: Bool
    var isSelected = false
    let model: AppModel
    @State private var hovering = false

    private var task: BuddyTask { row.task }
    private var isEditing: Bool { model.editingTaskID == task.id }
    private var isNew: Bool { model.justAddedTaskID == task.id }
    /// 20 pt per level; past the third level rows stop moving right, so titles keep their room.
    private var indent: CGFloat { CGFloat(min(row.depth, 3)) * 20 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.toggleTask(task.id) } label: {
                // Top-level tasks tick orange; subtasks keep the checkbox's green.
                SkyCheck(checked: task.isCompleted, size: 18, fill: task.parentID == nil ? Sky.accent : Sky.confirm)
            }
            .buttonStyle(.plain)
            .padding(.top, isEditing ? 10 : 1)
            .accessibilityLabel(task.isCompleted ? "Mark “\(task.title)” not done" : "Mark “\(task.title)” done")

            if isEditing {
                // The editor takes the title's place, so nothing appears twice.
                TaskEditor(task: task, model: model)
                    .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .skyType(.titleRow)
                        .foregroundStyle(task.isCompleted ? Sky.faint : Sky.ink)
                        .lineLimit(2)
                    meta
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { model.toggleEditing(task.id) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the editor")
            }

            if hovering && !isEditing {
                HStack(spacing: 2) {
                    if !task.isCompleted {
                        RowIconButton(symbol: "plus", help: "Add subtask", ringed: true) { model.openTaskForm(parent: task.id) }
                        RowIconButton(symbol: "play.fill", help: "Focus on this") { model.focus(on: task.id) }
                    }
                    RowIconButton(symbol: "xmark", help: "Remove") { model.removeTask(task.id) }
                }
                .transition(.opacity)
            }
        }
        .padding(.leading, 20 + indent)
        .padding(.trailing, 20)
        .padding(.vertical, isEditing ? 10 : 9)
        .background(background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sky.line).frame(height: 1).padding(.leading, 20 + indent).padding(.trailing, 20)
        }
        .overlay(alignment: .leading) { guides }
        .overlay(alignment: .leading) {
            // Keyboard selection: a short orange tick at the row's edge.
            if isSelected {
                Capsule().fill(Sky.accent).frame(width: 3).padding(.vertical, 10).padding(.leading, 6)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.snappy(duration: 0.22), value: isEditing)
        .animation(.easeOut(duration: 0.6), value: isNew)
        .contextMenu { contextMenu }
    }

    private var background: Color {
        if isEditing { return Sky.well }
        if isNew { return Sky.accentPale }
        return hovering ? Sky.well : .clear
    }

    /// A thin line down the check column of each parent level, tying subtasks to their parent.
    private var guides: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<min(row.depth, 3), id: \.self) { level in
                Rectangle()
                    .fill(Sky.ring)
                    .frame(width: 1.5)
                    .padding(.leading, 20 + CGFloat(level) * 20 + 8.25)
            }
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        let due = TaskLabels.due(task)
        if !parts.isEmpty || task.estimateMinutes != nil || isInFocus || due != nil || task.scope == .today || !task.notes.isEmpty
            || task.external != nil || row.hasSubtasks || (task.priority != .none && !task.isCompleted) {
            HStack(spacing: 8) {
                if row.hasSubtasks { subtaskToggle }
                if isInFocus {
                    HStack(spacing: 4) {
                        Circle().fill(Sky.accent).frame(width: 5, height: 5)
                        SkyKicker("In focus", tone: .accent)
                    }
                }
                if task.priority != .none, !task.isCompleted { priorityMark }
                if let due, !task.isCompleted {
                    if due.overdue { SkyKicker(due.text, color: Sky.accentText) } else { SkyKicker(due.text, tone: .ink) }
                }
                if task.scope == .today {
                    SkyKicker("Today only", tone: .faint)
                }
                if task.external?.source == .notion {
                    SkyKicker("Notion")
                        .help("Linked to a Notion page — title and due date come from Notion")
                }
                if let estimate = task.estimateMinutes {
                    // Faint while open; ink once the task is done.
                    SkyKicker("Est \(TodayView.duration(estimate))", tone: task.isCompleted ? .ink : .faint)
                }
                ForEach(parts, id: \.self) { SkyKicker($0, tone: .faint) }
                if !task.notes.isEmpty {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Sky.faint)
                        .accessibilityLabel("Has notes")
                }
            }
        }
    }

    /// "2/4" with a chevron: shows or hides the subtasks. Turns orange once they're all done.
    private var subtaskToggle: some View {
        let allDone = row.completedSubtaskCount == row.subtaskCount
        return Button { withAnimation(.snappy(duration: 0.25)) { model.toggleCollapsed(task.id) } } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 7.5, weight: .bold))
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                Text("\(row.completedSubtaskCount)/\(row.subtaskCount)")
                    .skyType(.labelCount)
                    .monospacedDigit()
            }
            .foregroundStyle(allDone ? Sky.accentText : Sky.muted)
            .padding(.horizontal, 6)
            .frame(height: 16)
            .background(Capsule().fill(allDone ? Sky.accentPale : Sky.well))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(row.isExpanded ? "Hide subtasks" : "Show subtasks")
        .accessibilityLabel("\(row.completedSubtaskCount) of \(row.subtaskCount) subtasks done")
        .accessibilityValue(row.isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides the subtasks")
    }

    @ViewBuilder
    private var priorityMark: some View {
        if task.priority == .urgent {
            Text("Urgent")
                .skyType(.kickerStrong)
                .foregroundStyle(Sky.accentText)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Capsule().fill(Sky.accentPale))
                .accessibilityLabel("Urgent priority")
        } else {
            Text(String(repeating: "!", count: task.priority.rawValue))
                .font(Sky.text(11, .bold))
                .foregroundStyle(Sky.accentText)
                .accessibilityLabel("\(task.priority.label) priority")
        }
    }

    private var metaParts: [String] {
        task.focusMinutes > 0 ? ["Focused \(TodayView.duration(task.focusMinutes))"] : []
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Edit…") { model.editingTaskID = task.id }
        if !task.isCompleted {
            Button("Add Subtask…") { model.openTaskForm(parent: task.id) }
        }
        if let url = task.external?.url {
            Button("Open in Notion") { NSWorkspace.shared.open(url) }
        }
        Button(task.isCompleted ? "Mark Not Done" : "Mark Done") { model.toggleTask(task.id) }
        if !task.isCompleted, row.hasSubtasks, row.completedSubtaskCount < row.subtaskCount {
            Button("Mark Done With All Subtasks") { model.tasks.completeWithSubtasks(task.id) }
        }
        if !task.isCompleted {
            Button("Focus on This") { model.focus(on: task.id) }
        }
        Menu("Priority") {
            ForEach(TaskPriority.allCases, id: \.self) { priority in
                Button {
                    model.tasks.setPriority(priority, for: task.id)
                } label: {
                    if priority == task.priority { Label(priority.label, systemImage: "checkmark") } else { Text(priority.label) }
                }
            }
        }
        if task.parentID != nil {
            Button("Move to Top Level") { model.tasks.setParent(nil, for: task.id) }
        }
        Divider()
        Button("Remove", role: .destructive) { model.removeTask(task.id) }
    }
}

/// Small shared formatting for task metadata.
enum TaskLabels {
    struct Due {
        var text: String
        /// Due today or overdue.
        var urgent = false
        /// Past its date: the one due label that keeps the accent colour (Figma shows due dates in ink).
        var overdue = false
    }

    static func due(_ task: BuddyTask, now: Date = .now) -> Due? {
        guard let deadline = task.deadline,
              let days = DayPlanner.daysUntilDeadline(task, now: now) else { return nil }
        switch days {
        case ..<0: return Due(text: "Overdue", urgent: true, overdue: true)
        case 0: return Due(text: "Due today", urgent: true)
        case 1: return Due(text: "Due tomorrow")
        case 2...6: return Due(text: "Due " + deadline.formatted(.dateTime.weekday(.abbreviated)))
        default: return Due(text: "Due " + deadline.formatted(.dateTime.month(.abbreviated).day()))
        }
    }

    static func reason(_ reason: DayPlanner.Reason) -> String {
        switch reason {
        case .overdue: "Overdue"
        case .dueToday: "Due today"
        case .dueTomorrow: "Due tomorrow"
        case .highPriority: "High priority"
        case .quickWin: "Quick win"
        case .nextInLine: "Waiting longest"
        }
    }
}

/// A hovered row's small round action (UI/IconButton, 22 pt). `ringed` is the add-subtask +:
/// 24 pt in a faded ink ring (Task/AddSubtaskAction).
struct RowIconButton: View {
    let symbol: String
    let help: String
    var ringed = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Sky.ink : Sky.muted)
                .frame(width: ringed ? 24 : 22, height: ringed ? 24 : 22)
                .background(Circle().fill(hovering ? Sky.line : .clear))
                .overlay { if ringed { Circle().strokeBorder(Sky.ink, lineWidth: 1) } }
                .opacity(ringed && !hovering ? 0.5 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
