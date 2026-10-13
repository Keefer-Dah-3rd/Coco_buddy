import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Today's calendar in two lines: the meeting now or next, and the best stretch of free time.
struct ScheduleStrip: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .trailing, spacing: Space.xs) {
            // Outside the card, so it reads as its own control: opens and closes the week.
            Button {
                if !model.scheduleExpanded { model.showScheduleDay(model.scheduleDay) }
                model.scheduleExpanded.toggle()
            } label: {
                HStack(spacing: 3) {
                    Text("Week")
                    Image(systemName: model.scheduleExpanded ? "chevron.up" : "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            .help(model.scheduleExpanded ? "Show just today" : "Browse the week")
            .accessibilityLabel(model.scheduleExpanded ? "Collapse week" : "Show the week")
            Group {
                if model.scheduleExpanded {
                    WeekScheduleView(model: model)
                } else {
                    today.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    /// Every event today, stacked in order — the one happening now marked, finished ones dimmed.
    private var today: some View {
        let service = model.calendar
        let now = Date.now
        let schedule = service.schedule
        let day = Availability.dayInterval(now, calendar: .current)
        let _ = model.dayToken
        return VStack(alignment: .leading, spacing: Space.xs) {
            MonoLabel("Today")
            if schedule.events.isEmpty && schedule.allDayEvents.isEmpty {
                Text("No meetings today — wide open.")
                    .font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary)
            }
            ForEach(schedule.allDayEvents) { event in
                HStack(spacing: Space.sm) {
                    MonoLabel("All day")
                    Text(event.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
                }
            }
            ForEach(schedule.events) { event in
                EventRow(event: event, day: day, now: now)
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
    }

    private func meetingLine(label: String, event: CalendarEvent, detail: String, urgent: Bool) -> some View {
        HStack(spacing: Space.sm) {
            MonoLabel(label, color: urgent ? Theme.accent : Theme.inkSecondary)
            Text(event.title)
                .font(.style(.bodyEmphasis))
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
        return schedule.freeBlocks(from: start, until: DaySchedule.workdayEnd(after: now, hour: model.preferences.workdayEndHour), minimum: 25 * 60)
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
        VStack(alignment: .leading, spacing: Space.sm) {
            Button {
                if !expanded { selected = Set(candidates.filter(isDueSoon).map(\.id)) }
                expanded.toggle()
            } label: {
                HStack(spacing: Space.sm) {
                    MonoLabel("Notion", color: Theme.ink)
                    Text("\(candidates.count) open in “\(model.notion.mapping?.dataSourceTitle ?? "Notion")”")
                        .font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
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
                        HStack(spacing: Space.sm) {
                            Image(systemName: selected.contains(task.id) ? "checkmark.square.fill" : "square")
                                .font(.system(size: 12))
                                .foregroundStyle(selected.contains(task.id) ? Theme.accent : Theme.inkTertiary)
                            Text(task.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
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
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.hairline))
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
        VStack(alignment: .leading, spacing: Space.sm) {
            Text("Also mark “\(BuddyVoice.short(task.title, limit: 34))” done in Notion?")
                .font(.style(.bodySmallEmphasis))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.sm) {
                Button("Mark done in Notion") { model.confirmNotionCompletion() }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true, compact: true))
                Button("Only here") { model.skipNotionCompletion() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            }
        }
        .padding(Space.md)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}
