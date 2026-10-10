import SwiftUI
import BuddyCore

/// Inline editor under a task row. Edits save as you make them — there's no
/// separate save step to forget; "Done" just closes the editor.
struct TaskEditor: View {
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
        VStack(alignment: .leading, spacing: 10) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .focused($titleFocused)
                .onSubmit { model.editingTaskID = nil }
                .fieldWell()

            TextField("Notes", text: $draft.notes, prompt: Text("Notes — links, details, the first step…")
                .foregroundStyle(Theme.inkTertiary), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink)
                .lineLimit(2...5)
                .fieldWell()

            row("Priority") {
                KeySegment(selection: $draft.priority, items: [
                    .init(.none, "–"), .init(.low, "!"), .init(.medium, "!!"), .init(.high, "!!!"),
                ], height: 22)
                .frame(width: 186)
                .help("Priority: none, low, medium, high — the same marks as quick-add")
                .accessibilityLabel("Priority \(draft.priority.label)")
            }

            row("Estimate") {
                HStack(spacing: 6) {
                    StepButton(symbol: "minus", help: "15 minutes less") { stepEstimate(-15) }
                        .disabled(draft.estimateMinutes == nil)
                    Text(draft.estimateMinutes.map(TodayView.duration) ?? "—")
                        .font(Theme.mono(11, .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(minWidth: 52)
                    StepButton(symbol: "plus", help: "15 minutes more") { stepEstimate(15) }
                }
            }

            row("Due") { deadlineControl }

            row("Keep") {
                KeySegment(selection: scopeBinding, items: [
                    .init(.personal, "My list"), .init(.today, "Today only"),
                ], height: 22)
                .frame(width: 186)
                .help("“My list” keeps a task until it's done. “Today only” is a temporary item for today.")
            }

            HStack {
                if task.focusMinutes > 0 {
                    MonoLabel("Focused \(TodayView.duration(task.focusMinutes)) on this", color: Theme.inkTertiary)
                }
                Spacer()
                Button("Remove") { model.removeTask(task.id) }
                    .buttonStyle(KeyButtonStyle(kind: .quiet))
                Button("Done") { model.editingTaskID = nil }
                    .buttonStyle(KeyButtonStyle(kind: .secondary))
            }
        }
        .onAppear { titleFocused = true }
        .onChange(of: draft) { _, new in save(new) }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var deadlineControl: some View {
        if let deadline = draft.deadline {
            HStack(spacing: 6) {
                DatePicker("Due date", selection: Binding(
                    get: { deadline },
                    set: { draft.deadline = Calendar.current.startOfDay(for: $0) }
                ), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.field)
                .font(.system(size: 12))
                StepButton(symbol: "xmark", help: "No due date") { draft.deadline = nil }
            }
        } else {
            HStack(spacing: 4) {
                quickDue("Today", days: 0)
                quickDue("Tmrw", days: 1)
                quickDue("+1 wk", days: 7)
            }
        }
    }

    private func quickDue(_ title: String, days: Int) -> some View {
        Button(title) {
            let today = Calendar.current.startOfDay(for: .now)
            draft.deadline = Calendar.current.date(byAdding: .day, value: days, to: today)
        }
        .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            MonoLabel(label)
            Spacer()
            content()
        }
        .frame(minHeight: 26)
    }

    private var scopeBinding: Binding<TaskScope> {
        Binding(get: { draft.scope }, set: { scope in
            draft.scope = scope
            // A task switched to "today only" belongs to today, not the day it was created.
            draft.plannedDay = scope == .today ? Calendar.current.startOfDay(for: .now) : nil
        })
    }

    private func stepEstimate(_ minutes: Int) {
        let current = draft.estimateMinutes ?? 0
        let next = current + minutes
        draft.estimateMinutes = next <= 0 ? nil : min(next, 12 * 60)
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

private struct StepButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 24, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private extension View {
    func fieldWell() -> some View {
        padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.hairline))
    }
}
