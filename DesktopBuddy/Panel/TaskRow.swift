import SwiftUI
import BuddyCore

struct TaskRow: View {
    let task: BuddyTask
    let isInFocus: Bool
    var isSelected = false
    let model: AppModel
    @State private var hovering = false

    private var isEditing: Bool { model.editingTaskID == task.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Button { model.toggleTask(task.id) } label: {
                    CheckSquare(checked: task.isCompleted)
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityLabel(task.isCompleted ? "Mark “\(task.title)” not done" : "Mark “\(task.title)” done")

                if isEditing {
                    // The editor takes the title's place, so nothing appears twice.
                    TaskEditor(task: task, model: model)
                        .transition(.opacity)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                            .font(.system(size: 13))
                            .foregroundStyle(task.isCompleted ? Theme.inkTertiary : Theme.ink)
                            .strikethrough(task.isCompleted, color: Theme.inkTertiary)
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
                            RowIconButton(symbol: "play.fill", help: "Focus on this") { model.focus(on: task.id) }
                        }
                        RowIconButton(symbol: "xmark", help: "Remove") { model.removeTask(task.id) }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, isEditing ? 10 : 8)
        }
        .background(isEditing ? Theme.well : hovering ? Theme.well.opacity(0.7) : .clear)
        .overlay(alignment: .leading) {
            // Keyboard selection: a thin accent bar, like a cursor in the margin.
            if isSelected { Rectangle().fill(Theme.accent).frame(width: 3) }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.snappy(duration: 0.22), value: isEditing)
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        let due = TaskLabels.due(task)
        if !parts.isEmpty || isInFocus || due != nil || task.scope == .today || !task.notes.isEmpty || task.external != nil {
            HStack(spacing: 8) {
                if isInFocus {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.accent).frame(width: 5, height: 5)
                        MonoLabel("In focus", color: Theme.accent)
                    }
                }
                if task.priority != .none, !task.isCompleted {
                    Text(String(repeating: "!", count: task.priority.rawValue))
                        .font(Theme.mono(10, .bold))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("\(task.priority.label) priority")
                }
                if let due, !task.isCompleted {
                    MonoLabel(due.text, color: due.urgent ? Theme.accent : Theme.inkSecondary)
                }
                if task.scope == .today {
                    MonoLabel("Today only", color: Theme.inkTertiary)
                }
                if task.external?.source == .notion {
                    MonoLabel("Notion", color: Theme.inkSecondary)
                        .help("Linked to a Notion page — title and due date come from Notion")
                }
                ForEach(parts, id: \.self) { MonoLabel($0, color: Theme.inkTertiary) }
                if !task.notes.isEmpty {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.inkTertiary)
                        .accessibilityLabel("Has notes")
                }
            }
        }
    }

    private var metaParts: [String] {
        var parts: [String] = []
        if let estimate = task.estimateMinutes { parts.append("Est \(TodayView.duration(estimate))") }
        if task.focusMinutes > 0 { parts.append("Focused \(TodayView.duration(task.focusMinutes))") }
        return parts
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button("Edit…") { model.editingTaskID = task.id }
        if let url = task.external?.url {
            Button("Open in Notion") { NSWorkspace.shared.open(url) }
        }
        Button(task.isCompleted ? "Mark Not Done" : "Mark Done") { model.toggleTask(task.id) }
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
        Divider()
        Button("Remove", role: .destructive) { model.removeTask(task.id) }
    }
}

/// Small shared formatting for task metadata.
enum TaskLabels {
    struct Due {
        var text: String
        var urgent: Bool
    }

    static func due(_ task: BuddyTask, now: Date = .now) -> Due? {
        guard let deadline = task.deadline,
              let days = DayPlanner.daysUntilDeadline(task, now: now) else { return nil }
        switch days {
        case ..<0: return Due(text: "Overdue", urgent: true)
        case 0: return Due(text: "Due today", urgent: true)
        case 1: return Due(text: "Due tomorrow", urgent: false)
        case 2...6: return Due(text: "Due " + deadline.formatted(.dateTime.weekday(.abbreviated)), urgent: false)
        default: return Due(text: "Due " + deadline.formatted(.dateTime.month(.abbreviated).day()), urgent: false)
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

private struct CheckSquare: View {
    let checked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(checked ? Theme.ink : Color.clear)
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .strokeBorder(checked ? Theme.ink : Theme.inkSecondary, lineWidth: 1.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(Theme.paper)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.25, bounce: 0.4), value: checked)
    }
}

struct RowIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Theme.ink : Theme.inkSecondary)
                .frame(width: 22, height: 22)
                .background(hovering ? Theme.hairline : .clear, in: RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
