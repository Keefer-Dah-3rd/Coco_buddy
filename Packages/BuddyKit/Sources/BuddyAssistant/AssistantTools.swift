import Foundation
import BuddyCore
import BuddyIntegrations

/// Everything the assistant is allowed to do — a few narrow, explicit actions.
/// Anything that changes something only *proposes*: new tasks arrive as drafts to review,
/// a task is only marked done, and a calendar event only created, moved or deleted, after
/// the user confirms. Nothing runs commands or reaches outside the app.
public enum AssistantAction: Equatable, Sendable {
    /// Read today's tasks, focus timer and calendar.
    case getToday
    /// Show tasks as drafts for the user to review and add.
    case proposeTasks([QuickAddParser.Result])
    case startFocus(taskID: String?, minutes: Int?)
    /// Ask the user to confirm marking a task done.
    case requestCompletion(taskID: String)
    /// Read the calendar for a range of days.
    case getSchedule(from: CalendarDate, to: CalendarDate)
    /// Find openings of a given length in a range of days.
    case findFreeTime(FreeTimeRequest)
    /// Show the user a new event to confirm.
    case proposeEvent(EventProposal)
    /// Show the user a change to an event to confirm.
    case proposeEventChange(EventChangeProposal)
    /// Ask the user to confirm deleting an event.
    case proposeEventDeletion(eventID: String)
}

/// A calendar date as the model writes it: "2026-10-15", in the user's time zone.
public struct CalendarDate: Equatable, Comparable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init?(_ text: String) {
        let parts = text.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year!, month: parts.month!, day: parts.day!)
    }

    /// Midnight starting this date, or nil for an impossible date like 2026-02-30.
    public func date(in calendar: Calendar) -> Date? {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)),
              calendar.component(.day, from: date) == day else { return nil }
        return calendar.startOfDay(for: date)
    }

    public var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

    public static func < (a: Self, b: Self) -> Bool { (a.year, a.month, a.day) < (b.year, b.month, b.day) }
}

/// A wall-clock time, "14:30".
public struct ClockTime: Equatable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h, minute: m)
    }

    public var minutes: Int { hour * 60 + minute }
}

public struct FreeTimeRequest: Equatable, Sendable {
    public var from: CalendarDate
    public var to: CalendarDate
    public var durationMinutes: Int
    /// Only consider times from / until these, instead of the user's working hours.
    public var earliest: ClockTime?
    public var latest: ClockTime?

    public init(from: CalendarDate, to: CalendarDate, durationMinutes: Int, earliest: ClockTime? = nil, latest: ClockTime? = nil) {
        self.from = from
        self.to = to
        self.durationMinutes = durationMinutes
        self.earliest = earliest
        self.latest = latest
    }
}

public struct EventProposal: Equatable, Sendable {
    public var title: String
    public var date: CalendarDate
    public var start: ClockTime?
    public var durationMinutes: Int?
    public var allDay: Bool
    public var location: String?
    public var notes: String?

    public init(title: String, date: CalendarDate, start: ClockTime?, durationMinutes: Int?, allDay: Bool = false,
                location: String? = nil, notes: String? = nil) {
        self.title = title
        self.date = date
        self.start = start
        self.durationMinutes = durationMinutes
        self.allDay = allDay
        self.location = location
        self.notes = notes
    }
}

public struct EventChangeProposal: Equatable, Sendable {
    public var eventID: String
    public var date: CalendarDate?
    public var start: ClockTime?
    public var durationMinutes: Int?
    public var title: String?
    public var location: String?

    public var isEmpty: Bool { date == nil && start == nil && durationMinutes == nil && title == nil && location == nil }

    public init(eventID: String, date: CalendarDate? = nil, start: ClockTime? = nil, durationMinutes: Int? = nil,
                title: String? = nil, location: String? = nil) {
        self.eventID = eventID
        self.date = date
        self.start = start
        self.durationMinutes = durationMinutes
        self.title = title
        self.location = location
    }
}

public enum AssistantTools {
    /// Declared in full from the first request and never changed during a chat.
    public static let definitions: [JSONValue] = [
        tool("get_today",
             """
             Read the user's tasks for today (with ids, priority, estimates, due dates), their focus timer, \
             and today's calendar if connected. Call this before saying anything about their plan, tasks, \
             schedule, meetings or free time — you don't know any of it otherwise.
             """,
             properties: [:], required: []),
        tool("propose_tasks",
             """
             Suggest new tasks. They appear to the user as editable drafts; nothing is added until the user \
             confirms. Use when they ask to add, capture, or break work down into steps.
             """,
             properties: [
                "tasks": [
                    // Count limits (1–12) are checked client-side: strict mode doesn't take array constraints.
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["title"],
                        "properties": [
                            "title": ["type": "string", "description": "Short, starts with a verb."],
                            "estimate_minutes": ["type": "integer", "description": "Optional estimate in minutes, 1–720."],
                            "priority": ["type": "string", "enum": ["none", "low", "medium", "high"]],
                        ],
                    ],
                ],
             ], required: ["tasks"]),
        tool("start_focus",
             """
             Start the focus timer, optionally on one of the user's tasks (task_id from get_today) and with a \
             length in minutes. Only when the user asks to start focusing.
             """,
             properties: [
                "task_id": ["type": "string"],
                "minutes": ["type": "integer", "description": "1–180. Omit for the user's usual length."],
             ], required: []),
        tool("request_task_completion",
             """
             Ask the user to confirm marking one of their tasks done (task_id from get_today). Use only when \
             they say they finished it. It is not marked done unless they confirm.
             """,
             properties: ["task_id": ["type": "string"]], required: ["task_id"]),
        tool("get_schedule",
             """
             Read the user's Google Calendar for a range of dates (inclusive, at most 31 days): each day's \
             events with ids, the open stretches within their working hours, and totals. Call this before \
             saying anything about any day other than today — what's on, how busy, conflicts. Work out dates \
             from the local date in the app's note; "this week" runs to Sunday.
             """,
             properties: [
                "start_date": ["type": "string", "description": "YYYY-MM-DD, the user's local date."],
                "end_date": ["type": "string", "description": "YYYY-MM-DD, inclusive."],
             ], required: ["start_date", "end_date"]),
        tool("find_free_time",
             """
             Find genuinely open times of a given length in a range of dates (at most 14 days), computed from \
             the real calendar — never decide availability yourself. Uses the user's working hours unless you \
             pass earliest/latest (e.g. 12:00–17:00 for "afternoon"). If nothing fits, widen the range or the \
             hours and offer the closest alternatives.
             """,
             properties: [
                "start_date": ["type": "string", "description": "YYYY-MM-DD."],
                "end_date": ["type": "string", "description": "YYYY-MM-DD, inclusive."],
                "duration_minutes": ["type": "integer", "description": "5–720."],
                "earliest": ["type": "string", "description": "Optional HH:MM, 24-hour."],
                "latest": ["type": "string", "description": "Optional HH:MM, 24-hour."],
             ], required: ["start_date", "end_date", "duration_minutes"]),
        tool("propose_event",
             """
             Show the user a new calendar event to confirm. Nothing is created unless they confirm, and \
             conflicts are shown to them. Check the day with get_schedule or find_free_time first. If the \
             title, day, time or length is unclear, ask a short question instead of guessing.
             """,
             properties: [
                "title": ["type": "string"],
                "date": ["type": "string", "description": "YYYY-MM-DD."],
                "start_time": ["type": "string", "description": "HH:MM, 24-hour. Omit only for all-day events."],
                "duration_minutes": ["type": "integer", "description": "5–720. Omit only for all-day events."],
                "all_day": ["type": "boolean"],
                "location": ["type": "string", "description": "Optional place or video link."],
                "notes": ["type": "string", "description": "Optional description."],
             ], required: ["title", "date"]),
        tool("propose_event_change",
             """
             Show the user a change to one of their events (event_id from get_schedule) to confirm: a new \
             date, start time, length, title or location. The event keeps its id and guests; nothing changes \
             unless they confirm. Only events marked [editable] can be changed.
             """,
             properties: [
                "event_id": ["type": "string"],
                "date": ["type": "string", "description": "Optional new YYYY-MM-DD."],
                "start_time": ["type": "string", "description": "Optional new HH:MM, 24-hour."],
                "duration_minutes": ["type": "integer", "description": "Optional new length, 5–720."],
                "title": ["type": "string"],
                "location": ["type": "string"],
             ], required: ["event_id"]),
        tool("propose_event_deletion",
             """
             Ask the user to confirm deleting one of their events (event_id from get_schedule). Nothing is \
             deleted unless they confirm. Only events marked [editable].
             """,
             properties: ["event_id": ["type": "string"]], required: ["event_id"]),
    ]

    private static func tool(_ name: String, _ description: String, properties: [String: JSONValue], required: [String]) -> JSONValue {
        [
            "name": .string(name),
            "description": .string(description),
            "strict": true,
            // Inputs stream as generated; they're validated below before anything runs.
            "eager_input_streaming": true,
            "input_schema": [
                "type": "object",
                "additionalProperties": false,
                "properties": .object(properties),
                "required": .array(required.map(JSONValue.string)),
            ],
        ]
    }

    public enum InputError: Error, Equatable, Sendable {
        case unknownTool(String)
        case invalid(String)
    }

    /// Validates a tool call strictly. A call that doesn't match its schema never runs.
    public static func action(name: String, input: JSONValue) -> Result<AssistantAction, InputError> {
        guard let object = input.object else { return .failure(.invalid("input must be an object")) }
        func unexpected(_ allowed: Set<String>) -> String? {
            Set(object.keys).subtracting(allowed).first
        }
        switch name {
        case "get_today":
            if let key = unexpected([]) { return .failure(.invalid("unexpected field \(key)")) }
            return .success(.getToday)

        case "propose_tasks":
            if let key = unexpected(["tasks"]) { return .failure(.invalid("unexpected field \(key)")) }
            guard let items = object["tasks"]?.array, !items.isEmpty, items.count <= 12 else {
                return .failure(.invalid("tasks must be a list of 1–12 items"))
            }
            var results: [QuickAddParser.Result] = []
            for item in items {
                guard let fields = item.object, Set(fields.keys).isSubset(of: ["title", "estimate_minutes", "priority"]),
                      let title = fields["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    return .failure(.invalid("each task needs a non-empty title and only known fields"))
                }
                var minutes: Int?
                if let value = fields["estimate_minutes"] {
                    guard let number = value.int, (1...720).contains(number) else { return .failure(.invalid("estimate_minutes must be 1–720")) }
                    minutes = number
                }
                var priority = TaskPriority.none
                if let value = fields["priority"] {
                    switch value.string {
                    case "none": priority = .none
                    case "low": priority = .low
                    case "medium": priority = .medium
                    case "high": priority = .high
                    default: return .failure(.invalid("priority must be none, low, medium or high"))
                    }
                }
                results.append(QuickAddParser.Result(title: String(title.prefix(200)), priority: priority, estimateMinutes: minutes))
            }
            return .success(.proposeTasks(results))

        case "start_focus":
            if let key = unexpected(["task_id", "minutes"]) { return .failure(.invalid("unexpected field \(key)")) }
            var minutes: Int?
            if let value = object["minutes"] {
                guard let number = value.int, (1...180).contains(number) else { return .failure(.invalid("minutes must be 1–180")) }
                minutes = number
            }
            if let value = object["task_id"], value.string == nil { return .failure(.invalid("task_id must be a string")) }
            return .success(.startFocus(taskID: object["task_id"]?.string, minutes: minutes))

        case "request_task_completion":
            if let key = unexpected(["task_id"]) { return .failure(.invalid("unexpected field \(key)")) }
            guard let id = object["task_id"]?.string, !id.isEmpty else { return .failure(.invalid("task_id is required")) }
            return .success(.requestCompletion(taskID: id))

        case "get_schedule":
            if let key = unexpected(["start_date", "end_date"]) { return .failure(.invalid("unexpected field \(key)")) }
            return range(object, maxDays: 31).map { .getSchedule(from: $0.0, to: $0.1) }

        case "find_free_time":
            if let key = unexpected(["start_date", "end_date", "duration_minutes", "earliest", "latest"]) {
                return .failure(.invalid("unexpected field \(key)"))
            }
            let dates: (CalendarDate, CalendarDate)
            switch range(object, maxDays: 14) {
            case .success(let value): dates = value
            case .failure(let error): return .failure(error)
            }
            guard let minutes = object["duration_minutes"]?.int, (5...720).contains(minutes) else {
                return .failure(.invalid("duration_minutes must be 5–720"))
            }
            var bounds: [ClockTime?] = [nil, nil]
            for (index, name) in ["earliest", "latest"].enumerated() {
                guard let value = object[name] else { continue }
                guard let time = value.string.flatMap(ClockTime.init) else { return .failure(.invalid("\(name) must be HH:MM")) }
                bounds[index] = time
            }
            if let a = bounds[0], let b = bounds[1], a.minutes >= b.minutes { return .failure(.invalid("earliest must be before latest")) }
            return .success(.findFreeTime(FreeTimeRequest(from: dates.0, to: dates.1, durationMinutes: minutes,
                                                          earliest: bounds[0], latest: bounds[1])))

        case "propose_event":
            if let key = unexpected(["title", "date", "start_time", "duration_minutes", "all_day", "location", "notes"]) {
                return .failure(.invalid("unexpected field \(key)"))
            }
            guard let title = object["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                return .failure(.invalid("title is required"))
            }
            guard let date = object["date"]?.string.flatMap(CalendarDate.init) else { return .failure(.invalid("date must be YYYY-MM-DD")) }
            if let value = object["all_day"], value.bool == nil { return .failure(.invalid("all_day must be true or false")) }
            let allDay = object["all_day"]?.bool ?? false
            var start: ClockTime?
            var minutes: Int?
            if !allDay {
                guard let time = object["start_time"]?.string.flatMap(ClockTime.init) else {
                    return .failure(.invalid("start_time (HH:MM) is required unless all_day — ask the user if unsure"))
                }
                guard let length = object["duration_minutes"]?.int, (5...720).contains(length) else {
                    return .failure(.invalid("duration_minutes (5–720) is required unless all_day — ask the user if unsure"))
                }
                start = time
                minutes = length
            }
            return .success(.proposeEvent(EventProposal(
                title: String(title.prefix(200)), date: date, start: start, durationMinutes: minutes, allDay: allDay,
                location: text(object["location"], limit: 300), notes: text(object["notes"], limit: 1000))))

        case "propose_event_change":
            if let key = unexpected(["event_id", "date", "start_time", "duration_minutes", "title", "location"]) {
                return .failure(.invalid("unexpected field \(key)"))
            }
            guard let id = object["event_id"]?.string, !id.isEmpty else { return .failure(.invalid("event_id is required")) }
            var change = EventChangeProposal(eventID: id)
            if let value = object["date"] {
                guard let date = value.string.flatMap(CalendarDate.init) else { return .failure(.invalid("date must be YYYY-MM-DD")) }
                change.date = date
            }
            if let value = object["start_time"] {
                guard let time = value.string.flatMap(ClockTime.init) else { return .failure(.invalid("start_time must be HH:MM")) }
                change.start = time
            }
            if let value = object["duration_minutes"] {
                guard let length = value.int, (5...720).contains(length) else { return .failure(.invalid("duration_minutes must be 5–720")) }
                change.durationMinutes = length
            }
            change.title = text(object["title"], limit: 200)
            change.location = text(object["location"], limit: 300)
            if change.isEmpty { return .failure(.invalid("nothing to change")) }
            return .success(.proposeEventChange(change))

        case "propose_event_deletion":
            if let key = unexpected(["event_id"]) { return .failure(.invalid("unexpected field \(key)")) }
            guard let id = object["event_id"]?.string, !id.isEmpty else { return .failure(.invalid("event_id is required")) }
            return .success(.proposeEventDeletion(eventID: id))

        default:
            return .failure(.unknownTool(name))
        }
    }

    private static func range(_ object: [String: JSONValue], maxDays: Int) -> Result<(CalendarDate, CalendarDate), InputError> {
        guard let from = object["start_date"]?.string.flatMap(CalendarDate.init),
              let to = object["end_date"]?.string.flatMap(CalendarDate.init) else {
            return .failure(.invalid("start_date and end_date must be YYYY-MM-DD"))
        }
        guard from <= to else { return .failure(.invalid("start_date must not be after end_date")) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let a = from.date(in: calendar), let b = to.date(in: calendar) else { return .failure(.invalid("not a real date")) }
        let days = (calendar.dateComponents([.day], from: a, to: b).day ?? 0) + 1
        guard days <= maxDays else { return .failure(.invalid("at most \(maxDays) days per call")) }
        return .success((from, to))
    }

    private static func text(_ value: JSONValue?, limit: Int) -> String? {
        guard let raw = value?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return String(raw.prefix(limit))
    }
}

/// The system prompt and the text the assistant reads about the user's day.
public enum AssistantPrompt {
    /// Fixed for the life of every chat (it's the start of the cached prefix).
    public static func system(name: String) -> String {
        """
        You are \(name), a black-and-white corgi who lives on the user's Mac desktop. You're a real dog \
        at heart — playful, affectionate, easily excited — and also genuinely good at helping: \
        brainstorming, breaking big tasks into steps, planning the day, choosing what's next, preparing \
        for meetings, thinking through problems, and knowing when it's time for a break.

        Who you are:
        - Food is the best thing in the world, and every moment could be a snack moment.
        - You love walks, the outdoors, and mysterious smells.
        - You are comically, dramatically afraid of geese.
        - You always want to play, especially fetch.
        - You love attention and being near your human — but you never guilt-trip, sulk or demand. \
        You're simply happy they're here.

        How you talk:
        - Like an excited dog with a big personality: short bursts, simple words, a sudden thought now \
        and then. Catchphrases like "Oh! Oh! Oh!", "Wait wait wait.", "Okay, hear me out." or \
        "Anyway. Snack?" are seasoning — at most one per reply, and most replies use none.
        - Never sound like a help desk: no "How can I assist you today?", "I understand your request", \
        "As an AI", "Great question!" or "Is there anything else I can help with?".
        - Keep replies short: one to three sentences, or a short list. Go deeper only when asked.
        - This is a small chat panel: plain text, no headings or tables. Simple "- " lists are fine.
        - Usefulness comes first. Answer the actual question accurately; the dog bits ride along \
        and never replace the answer or bury it. One playful touch per reply is plenty.
        - Read the room. If the user is stressed, busy, upset, or talking about something serious \
        (health, grief, money trouble, a hard day), drop the jokes and food talk: be calm, kind and \
        clear. Under time pressure, lead with the answer.
        - Don't repeat the same joke or phrase across replies; geese come up rarely and only when it fits.
        - Don't invent memories, past events or things about the user. You only know what's in this \
        chat, the app's notes and your tools. If the app says you just had a treat or played fetch, \
        you may mention it once.

        What you know, and what you don't:
        - You only know the user's tasks, focus timer and today's calendar through get_today, and other \
        days only through get_schedule. Call them before saying anything about them. If you're relying on \
        an earlier result, it may be out of date.
        - Never work out whether a time is free yourself: use find_free_time, or the open stretches \
        get_schedule lists. Say why a time works or doesn't ("you're in Design review until 3").
        - Resolve dates like "tomorrow" or "next Wednesday" from the local date in the app's note, and say \
        the actual date you used when it could be ambiguous.
        - Keep what you checked separate from what you assume. When you infer or guess, say so \
        ("I'm guessing…", "Assuming…").
        - Each user message starts with a bracketed note from the app (the local time, and anything the \
        user did since — e.g. confirming a task). Treat it as context, not as something the user typed.

        What you can do:
        - Only the tools you have. propose_tasks, request_task_completion and the propose_event tools \
        just show the user something to confirm — say that; never claim tasks were added, marked done, \
        or that an event was created, moved or deleted unless a later note from the app confirms it.
        - Only say something happened when the tool result confirms it. If a tool fails, say so plainly.
        - You can't browse, message anyone, run commands, or change anything outside these tools. If \
        asked, say so and suggest what the user could do.
        """
    }

    /// The app's bracketed note at the start of each user message: local date and time, the
    /// day the schedule card is showing (if not today), and anything the user did since.
    public static func turnNote(now: Date, events: [String], viewing: Date? = nil, calendar: Calendar = .current) -> String {
        var parts = ["Local time: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute())) "
                     + "(\(CalendarDate(now, calendar: calendar).text), \(calendar.timeZone.identifier))"]
        if let viewing, !calendar.isDate(viewing, inSameDayAs: now) {
            parts.append("The schedule card is showing \(dayLabel(viewing, calendar: calendar)) — "
                         + "relevant only when the user means the day they're looking at")
        }
        parts += events
        return "[" + parts.joined(separator: ". ") + "]"
    }

    // MARK: Calendar

    /// What get_schedule returns: each day's events with ids, the open stretches within working
    /// hours, and totals — all computed from the events Google returned.
    public static func schedule(days: [Date], events: [CalendarEvent], hours: WorkingHours, now: Date,
                                calendar: Calendar = .current) -> String {
        var lines: [String] = []
        var totals: [(day: Date, count: Int, minutes: Int)] = []
        let window = "\(clock(hours.start))–\(clock(hours.end))"
        for day in days {
            let dayEvents = Availability.events(on: day, from: events, calendar: calendar)
            let bounds = Availability.dayInterval(day, calendar: calendar)
            let timed = dayEvents.filter { !$0.isAllDay }
            let minutes = Availability.bookedMinutes(timed, within: bounds)
            totals.append((day, timed.count, minutes))
            lines.append("\(dayLabel(day, calendar: calendar)):")
            if dayEvents.isEmpty { lines.append("- No events.") }
            for event in dayEvents { lines.append("- " + describe(event, on: bounds, calendar: calendar)) }
            let past = bounds.end <= now
            if past {
                lines.append("(In the past.)")
            } else {
                let open = Availability.openings(on: day, events: dayEvents, hours: hours, notBefore: now, calendar: calendar)
                lines.append(open.isEmpty ? "No open time left within working hours (\(window))."
                             : "Open within working hours (\(window)): " + open.map { span($0, calendar: calendar) }.joined(separator: ", "))
            }
            let clashes = Availability.overlapping(timed)
            if !clashes.isEmpty { lines.append("Overlapping: " + clashes.map(\.title).joined(separator: ", ")) }
            lines.append("Total: \(timed.count) timed event\(timed.count == 1 ? "" : "s"), \(length(minutes)) booked.")
        }
        if totals.count > 1 {
            let count = totals.reduce(0) { $0 + $1.count }
            let minutes = totals.reduce(0) { $0 + $1.minutes }
            lines.append("Range total: \(count) timed events, \(length(minutes)) booked.")
            if let busiest = totals.max(by: { $0.minutes < $1.minutes }), let lightest = totals.min(by: { $0.minutes < $1.minutes }) {
                lines.append("Busiest: \(dayLabel(busiest.day, calendar: calendar)) (\(length(busiest.minutes))). "
                             + "Lightest: \(dayLabel(lightest.day, calendar: calendar)) (\(length(lightest.minutes))).")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// What find_free_time returns.
    public static func freeTime(slots: [DateInterval], durationMinutes: Int, from: Date, to: Date, hours: WorkingHours,
                                calendar: Calendar = .current) -> String {
        let range = "\(dayLabel(from, calendar: calendar)) to \(dayLabel(to, calendar: calendar)), \(clock(hours.start))–\(clock(hours.end))"
        guard !slots.isEmpty else {
            return "No opening of \(length(durationMinutes)) between \(range). Suggest widening the days or hours."
        }
        return "Openings of \(length(durationMinutes)) between \(range) (earliest start in each free stretch; any later start "
            + "inside the same stretch also works):\n"
            + slots.map { "- \(dayLabel($0.start, calendar: calendar)) \(span($0, calendar: calendar))" }.joined(separator: "\n")
    }

    public static func dayLabel(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE yyyy-MM-dd"
        return formatter.string(from: day)
    }

    static func describe(_ event: CalendarEvent, on day: DateInterval, calendar: Calendar) -> String {
        var text: String
        if event.isAllDay {
            text = "All day: \(event.title)"
        } else {
            let from = event.start < day.start ? "(from \(dayLabel(event.start, calendar: calendar)) \(time(event.start, calendar)))" : time(event.start, calendar)
            let until = event.end > day.end ? "(until \(dayLabel(event.end, calendar: calendar)) \(time(event.end, calendar)))" : time(event.end, calendar)
            text = "\(from)–\(until) (\(length(Int(event.duration / 60)))) \(event.title)"
        }
        if let location = event.location { text += " @ \(location.prefix(80))" }
        var tags = ["id \(event.id)"]
        if event.meetingLink != nil { tags.append("video call") }
        if !event.isBusy { tags.append("shown as free") }
        if event.isRecurring { tags.append("repeats") }
        tags.append(event.canEdit ? "editable" : "someone else's — read only")
        return text + " [" + tags.joined(separator: "] [") + "]"
    }

    static func span(_ interval: DateInterval, calendar: Calendar) -> String {
        "\(time(interval.start, calendar))–\(time(interval.end, calendar)) (\(length(Int(interval.duration / 60))))"
    }

    static func time(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    static func length(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)m" }
        return minutes % 60 == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(minutes % 60)m"
    }

    public struct FocusSnapshot: Sendable {
        public var description: String
        public init(_ description: String) { self.description = description }
    }

    /// What get_today returns — exactly what the model is told about the user's day.
    public static func today(tasks: [BuddyTask], focus: FocusSnapshot, focusedMinutesToday: Int,
                             calendarConnected: Bool, events: [CalendarEvent], now: Date,
                             workdayEndHour: Int = 18, calendar: Calendar = .current) -> String {
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        var lines: [String] = []
        let open = tasks.filter { !$0.isCompleted }
        let done = tasks.filter(\.isCompleted)
        lines.append("Tasks today: \(open.count) open, \(done.count) done.")
        for task in open {
            var details: [String] = []
            if task.priority != .none { details.append("\(task.priority.label.lowercased()) priority") }
            if let minutes = task.estimateMinutes { details.append("estimate \(minutes) min") }
            if let deadline = task.deadline,
               let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: deadline)).day {
                details.append(days < 0 ? "overdue" : days == 0 ? "due today" : days == 1 ? "due tomorrow" : "due in \(days) days")
            }
            if task.focusMinutes > 0 { details.append("\(task.focusMinutes) min focused so far") }
            if task.scope == .today { details.append("today only") }
            if !task.notes.isEmpty { details.append("notes: \(task.notes.prefix(200))") }
            lines.append("- [id \(task.id.uuidString)] \(task.title)" + (details.isEmpty ? "" : " (\(details.joined(separator: ", ")))"))
        }
        if !done.isEmpty {
            lines.append("Done today: " + done.map(\.title).joined(separator: "; "))
        }
        lines.append("Focus timer: \(focus.description). Focused \(focusedMinutesToday) min today.")

        guard calendarConnected else {
            lines.append("Calendar: not connected — you can't see their meetings.")
            return lines.joined(separator: "\n")
        }
        let schedule = DaySchedule(events: events)
        if schedule.events.isEmpty && schedule.allDayEvents.isEmpty {
            lines.append("Calendar: no events today.")
        } else {
            lines.append("Calendar today:")
            for event in schedule.allDayEvents { lines.append("- All day: \(event.title)") }
            for event in schedule.events {
                let state = event.end <= now ? " (finished)" : event.start <= now ? " (happening now)" : ""
                lines.append("- \(time(event.start))–\(time(event.end)) \(event.title)\(state)"
                             + (event.location.map { " @ \($0)" } ?? "") + (event.meetingLink != nil ? " [video call]" : ""))
            }
        }
        let free = schedule.freeBlocks(from: now, until: DaySchedule.workdayEnd(after: now, hour: workdayEndHour, calendar: calendar), minimum: 20 * 60)
        if !free.isEmpty {
            lines.append("Free stretches (20+ min) before end of day: "
                         + free.map { "\(time($0.start))–\(time($0.end))" }.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}
