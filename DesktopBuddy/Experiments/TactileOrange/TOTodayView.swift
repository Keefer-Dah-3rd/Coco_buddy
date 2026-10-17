#if DEBUG
import SwiftUI
import BuddyCore
import BuddyIntegrations

// EXPERIMENT — Tactile Orange "Tasks": every task is a key you can press. Same intents and
// the same merged schedule (`model.agenda`) as the real Today tab.

struct TOTodayView: View {
    let model: AppModel
    @Binding var expandedEventID: String?
    var openSection: (EOSection) -> Void

    var body: some View {
        let tasks = model.tasks.today()
        let upNext = !model.focus.timer.isActive && model.taskDrafts.isEmpty ? model.upNext : nil
        VStack(spacing: 0) {
            TOAddTask(model: model)
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TOSpeech(text: model.buddyLine).eoEntrance(0)


                    if tasks.isEmpty {
                        TOEmpty().eoEntrance(2)
                    }
                    if let upNext {
                        Button {
                            model.focus(on: upNext.task.id)
                            openSection(.focus)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    TOPill("Up next · " + TaskLabels.reason(upNext.reason))
                                    Spacer()
                                    Image(systemName: "play.fill").font(.system(size: 13, weight: .bold))
                                }
                                Text(upNext.task.title)
                                    .font(TO.font(21))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(TOKey(kind: .orange, padding: EdgeInsets(top: 18, leading: 20, bottom: 18, trailing: 20)))
                        .shadow(color: TO.orange.opacity(0.25), radius: 10, y: 6)
                        .help("Start a focus session on this task")
                        .eoEntrance(2)
                    }
                    ForEach(Array(tasks.filter { $0.id != upNext?.task.id }.enumerated()), id: \.element.id) { index, task in
                        TOTaskKey(task: task, model: model) { openSection(.focus) }
                            .eoEntrance(3 + index)
                    }

                    if !model.tasks.leftovers.isEmpty {
                        TOLeftovers(count: model.tasks.leftovers.count, model: model)
                    }
                    TOScheduleCard(model: model, expandedEventID: $expandedEventID)
                        .padding(.top, 6)
                        .eoEntrance(4)
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
                .padding(.bottom, 16)
                .animation(TO.Motion.pop, value: tasks.map(\.id))
            }
            .scrollIndicators(.never)

            if let removed = model.recentlyRemoved {
                HStack {
                    Text("Removed “\(BuddyVoice.short(removed.title, limit: 22))”")
                        .font(TO.font(14, .medium)).foregroundStyle(TO.inkSecondary).lineLimit(1)
                    Spacer()
                    Button("Undo") { model.undoRemove() }
                        .buttonStyle(TOKey(kind: .ink, radius: 16, depth: 4, padding: EdgeInsets(top: 7, leading: 14, bottom: 7, trailing: 14), size: 14))
                        .keyboardShortcut("z", modifiers: .command)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(TO.Motion.pop, value: model.recentlyRemoved?.id)
    }
}

// MARK: - Add task

/// `bg-white rounded-[24px] p-3` with a `+` key: the real quick-add, with the mic.
private struct TOAddTask: View {
    let model: AppModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        let parsed = QuickAddParser.parse(draft)
        let voice = model.voiceIn
        VStack(alignment: .leading, spacing: 6) {
            TOField(focused: focused || voice.isListening) {
                HStack(spacing: 10) {
                    Button { if model.addTask(draft) { draft = "" } } label: { Text("+").font(TO.font(20)) }
                        .buttonStyle(TOKey(kind: .well, radius: 16, depth: 4, padding: EdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 11)))
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                        .help("Add (Return)")
                    if voice.isListening {
                        Text(voice.transcript.isEmpty ? "Listening…" : voice.transcript)
                            .font(TO.font(17)).foregroundStyle(voice.transcript.isEmpty ? TO.inkMuted : TO.ink)
                            .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                            .eoPulse(voice.transcript.isEmpty)
                    } else {
                        TextField("Add a task", text: $draft, prompt: Text("Add a task…").foregroundStyle(TO.inkMuted))
                            .textFieldStyle(.plain)
                            .font(TO.font(17))
                            .foregroundStyle(TO.ink)
                            .focused($focused)
                            .onSubmit { if model.addTask(draft) { draft = "" } }
                    }
                    Button { model.toggleListening() } label: {
                        Image(systemName: voice.isListening ? "stop.fill" : "mic.fill").font(.system(size: 13, weight: .bold))
                    }
                    .buttonStyle(TOKey(kind: voice.isListening ? .orange : .well, radius: 16, depth: 4,
                                       padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)))
                    .keyboardShortcut("l", modifiers: .command)
                    .help(voice.isListening ? "Stop listening (⌘L)" : "Talk to \(Buddy.name) (⌘L)")
                }
            }
            if !voice.isListening, let parsed, parsed.priority != .none || parsed.estimateMinutes != nil {
                HStack(spacing: 6) {
                    if let minutes = parsed.estimateMinutes { TOPill("~" + TodayView.duration(minutes), face: TO.white, color: TO.inkSecondary) }
                    if parsed.priority != .none { TOPill(parsed.priority.label + " priority", face: TO.orange, color: .white) }
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
            if case .denied(let message) = voice.status { problem(message) }
            if case .unavailable(let message) = voice.status { problem(message) }
            if let problem = model.tasks.storageProblem {
                Text(problem).font(TO.font(12, .medium)).foregroundStyle(TO.orange)
            }
        }
        .animation(TO.Motion.pop, value: parsed?.priority)
        .animation(TO.Motion.pop, value: parsed?.estimateMinutes)
        .onAppear { focused = true }
        .onChange(of: model.panelOpenCount) { focused = true }
    }

    private func problem(_ message: String) -> some View {
        HStack(alignment: .top) {
            Text(message).font(TO.font(12, .medium)).foregroundStyle(TO.inkSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("OK") { model.voiceIn.clearProblem() }
                .buttonStyle(TOKey(kind: .white, radius: 12, depth: 3, padding: EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10), size: 12))
        }
    }
}

// MARK: - Task key

/// A white task key: ring to tick, the face to open the editor, play / remove on hover.
private struct TOTaskKey: View {
    let task: BuddyTask
    let model: AppModel
    let openFocus: () -> Void
    @State private var hovering = false

    private var inFocus: Bool { model.focus.timer.isActive && model.focus.timer.taskID == task.id }

    var body: some View {
        HStack(spacing: 14) {
            Button { model.toggleTask(task.id) } label: { TOCheck(checked: task.isCompleted) }
                .buttonStyle(.plain)
                .accessibilityLabel(task.isCompleted ? "Mark “\(task.title)” not done" : "Mark “\(task.title)” done")
            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(TO.font(17))
                    .foregroundStyle(task.isCompleted ? TO.inkMuted : TO.ink)
                    .strikethrough(task.isCompleted, color: TO.inkMuted)
                    .lineLimit(2)
                meta
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { model.editingTaskID = task.id }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the editor")
            if hovering {
                HStack(spacing: 6) {
                    if !task.isCompleted {
                        Button { model.focus(on: task.id); openFocus() } label: {
                            Image(systemName: "play.fill").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(TOKey(kind: .orange, radius: 10, depth: 3, padding: EdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)))
                        .help("Focus on this")
                        .accessibilityLabel("Focus on \(task.title)")
                    }
                    Button { model.removeTask(task.id) } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(TOKey(kind: .well, radius: 10, depth: 3, padding: EdgeInsets(top: 8, leading: 9, bottom: 8, trailing: 9)))
                    .help("Remove")
                    .accessibilityLabel("Remove \(task.title)")
                }
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 16))
        .toFace(.white, edge: TO.edge, radius: TO.Radius.key, depth: 6, lift: hovering ? 1 : 0)
        .overlay(alignment: .leading) {
            if inFocus { Capsule().fill(TO.orange).frame(width: 4).padding(.vertical, 16).offset(x: -10) }
        }
        .opacity(task.isCompleted ? 0.6 : 1)
        .onHover { hovering = $0 }
        .animation(TO.Motion.pop, value: hovering)
        .animation(TO.Motion.pop, value: task.isCompleted)
        .contextMenu {
            if !task.isCompleted { Button("Focus on this") { model.focus(on: task.id); openFocus() } }
            Button("Edit") { model.editingTaskID = task.id }
            Button(task.isCompleted ? "Mark not done" : "Mark done") { model.toggleTask(task.id) }
            Divider()
            Button("Remove") { model.removeTask(task.id) }
        }
    }

    @ViewBuilder
    private var meta: some View {
        let due = TaskLabels.due(task)
        if inFocus || (task.priority != .none && !task.isCompleted) || task.estimateMinutes != nil || due != nil || task.scope == .today {
            HStack(spacing: 5) {
                if inFocus { TOPill("In focus", face: TO.orange, color: .white) }
                if task.priority != .none, !task.isCompleted {
                    TOPill(String(repeating: "!", count: task.priority.rawValue) + " " + task.priority.label, face: TO.orange.opacity(0.12), color: TO.orangeEdge)
                }
                if let minutes = task.estimateMinutes { TOPill(TodayView.duration(minutes), face: TO.card, color: TO.inkSecondary) }
                if let due, !task.isCompleted { TOPill(due.text, face: due.urgent ? TO.orange.opacity(0.12) : TO.card, color: due.urgent ? TO.orangeEdge : TO.inkSecondary) }
                if task.scope == .today { TOPill("Today only", face: TO.card, color: TO.inkSecondary) }
            }
        }
    }
}

private struct TOLeftovers: View {
    let count: Int
    let model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("\(count) left over").font(TO.font(15)).foregroundStyle(TO.ink)
            Spacer()
            Button("Carry over") { model.carryOverLeftovers() }
                .buttonStyle(TOKey(kind: .orange, radius: 14, depth: 4, padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12), size: 13))
            Button("Let go") { model.letGoOfLeftovers() }
                .buttonStyle(TOKey(kind: .white, radius: 14, depth: 4, padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12), size: 13))
        }
        .padding(14)
        .toFace(TO.card, edge: TO.edge, radius: 20, depth: 4)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white, lineWidth: 3))
    }
}

private struct TOEmpty: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("🦴").font(.system(size: 34))
            Text("Nothing on the list yet!").font(TO.font(20)).foregroundStyle(TO.ink)
            Text("Type above and press Return. Try ~25m for time, ! to !!! for priority, @today for one day.")
                .font(TO.font(14, .medium)).foregroundStyle(TO.inkSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Schedule

/// Today's merged calendar in one white card: now / next as a pill, the day as rows with
/// open time between, coming up, and a Week key that opens a chunky day strip.
struct TOScheduleCard: View {
    let model: AppModel
    @Binding var expandedEventID: String?

    var body: some View {
        let agenda = model.agenda
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📅").font(.system(size: 15))
                Text(model.scheduleExpanded ? "This week" : "Today's plan").font(TO.font(17)).foregroundStyle(TO.ink)
                Spacer()
                if agenda.isConnected {
                    Button(model.scheduleExpanded ? "Today" : "Week") {
                        if !model.scheduleExpanded { model.showScheduleDay(model.scheduleDay) }
                        withAnimation(TO.Motion.pop) { model.scheduleExpanded.toggle() }
                    }
                    .buttonStyle(TOKey(kind: .well, radius: 12, depth: 3, padding: EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10), size: 12))
                }
            }
            if !agenda.isConnected {
                Text("No calendar connected yet.").font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary)
                Button("Connect a calendar") { model.openConnections() }
                    .buttonStyle(TOKey(kind: .orange, radius: 16, depth: 4, padding: EdgeInsets(top: 8, leading: 14, bottom: 8, trailing: 14), size: 14))
            } else if model.scheduleExpanded {
                week
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in today(now: context.date) }
            }
        }
        .padding(16)
        .toFace(.white, edge: TO.edge, radius: TO.Radius.key, depth: 6)
    }

    private func today(now: Date) -> some View {
        let agenda = model.agenda
        let _ = model.dayToken
        let loaded = agenda.events(on: now)
        let schedule = DaySchedule(events: loaded ?? [])
        let current = schedule.current(at: now)
        let next = schedule.next(after: now)
        let remaining = schedule.events.filter { $0.end > now }
        let open = remaining.isEmpty ? [] : Availability.openings(on: now, events: loaded ?? [], hours: model.workingHours,
                                                                  minimum: 30 * 60, notBefore: now, calendar: .current)
        return VStack(alignment: .leading, spacing: 6) {
            if loaded == nil && agenda.isLoading(now) {
                Text("Fetching your day…").font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary).eoPulse()
            } else {
                if let current {
                    TOPill("Now · " + RelativeTiming.remaining(until: current.end, now: now), face: TO.orange, color: .white)
                }
                if let next {
                    let urgent = next.start.timeIntervalSince(now) <= 15 * 60
                    TOPill("Next · \(BuddyVoice.short(next.title, limit: 22)) · " + RelativeTiming.untilStart(of: next.start, now: now),
                           face: urgent ? TO.orange : TO.card, color: urgent ? .white : TO.ink)
                        .eoPulse(urgent)
                }
                ForEach(schedule.allDayEvents) { event in
                    TOEventRow(event: event, now: now, label: "All day", expandedEventID: $expandedEventID)
                }
                ForEach(mergedRows(schedule.events, open)) { row in
                    switch row {
                    case .event(let event):
                        TOEventRow(event: event, now: now, label: event.start.formatted(date: .omitted, time: .shortened), expandedEventID: $expandedEventID)
                    case .open(let interval):
                        Text("☀️ Open · \(TodayView.duration(Int(interval.duration / 60)))")
                            .font(TO.font(13, .medium)).foregroundStyle(TO.inkMuted)
                            .padding(.leading, 70).padding(.vertical, 2)
                    }
                }
                if schedule.events.isEmpty && schedule.allDayEvents.isEmpty {
                    Text("No meetings today — wide open! 🎾").font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary)
                }
            }
            problems(now)
            let upcoming = agenda.comingUp(after: now, limit: 3)
            if !upcoming.isEmpty {
                Text("Coming up").font(TO.font(13)).foregroundStyle(TO.inkMuted).padding(.top, 6)
                ForEach(upcoming) { event in
                    TOEventRow(event: event, now: now, label: RelativeTiming.day(of: event.start, now: now), expandedEventID: $expandedEventID)
                }
            }
        }
    }

    private enum Row: Identifiable {
        case event(CalendarEvent)
        case open(DateInterval)
        var id: String {
            switch self {
            case .event(let e): e.id
            case .open(let i): "open-\(i.start.timeIntervalSince1970)"
            }
        }
        var start: Date {
            switch self {
            case .event(let e): e.start
            case .open(let i): i.start
            }
        }
    }

    private func mergedRows(_ events: [CalendarEvent], _ open: [DateInterval]) -> [Row] {
        (events.map(Row.event) + open.map(Row.open)).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
    }

    @ViewBuilder
    private func problems(_ day: Date) -> some View {
        let failing = model.agenda.activeSources.filter { $0.problem(for: day) != nil }.map(\.sourceName)
        if model.calendar.status == .needsReconnect || !failing.isEmpty {
            Button(model.calendar.status == .needsReconnect ? "Google Calendar needs reconnecting" : "Couldn't refresh \(failing.joined(separator: " or "))") {
                model.openConnections()
            }
            .buttonStyle(TOKey(kind: .orange, radius: 14, depth: 4, padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12), size: 13))
        }
    }

    private var week: some View {
        let calendar = Calendar.current
        let day = model.scheduleDay
        let start = model.calendar.weekStart(for: day)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let events = model.agenda.events(on: day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Button { model.moveScheduleDay(by: -7) } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(TOKey(kind: .well, radius: 10, depth: 3, padding: EdgeInsets(top: 9, leading: 6, bottom: 9, trailing: 6)))
                ForEach(days, id: \.self) { date in
                    let selected = calendar.isDate(date, inSameDayAs: day)
                    Button { model.showScheduleDay(date) } label: {
                        VStack(spacing: 1) {
                            Text(date.formatted(.dateTime.weekday(.narrow))).font(TO.font(10))
                            Text(date.formatted(.dateTime.day())).font(TO.font(15))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TOKey(kind: selected ? .orange : calendar.isDateInToday(date) ? .white : .well, radius: 12, depth: 3,
                                       padding: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0), size: 13))
                }
                Button { model.moveScheduleDay(by: 7) } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)) }
                    .buttonStyle(TOKey(kind: .well, radius: 10, depth: 3, padding: EdgeInsets(top: 9, leading: 6, bottom: 9, trailing: 6)))
            }
            Text(AppModel.shortDay(day)).font(TO.font(15)).foregroundStyle(TO.ink).padding(.top, 2)
            if events == nil && model.agenda.isLoading(day) {
                Text("Fetching…").font(TO.font(14, .medium)).foregroundStyle(TO.inkSecondary).eoPulse()
            } else if let events, !events.isEmpty {
                let schedule = DaySchedule(events: events)
                ForEach(schedule.allDayEvents) { TOEventRow(event: $0, now: .now, label: "All day", expandedEventID: $expandedEventID) }
                ForEach(schedule.events) { TOEventRow(event: $0, now: .now, label: $0.start.formatted(date: .omitted, time: .shortened), expandedEventID: $expandedEventID) }
            } else if events != nil {
                Text("Nothing planned.").font(TO.font(14, .medium)).foregroundStyle(TO.inkSecondary)
            }
            problems(day)
        }
        .id(day)
    }
}

/// One event row; tap to open its details in a sunken well.
private struct TOEventRow: View {
    let event: CalendarEvent
    let now: Date
    let label: String
    @Binding var expandedEventID: String?

    private var isOpen: Bool { expandedEventID == event.id }
    private var isNow: Bool { !event.isAllDay && event.start <= now && now < event.end }
    private var isPast: Bool { !event.isAllDay && event.end <= now }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(TO.Motion.pop) { expandedEventID = isOpen ? nil : event.id }
            } label: {
                HStack(spacing: 10) {
                    Text(label).font(TO.font(12, .semibold)).foregroundStyle(isNow ? TO.orange : TO.inkMuted)
                        .frame(width: 62, alignment: .leading).lineLimit(1).minimumScaleFactor(0.8)
                    Circle().fill(isNow ? TO.orange : TO.edge).frame(width: 8, height: 8)
                    Text(event.title).font(TO.font(15)).foregroundStyle(TO.ink).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(TO.inkMuted)
                }
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppModel.describe(event.start, event.end, allDay: event.isAllDay)).font(TO.font(13, .semibold)).foregroundStyle(TO.ink)
                    if let location = event.location, !location.isEmpty {
                        Text("📍 " + location).font(TO.font(13, .medium)).foregroundStyle(TO.inkSecondary)
                    }
                    Text("In " + event.sourcesDescription).font(TO.font(12, .medium)).foregroundStyle(TO.inkSecondary)
                    let copies = event.alsoIn.filter { $0.match == .details }
                    if !copies.isEmpty {
                        Text("Also saved separately in \(copies.map(\.label).joined(separator: " and ")) — shown once.")
                            .font(TO.font(12, .medium)).foregroundStyle(TO.inkMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    if let notes = event.notes.map(AppModel.withoutPartifulBoilerplate), !notes.isEmpty {
                        Text(notes).font(TO.font(12, .medium)).foregroundStyle(TO.inkSecondary).lineLimit(3)
                    }
                    HStack(spacing: 8) {
                        if let link = event.meetingLink {
                            Link(destination: link) { linkKey("Join call", orange: true) }
                        }
                        if let link = event.htmlLink {
                            Link(destination: link) { linkKey(event.provider == .partiful ? "Open invite" : "Open", orange: false) }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(TO.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
            }
        }
        .opacity(isPast && !isOpen ? 0.45 : 1)
        .help(event.sourcesDescription)
    }

    private func linkKey(_ title: String, orange: Bool) -> some View {
        Text(title)
            .font(TO.font(12))
            .foregroundStyle(orange ? .white : TO.ink)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .toFace(orange ? TO.orange : .white, edge: orange ? TO.orangeEdge : TO.edge, radius: 12, depth: 3)
    }
}
#endif
