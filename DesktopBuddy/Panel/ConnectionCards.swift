import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Today's calendar in two lines: the meeting now or next, and the best stretch of free time.
struct ScheduleStrip: View {
    let model: AppModel

    var body: some View {
        let service = model.calendar
        let now = Date.now
        let schedule = service.schedule
        VStack(alignment: .leading, spacing: 6) {
            if let current = schedule.current(at: now) {
                meetingLine(label: "Now", event: current,
                            detail: "until \(current.end.formatted(date: .omitted, time: .shortened))", urgent: true)
            } else if let next = schedule.next(after: now) {
                let minutes = Int(next.start.timeIntervalSince(now) / 60)
                meetingLine(label: "Next", event: next,
                            detail: minutes < 60 ? "in \(minutes)m" : next.start.formatted(date: .omitted, time: .shortened),
                            urgent: minutes <= 10)
            } else {
                HStack(spacing: 8) {
                    MonoLabel("Calendar")
                    Text(schedule.events.isEmpty ? "No meetings today — wide open." : "No more meetings today.")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSecondary)
                }
            }
            if let free = longestFreeBlock(now: now) {
                HStack(spacing: 8) {
                    MonoLabel("Free", color: Theme.ink)
                    Text("\(free.start.formatted(date: .omitted, time: .shortened))–\(free.end.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 12)).foregroundStyle(Theme.ink)
                    MonoLabel(TodayView.duration(Int(free.duration / 60)))
                    Spacer()
                }
                .help("Longest stretch without meetings before 6 pm — good for deep work")
            }
            if service.problem != nil || service.status == .needsReconnect {
                Button { model.openConnections() } label: {
                    MonoLabel(service.status == .needsReconnect ? "Calendar needs reconnecting ›"
                              : "Couldn't refresh" + (service.lastUpdated.map { " · showing \($0.formatted(date: .omitted, time: .shortened))" } ?? ""),
                              color: Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
    }

    private func meetingLine(label: String, event: CalendarEvent, detail: String, urgent: Bool) -> some View {
        HStack(spacing: 8) {
            MonoLabel(label, color: urgent ? Theme.accent : Theme.inkSecondary)
            Text(event.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
            MonoLabel(detail)
            Spacer(minLength: 4)
            if let link = event.meetingLink {
                Button("Join") { NSWorkspace.shared.open(link) }
                    .buttonStyle(KeyButtonStyle(kind: urgent ? .primary : .secondary, compact: true))
                    .help(link.absoluteString)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func longestFreeBlock(now: Date) -> DateInterval? {
        let schedule = model.calendar.schedule
        let start = schedule.current(at: now)?.end ?? now
        return schedule.freeBlocks(from: start, until: DaySchedule.workdayEnd(after: now), minimum: 25 * 60)
            .max { $0.duration < $1.duration }
    }
}

/// "12 open in Notion — pick for today": an inline list, with anything due today or
/// overdue pre-selected. Nothing is added until "Add".
struct NotionPickerCard: View {
    let model: AppModel
    @State private var expanded = false
    @State private var selected: Set<String> = []

    var body: some View {
        let candidates = model.notionCandidates
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if !expanded { selected = Set(candidates.filter(isDueSoon).map(\.id)) }
                expanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    MonoLabel("Notion", color: Theme.ink)
                    Text("\(candidates.count) open in “\(model.notion.mapping?.dataSourceTitle ?? "Notion")”")
                        .font(.system(size: 12)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                    Spacer()
                    MonoLabel(expanded ? "Close" : "Pick ›", color: Theme.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(candidates.prefix(30)) { task in
                    Button {
                        if selected.contains(task.id) { selected.remove(task.id) } else { selected.insert(task.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selected.contains(task.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundStyle(selected.contains(task.id) ? Theme.accent : Theme.inkTertiary)
                            Text(task.title).font(.system(size: 12)).foregroundStyle(Theme.ink).lineLimit(1)
                            Spacer()
                            if let due = task.due {
                                MonoLabel(dueText(due), color: isDueSoon(task) ? Theme.accent : Theme.inkTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                HStack {
                    Button("Refresh") { Task { await model.notion.refreshTasks() } }
                        .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                    Spacer()
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)") {
                        model.addFromNotion(candidates.filter { selected.contains($0.id) })
                        selected = []
                        expanded = false
                    }
                    .buttonStyle(KeyButtonStyle(kind: .primary, compact: true))
                    .disabled(selected.isEmpty)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.hairline))
        .animation(.snappy(duration: 0.2), value: expanded)
    }

    private func isDueSoon(_ task: NotionTask) -> Bool {
        guard let due = task.due else { return false }
        return Calendar.current.startOfDay(for: due) <= Calendar.current.startOfDay(for: .now)
    }

    private func dueText(_ date: Date) -> String {
        let task = BuddyTask(title: "", deadline: date)
        return TaskLabels.due(task)?.text ?? ""
    }
}

/// Asked every time a Notion-linked task is ticked off: change Notion too, or only here?
struct NotionCompletionCard: View {
    let model: AppModel
    let task: BuddyTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Also mark “\(BuddyVoice.short(task.title, limit: 34))” done in Notion?")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Mark done in Notion") { model.confirmNotionCompletion() }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true, compact: true))
                Button("Only here") { model.skipNotionCompletion() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            }
        }
        .padding(10)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
