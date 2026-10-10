import SwiftUI
import BuddyCore

struct TaskRow: View {
    let task: BuddyTask
    let isInFocus: Bool
    let model: AppModel
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button { model.toggleTask(task.id) } label: {
                CheckSquare(checked: task.isCompleted)
            }
            .buttonStyle(.plain)
            .padding(.top, 1)
            .accessibilityLabel(task.isCompleted ? "Mark “\(task.title)” not done" : "Mark “\(task.title)” done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(task.isCompleted ? Theme.inkTertiary : Theme.ink)
                    .strikethrough(task.isCompleted, color: Theme.inkTertiary)
                    .lineLimit(2)
                meta
            }

            Spacer(minLength: 4)

            if hovering {
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
        .padding(.vertical, 8)
        .background(hovering ? Theme.well.opacity(0.7) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .contextMenu { contextMenu }
    }

    @ViewBuilder
    private var meta: some View {
        let parts = metaParts
        if !parts.isEmpty || isInFocus {
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
                ForEach(parts, id: \.self) { MonoLabel($0, color: Theme.inkTertiary) }
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

private struct RowIconButton: View {
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
