#if DEBUG
import SwiftUI
import BuddyCore
import BuddyIntegrations

// EXPERIMENT — the schedule in Editorial Orange. Reads `model.agenda`, the same merged
// schedule the real Today card, reminders and chat use: Google, Apple Calendar and Partiful
// with duplicates shown once (CalendarMerge). No calendar logic of its own.

struct EOScheduleSection: View {
    let model: AppModel
    @Binding var expandedEventID: String?

    var body: some View {
        let agenda = model.agenda
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: EO.Space.sm) {
                EOKicker("The Schedule", color: EO.Ink.secondary, size: 11)
                Spacer()
                if agenda.isConnected {
                    Button(model.scheduleExpanded ? "Today" : "Week") {
                        if !model.scheduleExpanded { model.showScheduleDay(model.scheduleDay) }
                        withAnimation(EO.Motion.slideUp) { model.scheduleExpanded.toggle() }
                    }
                    .buttonStyle(EOLinkButtonStyle(arrow: model.scheduleExpanded ? "↑" : "→"))
                    .help(model.scheduleExpanded ? "Show just today" : "Browse the week")
                }
            }
            .padding(.bottom, EO.Space.sm)
            EORule()

            if !agenda.isConnected {
                notConnected
            } else if model.scheduleExpanded {
                EOWeekView(model: model, expandedEventID: $expandedEventID)
                    .transition(.opacity.combined(with: .offset(y: EO.Motion.slideDistance)))
            } else {
                // Once a minute, so "in 15m" and "20m left" stay true.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    today(now: context.date)
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Not connected

    private var notConnected: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No calendar connected.")
                .font(EO.font(EO.Size.lead, .light, italic: true))
                .foregroundStyle(EO.ink)
            Text("Connect Google Calendar, Apple Calendar or a Partiful link and \(Buddy.name) shows the day here — each meeting once, even if it's in two calendars.")
                .font(EO.font(14, .light))
                .foregroundStyle(EO.Ink.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            Button("Connect a calendar") { model.openConnections() }
                .buttonStyle(EOLinkButtonStyle(color: EO.orange))
        }
        .padding(.vertical, EO.Space.md)
    }

    // MARK: - Today

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

    private func today(now: Date) -> some View {
        let agenda = model.agenda
        let _ = model.dayToken
        let loaded = agenda.events(on: now)
        let events = loaded ?? []
        let schedule = DaySchedule(events: events)
        let remaining = schedule.events.filter { $0.end > now }
        let current = schedule.current(at: now)
        let next = schedule.next(after: now)
        let open = remaining.isEmpty ? [] : Availability.openings(on: now, events: events, hours: model.workingHours,
                                                                  minimum: 30 * 60, notBefore: now, calendar: .current)
        let items = (schedule.events.map(Item.event) + open.map(Item.open)).sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        let openMinutes = Int(open.reduce(0) { $0 + $1.duration } / 60)

        return VStack(alignment: .leading, spacing: 0) {
            if loaded == nil && agenda.isLoading(now) {
                quietLine("Loading the schedule…").eoPulse()
            } else {
                if current != nil || next != nil {
                    lead(current: current, next: next, now: now)
                }
                if !schedule.events.isEmpty {
                    HStack {
                        EOKicker("The Day", color: EO.Ink.secondary, size: 10)
                        Spacer()
                        EOKicker(remaining.isEmpty ? "Done" : "\(remaining.count) left" + (openMinutes > 0 ? " · \(TodayView.duration(openMinutes)) open" : ""),
                                 color: EO.Ink.secondary, size: 10, weight: .medium)
                    }
                    .padding(.top, EO.Space.md)
                    .padding(.bottom, 6)
                }
                ForEach(schedule.allDayEvents) { event in
                    EOEventRow(event: event, now: now, label: "All day", expandedEventID: $expandedEventID)
                }
                ForEach(items) { item in
                    switch item {
                    case .event(let event):
                        EOEventRow(event: event, now: now, label: event.start.formatted(date: .omitted, time: .shortened),
                                   expandedEventID: $expandedEventID)
                    case .open(let interval):
                        EOOpenRow(interval: interval)
                    }
                }
                if schedule.events.isEmpty && schedule.allDayEvents.isEmpty {
                    quietLine("No meetings today — wide open.")
                } else if remaining.isEmpty && !schedule.events.isEmpty {
                    quietLine("That's all for today — no more meetings.")
                }
            }
            EOScheduleProblems(model: model, day: now)
            comingUp(now: now)
        }
    }

    /// The newspaper lead: what's on now and how long is left, then what's next and how soon.
    private func lead(current: CalendarEvent?, next: CalendarEvent?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: EO.Space.sm) {
            if let current {
                VStack(alignment: .leading, spacing: 6) {
                    EOKicker("Now · " + RelativeTiming.remaining(until: current.end, now: now), size: EO.Size.micro)
                    Text(current.title)
                        .font(EO.font(EO.Size.item, .medium))
                        .tracking(EO.Tracking.tight(EO.Size.item))
                        .foregroundStyle(EO.ink)
                        .lineLimit(2)
                }
            }
            if let next {
                let urgent = next.start.timeIntervalSince(now) <= 15 * 60
                VStack(alignment: .leading, spacing: 6) {
                    EOKicker("Next · " + RelativeTiming.untilStart(of: next.start, now: now),
                             color: urgent ? EO.orange : EO.Ink.secondary, size: EO.Size.micro)
                    HStack(alignment: .firstTextBaseline) {
                        Text(next.title)
                            .font(EO.font(current == nil ? EO.Size.item : EO.Size.lead, current == nil ? .medium : .light,
                                          italic: current != nil))
                            .tracking(EO.Tracking.tight(EO.Size.lead))
                            .foregroundStyle(EO.ink)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if let link = next.meetingLink, urgent {
                            Link("Join →", destination: link)
                                .font(EO.font(11, .bold))
                                .tracking(EO.Tracking.widest(11))
                                .foregroundStyle(EO.orange)
                        }
                    }
                }
                .eoPulse(urgent && next.start > now)
            }
        }
        .padding(.top, EO.Space.md)
        .accessibilityElement(children: .combine)
    }

    /// The next few events after today.
    @ViewBuilder
    private func comingUp(now: Date) -> some View {
        let agenda = model.agenda
        let upcoming = agenda.comingUp(after: now, limit: 3)
        let weekAhead = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        VStack(alignment: .leading, spacing: 0) {
            EOKicker("Coming Up", color: EO.Ink.secondary, size: 10)
                .padding(.top, EO.Space.md)
                .padding(.bottom, 6)
            if upcoming.isEmpty {
                quietLine(agenda.events(on: weekAhead) == nil && agenda.isLoading(weekAhead) ? "Loading…" : "Nothing in the next 7 days.")
            }
            ForEach(upcoming) { event in
                EOEventRow(event: event, now: now, label: RelativeTiming.day(of: event.start, now: now),
                           trailing: event.isAllDay ? "all day" : event.start.formatted(date: .omitted, time: .shortened),
                           expandedEventID: $expandedEventID)
            }
        }
    }

    private func quietLine(_ text: String) -> some View {
        Text(text)
            .font(EO.font(16, .light, italic: true))
            .foregroundStyle(EO.Ink.secondary)
            .padding(.vertical, 12)
    }
}

// MARK: - Rows

/// One event: a light time column, the title, and — opened — its details. Finished events
/// fade back; the one happening now carries an orange mark.
struct EOEventRow: View {
    let event: CalendarEvent
    let now: Date
    let label: String
    var trailing: String?
    @Binding var expandedEventID: String?
    @State private var hovering = false

    private var isOpen: Bool { expandedEventID == event.id }
    private var isNow: Bool { !event.isAllDay && event.start <= now && now < event.end }
    private var isPast: Bool { !event.isAllDay && event.end <= now }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(EO.Motion.slideUp) { expandedEventID = isOpen ? nil : event.id }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(label)
                        .font(EO.font(label.count > 8 ? 10 : 13, label.count > 8 ? .bold : .light))
                        .tracking(label.count > 8 ? EO.Tracking.widest(10) : 0)
                        .textCase(label.count > 8 ? .uppercase : nil)
                        .monospacedDigit()
                        .foregroundStyle(isNow ? EO.orange : EO.Ink.secondary)
                        .frame(width: 72, alignment: .leading)
                    Text(event.title)
                        .font(EO.font(17, isNow ? .medium : .regular, italic: hovering || isOpen))
                        .foregroundStyle(EO.ink)
                        .lineLimit(isOpen ? 3 : 1)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let trailing {
                        Text(trailing).font(EO.font(13, .light)).monospacedDigit().foregroundStyle(EO.Ink.secondary)
                    } else if !event.isAllDay {
                        Text(TodayView.duration(max(1, Int(event.duration / 60))))
                            .font(EO.font(13, .light)).foregroundStyle(EO.Ink.muted)
                    }
                    Text(isOpen ? "–" : "+")
                        .font(EO.font(15, .light))
                        .foregroundStyle(EO.Ink.secondary)
                        .opacity(hovering || isOpen ? 1 : 0)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .leading) {
                if isNow { Circle().fill(EO.orange).frame(width: 6, height: 6).offset(x: -14) }
            }

            if isOpen {
                EOEventDetail(event: event)
                    .padding(.leading, 86)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .opacity(isPast && !isOpen ? 0.4 : 1)
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
        .onHover { hovering = $0 }
        .animation(EO.Motion.hover, value: hovering)
        .help(event.sourcesDescription)
        .accessibilityElement(children: .combine)
        .accessibilityHint(isOpen ? "Hides the details" : "Shows the details")
    }
}

/// An opened event: when, where, the call link, which calendars it's in (one line even
/// when it's in two), notes.
struct EOEventDetail: View {
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppModel.describe(event.start, event.end, allDay: event.isAllDay) + (event.endIsEstimated ? " (end time estimated)" : ""))
                .font(EO.font(14, .light))
                .foregroundStyle(EO.ink)
            if let location = event.location, !location.isEmpty {
                Text(location).font(EO.font(14, .light, italic: true)).foregroundStyle(EO.Ink.secondary).lineLimit(2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                EOKicker("In", color: EO.Ink.muted, size: 9)
                Text(event.sourcesDescription).font(EO.font(12)).foregroundStyle(EO.Ink.secondary)
            }
            let copies = event.alsoIn.filter { $0.match == .details }
            if !copies.isEmpty {
                Text("Also saved separately in \(copies.map(\.label).joined(separator: " and ")) — shown once.")
                    .font(EO.font(12, .light, italic: true)).foregroundStyle(EO.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if event.isRecurring { EOKicker("Repeats", color: EO.Ink.secondary, size: 9) }
            if !event.isBusy { EOKicker("Marked free", color: EO.Ink.secondary, size: 9) }
            if let notes = event.notes.map(AppModel.withoutPartifulBoilerplate), !notes.isEmpty {
                Text(notes).font(EO.font(13, .light)).foregroundStyle(EO.Ink.secondary).lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: EO.Space.md) {
                if let link = event.meetingLink {
                    Link(destination: link) { linkLabel("Join call") }
                }
                if let link = event.htmlLink {
                    Link(destination: link) { linkLabel(event.provider == .partiful ? "Open invite" : "Open in calendar") }
                }
            }
            .padding(.top, 2)
        }
    }

    private func linkLabel(_ text: String) -> some View {
        HStack(spacing: 5) {
            Text(text.uppercased()).font(EO.font(10, .bold)).tracking(EO.Tracking.widest(10))
            Text("→").font(EO.font(12, .light))
        }
        .foregroundStyle(EO.orange)
    }
}

/// Free time between meetings, in light italic.
private struct EOOpenRow: View {
    let interval: DateInterval

    var body: some View {
        HStack(spacing: 14) {
            Text(interval.start.formatted(date: .omitted, time: .shortened))
                .font(EO.font(13, .light)).monospacedDigit().foregroundStyle(EO.Ink.faint)
                .frame(width: 72, alignment: .leading)
            Text("Open · \(TodayView.duration(Int(interval.duration / 60)))")
                .font(EO.font(15, .light, italic: true))
                .foregroundStyle(EO.Ink.muted)
            Spacer()
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { EORule(color: EO.Ink.hairline) }
        .accessibilityLabel("Open for \(TodayView.duration(Int(interval.duration / 60)))")
    }
}

/// A calendar that couldn't be read, or Google needing a new sign-in — with the way to fix it.
struct EOScheduleProblems: View {
    let model: AppModel
    let day: Date

    var body: some View {
        let failing = model.agenda.activeSources.filter { $0.problem(for: day) != nil }.map(\.sourceName)
        if model.calendar.status == .needsReconnect || !failing.isEmpty {
            Button {
                model.openConnections()
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    EOKicker(model.calendar.status == .needsReconnect ? "Reconnect needed" : "Couldn't refresh", size: 10)
                    Text(model.calendar.status == .needsReconnect ? "Google Calendar needs reconnecting. Open Connections →"
                         : "\(failing.joined(separator: " or ")) — showing what's saved. Open Connections →")
                        .font(EO.font(14, .light, italic: true))
                        .foregroundStyle(EO.ink)
                        .multilineTextAlignment(.leading)
                }
                .padding(.vertical, 12)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(EO.orange).frame(width: 2) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }
}

// MARK: - Week

/// The week browser: a day strip set like a table of contents, then the chosen day.
struct EOWeekView: View {
    let model: AppModel
    @Binding var expandedEventID: String?

    var body: some View {
        let calendar = Calendar.current
        let day = model.scheduleDay
        let start = model.calendar.weekStart(for: day)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { model.moveScheduleDay(by: -7) } label: { Text("←").font(EO.font(18, .light)) }
                    .buttonStyle(.plain).help("Previous week")
                Spacer()
                EOKicker("Week of " + start.formatted(.dateTime.month(.wide).day()), color: EO.ink, size: 10)
                Spacer()
                Button { model.moveScheduleDay(by: 7) } label: { Text("→").font(EO.font(18, .light)) }
                    .buttonStyle(.plain).help("Next week")
            }
            .foregroundStyle(EO.ink)
            .padding(.top, EO.Space.sm)

            HStack(spacing: 0) {
                ForEach(days, id: \.self) { date in
                    dayKey(date, selected: calendar.isDate(date, inSameDayAs: day), isToday: calendar.isDateInToday(date))
                }
            }
            .padding(.vertical, EO.Space.sm)
            EORule(color: EO.Ink.hairline)

            dayList(day)
                .id(day)
                .transition(.opacity)
        }
        .animation(EO.Motion.fadeIn, value: day)
    }

    private func dayKey(_ date: Date, selected: Bool, isToday: Bool) -> some View {
        let count = model.agenda.events(on: date)?.count
        return Button { model.showScheduleDay(date) } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.weekday(.narrow)))
                    .font(EO.font(10, .bold))
                    .foregroundStyle(selected ? EO.orange : EO.Ink.secondary)
                Text(date.formatted(.dateTime.day()))
                    .font(EO.font(EO.Size.lead, selected ? .medium : .light, italic: selected))
                    .foregroundStyle(selected ? EO.orange : EO.ink)
                Rectangle()
                    .fill(selected ? EO.orange : .clear)
                    .frame(width: 18, height: 2)
                HStack(spacing: 2) {
                    ForEach(0..<min(count ?? 0, 4), id: \.self) { _ in
                        Circle().fill(selected ? EO.orange : EO.Ink.muted).frame(width: 3, height: 3)
                    }
                }
                .frame(height: 3)
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .topTrailing) {
                if isToday && !selected { Circle().fill(EO.orange).frame(width: 4, height: 4).offset(x: -6) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (count.map { ", \($0) events" } ?? ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder
    private func dayList(_ day: Date) -> some View {
        let agenda = model.agenda
        let events = agenda.events(on: day)
        VStack(alignment: .leading, spacing: 0) {
            Text(AppModel.shortDay(day))
                .font(EO.font(EO.Size.item, .medium))
                .tracking(EO.Tracking.tight(EO.Size.item))
                .foregroundStyle(EO.ink)
                .padding(.top, EO.Space.sm)
                .padding(.bottom, 6)
            if events == nil && agenda.isLoading(day) {
                Text("Loading…").font(EO.font(16, .light, italic: true)).foregroundStyle(EO.Ink.secondary).padding(.vertical, 12).eoPulse()
            } else if let events, !events.isEmpty {
                let schedule = DaySchedule(events: events)
                ForEach(schedule.allDayEvents) { event in
                    EOEventRow(event: event, now: .now, label: "All day", expandedEventID: $expandedEventID)
                }
                ForEach(schedule.events) { event in
                    EOEventRow(event: event, now: .now, label: event.start.formatted(date: .omitted, time: .shortened),
                               expandedEventID: $expandedEventID)
                }
            } else if events != nil {
                Text("Nothing on the calendar.").font(EO.font(16, .light, italic: true)).foregroundStyle(EO.Ink.secondary).padding(.vertical, 12)
            }
            EOScheduleProblems(model: model, day: day)
        }
    }
}
#endif
