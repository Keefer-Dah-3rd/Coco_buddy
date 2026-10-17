import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Today's calendar, from every connected calendar with duplicates merged: what's on now,
/// what's next and how soon, the rest of the day with the open time between, then the next
/// few days. Opens out into the week browser.
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
                    // Once a minute, so "in 15m" and "20m left" stay true while the panel is open.
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        today(now: context.date).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.horizontal, Space.md)
            .padding(.vertical, Space.sm)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Theme.hairline))
        }
    }

    private enum Item: Identifiable {
        case event(CalendarEvent)
        case open(DateInterval)
        var id: String {
            switch self {
            case .event(let event): event.id
            case .open(let interval): "open-\(interval.start.timeIntervalSince1970)"
            }
        }
        var start: Date {
            switch self {
            case .event(let event): event.start
            case .open(let interval): interval.start
            }
        }
    }

    /// Every event today in order — the one happening now marked, finished ones dimmed — with
    /// open stretches of half an hour or more between the ones still to come.
    private func today(now: Date) -> some View {
        let agenda = model.agenda
        let calendar = Calendar.current
        let _ = model.dayToken
        // Nil until a connected calendar has today: not the same as an empty day.
        let loaded = agenda.events(on: now)
        let events = loaded ?? []
        let schedule = DaySchedule(events: events)
        let day = Availability.dayInterval(now, calendar: calendar)
        let remaining = schedule.events.filter { $0.end > now }
        let next = schedule.next(after: now)
        let open = remaining.isEmpty ? [] : Availability.openings(on: now, events: events, hours: model.workingHours,
                                                                  minimum: 30 * 60, notBefore: now, calendar: calendar)
        let items = (schedule.events.map(Item.event) + open.map(Item.open)).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        return VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                MonoLabel("Today")
                Spacer(minLength: Space.xs)
                if !schedule.events.isEmpty {
                    MonoLabel(remaining.isEmpty ? "done" : "\(remaining.count) left"
                              + (open.isEmpty ? "" : " · \(TodayView.duration(Int(open.reduce(0) { $0 + $1.duration } / 60))) open"))
                }
            }
            if loaded == nil {
                // A failure with nothing saved is explained by the problem line below.
                if agenda.problem(for: now) == nil {
                    HStack(spacing: Space.sm) {
                        ProgressView().controlSize(.small)
                        MonoLabel("Loading today…")
                    }
                    .padding(.vertical, Space.xxs)
                    .accessibilityElement(children: .combine)
                }
            } else if schedule.events.isEmpty && schedule.allDayEvents.isEmpty {
                Text("No meetings today — wide open.")
                    .font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary)
            }
            ForEach(schedule.allDayEvents) { event in
                HStack(spacing: Space.sm) {
                    MonoLabel("All day")
                    Text(event.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
                }
                .help(event.sourcesDescription)
            }
            ForEach(items) { item in
                switch item {
                case .event(let event): EventRow(event: event, day: day, now: now, note: note(for: event, next: next, now: now))
                case .open(let interval): OpenRow(interval: interval)
                }
            }
            if !schedule.events.isEmpty && remaining.isEmpty {
                Text("That's all for today — no more meetings.")
                    .font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary)
            }
            problemLine(now: now)
            comingUp(now: now)
        }
    }

    /// The meeting happening now: how long is left. The next one: how soon.
    private func note(for event: CalendarEvent, next: CalendarEvent?, now: Date) -> (text: String, urgent: Bool)? {
        if event.start <= now && now < event.end { return (RelativeTiming.remaining(until: event.end, now: now), false) }
        guard event.id == next?.id else { return nil }
        return (RelativeTiming.untilStart(of: event.start, now: now), event.start.timeIntervalSince(now) <= 15 * 60)
    }

    @ViewBuilder
    private func problemLine(now: Date) -> some View {
        let failing = model.agenda.activeSources.filter { $0.problem(for: now) != nil }.map(\.sourceName)
        if model.calendar.status == .needsReconnect || !failing.isEmpty {
            Button { model.openConnections() } label: {
                MonoLabel(model.calendar.status == .needsReconnect ? "Google Calendar needs reconnecting ›"
                          : "Couldn't refresh \(failing.joined(separator: " or ")) · showing what's saved ›",
                          color: Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    /// The next few events after today, with when they are: "Tomorrow", "Thu", "Oct 24".
    @ViewBuilder
    private func comingUp(now: Date) -> some View {
        let agenda = model.agenda
        let upcoming = agenda.comingUp(after: now, limit: 3)
        let weekAhead = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        Rectangle().fill(Theme.hairline).frame(height: 1).padding(.vertical, Space.xxs)
        MonoLabel("Coming up")
        if upcoming.isEmpty {
            // Only "nothing" once the week ahead has actually been read.
            Text(agenda.events(on: weekAhead) == nil
                 ? (agenda.problem(for: weekAhead) == nil ? "Loading…" : "Couldn't read the next 7 days.")
                 : "Nothing in the next 7 days.")
                .font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary)
        }
        ForEach(upcoming) { event in
            HStack(spacing: Space.sm) {
                MonoLabel(RelativeTiming.day(of: event.start, now: now))
                    .frame(width: 66, alignment: .leading)
                Text(event.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer(minLength: Space.xs)
                Text(event.isAllDay ? "all day" : event.start.formatted(date: .omitted, time: .shortened))
                    .font(.style(.monoValue)).foregroundStyle(Theme.inkSecondary)
            }
            .help(event.sourcesDescription)
            .accessibilityElement(children: .combine)
        }
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
