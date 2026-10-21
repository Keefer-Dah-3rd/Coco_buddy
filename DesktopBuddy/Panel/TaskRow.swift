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
        HStack(alignment: .top, spacing: 10) {
            Button { model.toggleTask(task.id) } label: {
                SkyCheck(checked: task.isCompleted, size: 18)
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
                        .font(Sky.text(13.5, .medium))
                        .foregroundStyle(task.isCompleted ? Sky.faint : Sky.ink)
                        .strikethrough(task.isCompleted, color: Sky.faint)
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
        .padding(.horizontal, 20)
        .padding(.vertical, isEditing ? 10 : 9)
        .background(isEditing ? Sky.well : hovering ? Sky.well.opacity(0.7) : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Sky.line).frame(height: 1).padding(.horizontal, 20)
        }
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
                        Circle().fill(Sky.accent).frame(width: 5, height: 5)
                        SkyKicker("In focus", color: Sky.accentText)
                    }
                }
                if task.priority != .none, !task.isCompleted {
                    Text(String(repeating: "!", count: task.priority.rawValue))
                        .font(Sky.text(11, .bold))
                        .foregroundStyle(Sky.accentText)
                        .accessibilityLabel("\(task.priority.label) priority")
                }
                if let due, !task.isCompleted {
                    SkyKicker(due.text, color: due.urgent ? Sky.accentText : Sky.muted)
                }
                if task.scope == .today {
                    SkyKicker("Today only", color: Sky.faint)
                }
                if task.external?.source == .notion {
                    SkyKicker("Notion")
                        .help("Linked to a Notion page — title and due date come from Notion")
                }
                ForEach(parts, id: \.self) { SkyKicker($0, color: Sky.faint) }
                if !task.notes.isEmpty {
                    Image(systemName: "text.alignleft")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Sky.faint)
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

struct RowIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(hovering ? Sky.ink : Sky.muted)
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Sky.line : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
