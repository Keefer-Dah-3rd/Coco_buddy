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
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(Sky.text(14, .semibold))
                .foregroundStyle(Sky.ink)
                .focused($titleFocused)
                .onSubmit { model.editingTaskID = nil }
                .skyField()

            TextField("Notes", text: $draft.notes, prompt: Text("Notes — links, details, the first step…")
                .foregroundStyle(Sky.faint), axis: .vertical)
                .textFieldStyle(.plain)
                .font(Sky.text(12.5))
                .foregroundStyle(Sky.ink)
                .lineLimit(2...5)
                .skyField()

            row("Priority") {
                SkySegment(selection: $draft.priority, items: [
                    .init(.none, "–"), .init(.low, "!"), .init(.medium, "!!"), .init(.high, "!!!"),
                ], height: 28)
                .frame(width: 180)
                .help("Priority: none, low, medium, high — the same marks as quick-add")
                .accessibilityLabel("Priority \(draft.priority.label)")
            }

            VStack(alignment: .leading, spacing: 2) {
                SkyKicker("Estimate")
                SkyTimeSlider(title: "Estimate", minutes: estimateBinding, range: 0...(12 * 60), step: 15,
                              majorEvery: 4, noneLabel: "—")
            }

            row("Due") { deadlineControl }

            row("Keep") {
                SkySegment(selection: scopeBinding, items: [
                    .init(.personal, "My list"), .init(.today, "Today only"),
                ], height: 28)
                .frame(width: 180)
                .help("“My list” keeps a task until it's done. “Today only” is a temporary item for today.")
            }

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
                .font(Sky.text(12))
                Button { draft.deadline = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(SkyRoundStyle(size: 24, tint: Sky.ink))
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

    private func quickDue(_ title: String, days: Int) -> some View {
        Button(title) {
            let today = Calendar.current.startOfDay(for: .now)
            draft.deadline = Calendar.current.date(byAdding: .day, value: days, to: today)
        }
        .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
    }

    private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            SkyKicker(label)
            Spacer()
            content()
        }
        .frame(minHeight: 26)
    }

    /// Day Club's focus receipt, set out like a till slip: what this task has had so far.
    private var receipt: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your focus receipt")
                .font(Receipt.display(15))
                .tracking(-0.3)
                .foregroundStyle(Receipt.brown)
            Text("A little structure. Plenty of breathing room.")
                .font(Sky.text(10))
                .foregroundStyle(Receipt.muted)
                .padding(.top, 2)
                .padding(.bottom, 6)
            receiptLine("Estimate", draft.estimateMinutes.map(TodayView.duration) ?? "—")
            receiptLine("Focused on this", TodayView.duration(task.focusMinutes))
            HStack(alignment: .lastTextBaseline) {
                Text("Total time, well spent")
                    .font(Sky.text(11))
                    .foregroundStyle(Receipt.brown)
                Spacer()
                Text(TodayView.duration(task.focusMinutes))
                    .font(Receipt.display(18))
                    .monospacedDigit()
                    .foregroundStyle(Receipt.orange)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) {
                // A clipped path rather than a dashed border: the border drew doubled edges.
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: 10_000, y: 0))
                }
                .stroke(Receipt.dash, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(height: 1)
                .clipped()
            }
            .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Receipt.card))
        .accessibilityElement(children: .combine)
    }

    private func receiptLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(Sky.text(11))
                .foregroundStyle(Receipt.brown)
            Spacer()
            Text(value)
                .font(Sky.text(11, .bold))
                .monospacedDigit()
                .foregroundStyle(Receipt.brown)
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

/// The receipt's colours, from Coco Day Club's style (its headings use Titan One, which the
/// app doesn't bundle, so a heavy rounded face stands in).
private enum Receipt {
    static let card = Color(hex: 0xF7F6F0)
    static let brown = Color(hex: 0x38120C)
    static let muted = Color(hex: 0x87756D)
    static let orange = Color(hex: 0xEF833A)
    static let dash = Color(hex: 0xBCAFA0)

    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .rounded)
    }
}
