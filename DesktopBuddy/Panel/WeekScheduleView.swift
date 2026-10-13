import SwiftUI
import BuddyIntegrations

/// The Today card's calendar, opened out: a week of days you can click or drag across, the
/// week at a glance, and the chosen day in order with its open time between events.
/// Everything reads the calendar service's shared week cache, so it matches what Coco says.
struct WeekScheduleView: View {
    let model: AppModel
    @FocusState private var focused: Bool
    /// The first day of the strip when a drag began, so scrubbing past the edge carries on
    /// into the next week instead of jumping.
    @State private var dragBase: Date?

    private let calendar = Calendar.current

    var body: some View {
        let day = model.scheduleDay
        let weekStart = model.calendar.weekStart(for: day)
        let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        VStack(alignment: .leading, spacing: Space.sm) {
            header(days)
            strip(days)
            WeekSummary(model: model, days: days)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            DayAgenda(model: model, day: day)
                .id(day)
                .transition(.opacity)
        }
        .animation(.easeOut(duration: 0.12), value: day)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            let step = press.modifiers.contains(.shift) ? 7 : 1
            model.moveScheduleDay(by: press.key == .leftArrow ? -step : step)
            return .handled
        }
        .onKeyPress("t") {
            model.showScheduleDay(.now)
            return .handled
        }
        .onAppear { model.calendar.prefetch(around: model.scheduleDay) }
    }

    private func header(_ days: [Date]) -> some View {
        HStack(spacing: Space.xs) {
            MonoLabel(Self.weekLabel(days), color: Theme.ink)
                .accessibilityLabel("Week of \(days.first?.formatted(date: .long, time: .omitted) ?? "")")
            Spacer(minLength: Space.xs)
            Button { model.moveScheduleDay(by: -7) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                .help("Previous week (⇧←)")
                .accessibilityLabel("Previous week")
            Button("Today") { model.showScheduleDay(.now) }
                .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                .disabled(calendar.isDateInToday(model.scheduleDay))
                .help("Back to today (T)")
            Button { model.moveScheduleDay(by: 7) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(KeyButtonStyle(kind: .quiet, compact: true))
                .help("Next week (⇧→)")
                .accessibilityLabel("Next week")
        }
    }

    /// Seven day keys. Click one, or drag across to scrub — past either end keeps going.
    private func strip(_ days: [Date]) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width / 7
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
                    DayKey(model: model, day: day)
                        .frame(width: width)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let base = dragBase ?? days[0]
                        if dragBase == nil { dragBase = base }
                        let offset = Int((drag.location.x / width).rounded(.down))
                        if let target = calendar.date(byAdding: .day, value: offset, to: base),
                           !calendar.isDate(target, inSameDayAs: model.scheduleDay) {
                            model.showScheduleDay(target)
                        }
                    }
                    .onEnded { _ in
                        dragBase = nil
                        focused = true
                    }
            )
        }
        .frame(height: 46)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Days of the week")
        .accessibilityHint("Use the left and right arrow keys to change day")
    }

    static func weekLabel(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let sameMonth = Calendar.current.isDate(first, equalTo: last, toGranularity: .month)
        let start = first.formatted(.dateTime.month(.abbreviated).day())
        let end = sameMonth ? last.formatted(.dateTime.day()) : last.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) – \(end)"
    }
}

/// One day in the strip: weekday, date, and a bar for how booked it is.
private struct DayKey: View {
    let model: AppModel
    let day: Date

    var body: some View {
        let calendar = Calendar.current
        let selected = calendar.isDate(day, inSameDayAs: model.scheduleDay)
        let today = calendar.isDateInToday(day)
        let load = booked
        VStack(spacing: 3) {
            Text(day.formatted(.dateTime.weekday(.narrow)))
                .font(.style(.monoTiny))
                .foregroundStyle(selected ? Theme.paper.opacity(0.75) : Theme.inkTertiary)
            Text(day.formatted(.dateTime.day()))
                .font(.style(.bodySmallEmphasis))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.paper : today ? Theme.accent : Theme.ink)
            Capsule()
                .fill(barColor(selected: selected, load: load))
                .frame(width: max(4, 26 * CGFloat(load ?? 0)), height: 3)
                .opacity(load == nil ? 0.35 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Radius.key, style: .continuous)
                .fill(selected ? Theme.ink : .clear)
                .padding(.horizontal, 2)
        }
        .overlay(alignment: .bottom) {
            if today && !selected {
                Circle().fill(Theme.accent).frame(width: 3, height: 3).offset(y: 1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(today: today))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.showScheduleDay(day) }
    }

    /// Share of working hours booked, or nil while the week isn't loaded.
    private var booked: Double? {
        guard let events = model.calendar.events(on: day),
              let window = model.workingHours.interval(on: day, calendar: .current), window.duration > 0 else { return nil }
        return min(1, Double(Availability.bookedMinutes(events, within: window)) * 60 / window.duration)
    }

    private func barColor(selected: Bool, load: Double?) -> Color {
        if selected { return Theme.paper.opacity(0.85) }
        if let load, load >= 0.85 { return Theme.accent }
        return Theme.inkSecondary
    }

    private func accessibilityText(today: Bool) -> String {
        var text = day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (today ? ", today" : "")
        if let events = model.calendar.events(on: day) {
            let timed = events.filter { !$0.isAllDay }.count
            text += ", \(timed) event\(timed == 1 ? "" : "s")"
        }
        return text
    }
}

/// "9 events · 11h booked · lightest Thu".
private struct WeekSummary: View {
    let model: AppModel
    let days: [Date]

    var body: some View {
        let calendar = Calendar.current
        let loaded = days.compactMap { day in model.calendar.events(on: day).map { (day, $0) } }
        if loaded.count == days.count {
            let perDay = loaded.map { day, events -> (Date, Int, Int) in
                let timed = events.filter { !$0.isAllDay }
                return (day, timed.count, Availability.bookedMinutes(timed, within: Availability.dayInterval(day, calendar: calendar)))
            }
            let count = perDay.reduce(0) { $0 + $1.1 }
            let minutes = perDay.reduce(0) { $0 + $1.2 }
            let workdays = perDay.filter { !calendar.isDateInWeekend($0.0) }
            let lightest = (workdays.isEmpty ? perDay : workdays).min { $0.2 < $1.2 }
            HStack(spacing: Space.xs) {
                MonoLabel("\(count) event\(count == 1 ? "" : "s")")
                MonoLabel("· \(TodayView.duration(minutes)) booked")
                if let lightest, count > 0 {
                    MonoLabel("· lightest \(lightest.0.formatted(.dateTime.weekday(.abbreviated)))")
                }
            }
        } else {
            MonoLabel(days.contains { model.calendar.isLoading($0) } ? "Loading the week…" : " ")
        }
    }
}

/// The chosen day: all-day items, then events in order with the open time between them.
struct DayAgenda: View {
    let model: AppModel
    let day: Date

    var body: some View {
        let service = model.calendar
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.sm) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                    .font(.style(.bodySmallEmphasis))
                    .foregroundStyle(Theme.ink)
                Spacer()
                if let events = service.events(on: day) {
                    let timed = events.filter { !$0.isAllDay }
                    let minutes = Availability.bookedMinutes(timed, within: Availability.dayInterval(day, calendar: .current))
                    MonoLabel(timed.isEmpty ? "free" : "\(timed.count) · \(TodayView.duration(minutes))")
                }
            }
            if let events = service.events(on: day) {
                agenda(events)
            } else if let problem = service.problem(for: day), !service.isLoading(day) {
                problemView(problem)
            } else {
                HStack(spacing: Space.sm) {
                    ProgressView().controlSize(.small)
                    MonoLabel("Loading \(day.formatted(.dateTime.weekday(.abbreviated)))…")
                }
                .padding(.vertical, Space.xs)
            }
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

    @ViewBuilder
    private func agenda(_ events: [CalendarEvent]) -> some View {
        let calendar = Calendar.current
        let now = Date.now
        let bounds = Availability.dayInterval(day, calendar: calendar)
        let isToday = calendar.isDateInToday(day)
        let allDay = events.filter(\.isAllDay)
        let timed = events.filter { !$0.isAllDay }
        let open = bounds.end <= now ? [] : Availability.openings(on: day, events: events, hours: model.workingHours,
                                                                  notBefore: isToday ? now : nil, calendar: calendar)
        let items = (timed.map(Item.event) + open.map(Item.open)).sorted { $0.start < $1.start }

        ForEach(allDay) { event in
            HStack(spacing: Space.sm) {
                MonoLabel("All day")
                Text(event.title).font(.style(.bodySmall)).foregroundStyle(Theme.ink).lineLimit(1)
                if !event.isBusy { MonoLabel("free") }
                Spacer()
            }
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xxs)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous))
        }
        if timed.isEmpty, let window = model.workingHours.interval(on: day, calendar: calendar) {
            Text(bounds.end <= now ? "Nothing was scheduled." :
                    "Nothing scheduled — open \(window.start.formatted(date: .omitted, time: .shortened))–\(window.end.formatted(date: .omitted, time: .shortened)).")
                .font(.style(.bodySmall))
                .foregroundStyle(Theme.inkSecondary)
                .padding(.vertical, Space.xxs)
        } else {
            ForEach(items) { item in
                switch item {
                case .event(let event): EventRow(event: event, day: bounds, now: now)
                case .open(let interval): OpenRow(interval: interval)
                }
            }
        }
    }

    private func problemView(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(problem).font(.style(.bodySmall)).foregroundStyle(Theme.inkSecondary)
            HStack(spacing: Space.sm) {
                if model.calendar.status == .needsReconnect {
                    Button("Reconnect…") { model.openConnections() }
                        .buttonStyle(KeyButtonStyle(kind: .primary, compact: true))
                } else {
                    Button("Try again") {
                        Task { try? await model.calendar.ensureLoaded(from: day, to: day, maxAge: 0) }
                    }
                    .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                }
            }
        }
        .padding(.vertical, Space.xxs)
    }
}

struct EventRow: View {
    let event: CalendarEvent
    let day: DateInterval
    let now: Date

    var body: some View {
        let past = event.end <= now
        let happening = event.start <= now && now < event.end
        HStack(alignment: .top, spacing: Space.sm) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(EventColor.color(for: event.colorID))
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    if happening { MonoLabel("Now", color: Theme.accent) }
                    Text(event.title)
                        .font(.style(.bodySmallEmphasis))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                }
                HStack(spacing: Space.xs) {
                    Text(timeText).font(.style(.monoValue)).foregroundStyle(Theme.inkSecondary)
                    MonoLabel(TodayView.duration(Int(event.duration / 60)))
                    if event.isRecurring { Image(systemName: "repeat").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.inkTertiary) }
                    if !event.isBusy { MonoLabel("free") }
                }
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.style(.caption)).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: Space.xs)
            if let link = event.meetingLink, !past {
                Button("Join") { NSWorkspace.shared.open(link) }
                    .buttonStyle(KeyButtonStyle(kind: happening ? .primary : .secondary, compact: true))
                    .help(link.absoluteString)
            }
        }
        .padding(.vertical, Space.xxs)
        .opacity(past ? 0.5 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.title), \(timeText)\(happening ? ", happening now" : "")")
    }

    /// Times, noting when an event runs in from the day before or on past midnight.
    private var timeText: String {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        let from = event.start < day.start ? "← \(time(event.start))" : time(event.start)
        let until = event.end > day.end ? "\(time(event.end)) →" : time(event.end)
        return "\(from)–\(until)"
    }
}

private struct OpenRow: View {
    let interval: DateInterval

    var body: some View {
        HStack(spacing: Space.sm) {
            MonoLabel("Open", color: Theme.ink)
            Text("\(interval.start.formatted(date: .omitted, time: .shortened))–\(interval.end.formatted(date: .omitted, time: .shortened))")
                .font(.style(.monoValue))
                .foregroundStyle(Theme.inkSecondary)
            MonoLabel(TodayView.duration(Int(interval.duration / 60)))
            Spacer()
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, Space.xxs)
        .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous)
            .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Open from \(interval.start.formatted(date: .omitted, time: .shortened)) to \(interval.end.formatted(date: .omitted, time: .shortened))")
    }
}

/// Google Calendar's event colours (colorId 1–11). Events without one use a neutral ink.
enum EventColor {
    static func color(for id: String?) -> Color {
        switch id {
        case "1": Color(hex: 0x7986CB)
        case "2": Color(hex: 0x33B679)
        case "3": Color(hex: 0x8E24AA)
        case "4": Color(hex: 0xE67C73)
        case "5": Color(hex: 0xF6BF26)
        case "6": Color(hex: 0xF4511E)
        case "7": Color(hex: 0x039BE5)
        case "8": Color(hex: 0x616161)
        case "9": Color(hex: 0x3F51B5)
        case "10": Color(hex: 0x0B8043)
        case "11": Color(hex: 0xD50000)
        default: Theme.inkSecondary
        }
    }
}
