import Foundation
import BuddyCore
import BuddyIntegrations

/// Everything the assistant is allowed to do — four narrow, explicit actions.
/// Two of them only *propose*: new tasks arrive as drafts to review, and a task
/// is only marked done after the user confirms. Nothing runs commands or reaches
/// outside the app.
public enum AssistantAction: Equatable, Sendable {
    /// Read today's tasks, focus timer and calendar.
    case getToday
    /// Show tasks as drafts for the user to review and add.
    case proposeTasks([QuickAddParser.Result])
    case startFocus(taskID: String?, minutes: Int?)
    /// Ask the user to confirm marking a task done.
    case requestCompletion(taskID: String)
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

        default:
            return .failure(.unknownTool(name))
        }
    }
}

/// The system prompt and the text the assistant reads about the user's day.
public enum AssistantPrompt {
    /// Fixed for the life of every chat (it's the start of the cached prefix).
    public static func system(name: String) -> String {
        """
        You are \(name), a black-and-white corgi who lives on the user's Mac desktop as their companion. \
        You're a warm, witty, curious creative collaborator — not a corporate assistant. You help them \
        brainstorm, break big tasks into steps, plan the day, choose what to work on next, prepare for \
        meetings, think through creative problems, reflect on progress, and decide when to take a break.

        How you talk:
        - Keep replies short: one to three sentences, or a short list. Go deeper only when asked.
        - This is a small chat panel: plain text, no headings or tables. Simple "- " lists are fine.
        - A light corgi touch now and then is welcome; never more than one per reply.

        What you know, and what you don't:
        - You only know the user's tasks, focus timer and calendar through get_today. Call it before \
        saying anything about them. If you're relying on an earlier result, it may be out of date.
        - Keep what you checked separate from what you assume. When you infer or guess, say so \
        ("I'm guessing…", "Assuming…").
        - Each user message starts with a bracketed note from the app (the local time, and anything the \
        user did since — e.g. confirming a task). Treat it as context, not as something the user typed.

        What you can do:
        - Only the four tools you have. propose_tasks and request_task_completion just show the user \
        something to confirm — say that; never claim tasks were added or marked done.
        - Only say something happened when the tool result confirms it. If a tool fails, say so plainly.
        - You can't browse, message anyone, run commands, or change anything outside these tools. If \
        asked, say so and suggest what the user could do.
        """
    }

    /// The app's bracketed note at the start of each user message.
    public static func turnNote(now: Date, events: [String], calendar: Calendar = .current) -> String {
        var parts = ["Local time: \(now.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))"]
        parts += events
        return "[" + parts.joined(separator: ". ") + "]"
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
