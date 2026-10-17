#if DEBUG
import AppKit
import SwiftUI
import BuddyCore
import BuddyIntegrations

/// EXPERIMENT — renders every Editorial Orange state to PNG, next to the real panel in the
/// same state, for design review. In-memory sample data only (never your tasks or accounts):
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --editorial-orange-snapshots ~/Desktop/eo
///
/// (Run an unsandboxed build, or pass a folder inside the app's container.)
enum EditorialOrangeSnapshots {
    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let connected = connectedModel()
        shoot(EOPanelView(model: connected), "eo-today", folder)
        shoot(PanelRootView(model: connected), "prod-today", folder, editorial: false)
        shoot(EOPanelView(model: connected, expandedEventID: "1"), "eo-today-event-open", folder, height: 1900)

        // A long scroll of the whole Today page, to review everything below the fold.
        shoot(EOPanelView(model: connected), "eo-today-full", folder, height: 1900)

        let week = connectedModel()
        let sample = sampleWeek(model: week)
        week.calendar.loadPreview(events: sample.events, account: "keefer@example.com")
        week.showScheduleDay(sample.busyDay)
        week.scheduleExpanded = true
        shoot(EOPanelView(model: week, expandedEventID: "review"), "eo-week", folder, height: 1500)

        let empty = AppModel(preview: true)
        shoot(EOPanelView(model: empty), "eo-today-empty", folder)
        shoot(PanelRootView(model: empty), "prod-today-empty", folder, editorial: false)

        let editing = connectedModel()
        editing.editingTaskID = editing.tasks.today().first(where: { $0.title.hasPrefix("Take Coco") })?.id
        shoot(EOPanelView(model: editing), "eo-editor", folder)
        shoot(PanelRootView(model: editing), "prod-editor", folder, editorial: false)

        let review = demoModel()
        review.taskDrafts = TaskSplitter.split("I need to finish the homepage, review three portfolio projects for about an hour, and send two emails today")
            .map(AppModel.TaskDraft.init)
        review.speak(BuddyVoice.heardTasks(review.taskDrafts.count), .acknowledge)
        shoot(EOPanelView(model: review), "eo-voice-review", folder)
        shoot(PanelRootView(model: review), "prod-voice-review", folder, editorial: false)

        let focus = connectedModel()
        shoot(EOPanelView(model: focus, section: .focus), "eo-focus", folder)
        focus.panelTab = .focus
        shoot(PanelRootView(model: focus), "prod-focus", folder, editorial: false)
        // Running: started and stopped straight after the picture, so no session-end
        // notification is left scheduled.
        focus.startSelectedPhase()
        shoot(EOPanelView(model: focus, section: .focus), "eo-focus-running", folder)
        focus.focus.stop()

        let chatting = demoModel()
        var reply = AssistantService.Turn(role: .coco, text: "Your 1:1 with Sam is at 2. Before then you've got a clean 90 minutes — I'd spend it on the homepage hero, since it's your only high-priority task. Want me to start a focus session on it?")
        reply.activities = ["Looked at your tasks and calendar"]
        var proposal = AssistantService.Turn(role: .coco, text: "Here's a first pass at breaking it down. Tweak anything before adding.")
        proposal.activities = ["Suggested 3 tasks — review below"]
        chatting.assistant.loadPreview([
            AssistantService.Turn(role: .user, text: "What should I do before my 1:1?"),
            reply,
            AssistantService.Turn(role: .user, text: "Break the hero into steps"),
            proposal,
        ], cost: 0.018)
        chatting.taskDrafts = [
            QuickAddParser.Result(title: "Sketch three hero layouts", estimateMinutes: 30),
            QuickAddParser.Result(title: "Write headline options", estimateMinutes: 20),
            QuickAddParser.Result(title: "Build the chosen layout", priority: .high, estimateMinutes: 45),
        ].map(AppModel.TaskDraft.init)
        chatting.setDraftOriginForPreview(.chat)
        shoot(EOPanelView(model: chatting, section: .chat), "eo-chat", folder, height: 1200)
        chatting.panelTab = .chat
        shoot(PanelRootView(model: chatting), "prod-chat", folder, editorial: false)

        let asking = connectedModel()
        asking.calendar.loadPreview(events: sample.events, account: "keefer@example.com")
        var found = AssistantService.Turn(role: .coco, text: "Tuesday afternoon is tight — your portfolio critique runs 2 to 3:30. 2:00 overlaps it; 3:30 is the first clear hour. Here's 2:00 as you asked:")
        found.activities = ["Looked at your calendar for Tue", "Suggested adding “Design review” — confirm below"]
        asking.assistant.loadPreview([AssistantService.Turn(role: .user, text: "Schedule a design review Tuesday at 2"), found], cost: 0.011)
        asking.loadPreviewEventRequests([AppModel.EventRequest(
            kind: .create(EventDraft(title: "Design review", start: sample.busyDay.addingTimeInterval(14 * 3600),
                                     end: sample.busyDay.addingTimeInterval(15 * 3600))),
            conflicts: sample.events.filter { $0.id == "critique" })])
        shoot(EOPanelView(model: asking, section: .chat), "eo-chat-event", folder)

        let starters = demoModel()
        starters.assistant.loadPreview([], cost: 0)
        shoot(EOPanelView(model: starters, section: .chat), "eo-chat-starters", folder)
        shoot(EOPanelView(model: AppModel(preview: true), section: .chat), "eo-chat-needs-key", folder)

        shoot(EOPanelView(model: connected, section: .system), "eo-system", folder)
        shoot(EOPanelView(model: AppModel(preview: true), section: .system), "eo-system-setup", folder)

        compare(folder, pairs: ["today", "focus", "chat", "editor", "voice-review"])
        print("Editorial Orange snapshots written to \(folder.path)")
    }

    // MARK: - Sample data (same sample as the real snapshot sheet)

    static func demoModel() -> AppModel {
        let model = AppModel(preview: true)
        for line in ["Finish homepage hero ~90m !!!", "Review three portfolio projects ~45m !!",
                     "Send two emails ~15m", "Take Coco to the park ~30m !", "Book dentist"] {
            model.addTask(line)
        }
        if let first = model.tasks.today().first(where: { $0.title.hasPrefix("Send") }) {
            model.toggleTask(first.id)
        }
        if let hero = model.tasks.today().first {
            model.focus.selectTask(hero.id)
        }
        let today = Calendar.current.startOfDay(for: .now)
        if let review = model.tasks.today().first(where: { $0.title.hasPrefix("Review") }) {
            model.tasks.update(review.id) { $0.deadline = today }
        }
        if let park = model.tasks.today().first(where: { $0.title.hasPrefix("Take Coco") }) {
            model.tasks.update(park.id) {
                $0.deadline = Calendar.current.date(byAdding: .day, value: 3, to: today)
                $0.notes = "The big field, not the small one."
            }
        }
        model.focusLog.record(taskID: nil, seconds: 25 * 60, finished: true)
        model.focusLog.record(taskID: nil, seconds: 20 * 60, finished: false)
        model.speak("Good morning. Tail's wagging — what are we working on?", .ambient)
        return model
    }

    /// Google Calendar and Apple Calendar connected, with one meeting in both (shown once).
    static func connectedModel() -> AppModel {
        let model = demoModel()
        let day = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        model.calendar.loadPreview(events: [
            CalendarEvent(id: "1", title: "Design review", start: Date.now.addingTimeInterval(18 * 60),
                          end: Date.now.addingTimeInterval(48 * 60), location: "Studio B",
                          meetingLink: URL(string: "https://meet.google.com/abc")),
            CalendarEvent(id: "2", title: "1:1 with Sam", start: Date.now.addingTimeInterval(5 * 3600),
                          end: Date.now.addingTimeInterval(5.5 * 3600)),
            CalendarEvent(id: "0", title: "Standup", start: Date.now.addingTimeInterval(-90 * 60),
                          end: Date.now.addingTimeInterval(-75 * 60), isRecurring: true),
            CalendarEvent(id: "3", title: "Portfolio critique", start: at(24 * 2 + 14), end: at(24 * 2 + 15.5)),
        ], account: "keefer@example.com")
        let work = AppleCalendarInfo(id: "work", title: "Work", account: "Google", color: "#1BADF8", kind: .calDAV, isWritable: true)
        let home = AppleCalendarInfo(id: "home", title: "Home", account: "iCloud", color: "#63DA38", kind: .calDAV, isWritable: true)
        model.appleCalendar.loadPreview(calendars: [work, home], events: [
            CalendarEvent(id: "apple:r", title: "Design Review", start: Date.now.addingTimeInterval(18 * 60),
                          end: Date.now.addingTimeInterval(48 * 60), colorID: work.color, canEdit: false, provider: .apple,
                          calendarID: work.id, calendarName: work.title),
            CalendarEvent(id: "apple:d", title: "Dentist", start: Date.now.addingTimeInterval(2.5 * 3600),
                          end: Date.now.addingTimeInterval(3.25 * 3600), location: "Dr. Patel, 22 Court St", colorID: home.color,
                          canEdit: false, provider: .apple, calendarID: home.id, calendarName: home.title),
            CalendarEvent(id: "apple:l", title: "Lunch with Ana", start: at(24 + 12.5), end: at(24 + 13.5), colorID: home.color,
                          canEdit: false, provider: .apple, calendarID: home.id, calendarName: home.title),
        ])
        return model
    }

    static func sampleWeek(model: AppModel) -> (events: [CalendarEvent], busyDay: Date, quietDay: Date) {
        let calendar = Calendar.current
        let start = model.calendar.weekStart(for: .now)
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: start)! }
        func at(_ offset: Int, _ hour: Double) -> Date { day(offset).addingTimeInterval(hour * 3600) }
        var events: [CalendarEvent] = (0..<5).map { offset in
            CalendarEvent(id: "standup\(offset)", title: "Standup", start: at(offset, 9), end: at(offset, 9.25), colorID: "7", isRecurring: true)
        }
        events += [
            CalendarEvent(id: "lunch", title: "Lunch with Ana", start: at(0, 12.5), end: at(0, 13.5), location: "Café Lou"),
            CalendarEvent(id: "review", title: "Design review", start: at(1, 10), end: at(1, 11),
                          meetingLink: URL(string: "https://meet.google.com/abc"), colorID: "5"),
            CalendarEvent(id: "client", title: "Client call", start: at(1, 11), end: at(1, 12)),
            CalendarEvent(id: "critique", title: "Portfolio critique", start: at(1, 14), end: at(1, 15.5), canEdit: false),
            CalendarEvent(id: "prep", title: "Offsite prep", start: day(2), end: day(3), isAllDay: true, isBusy: false),
            CalendarEvent(id: "sam", title: "1:1 with Sam", start: at(2, 15), end: at(2, 16), colorID: "2"),
            CalendarEvent(id: "workshop", title: "Brand workshop", start: at(3, 9.5), end: at(3, 17.5), location: "Studio B", colorID: "3"),
            CalendarEvent(id: "park", title: "Park with Coco", start: at(6, 10), end: at(6, 11), colorID: "10"),
        ]
        return (events, day(1), day(5))
    }

    // MARK: - Rendering

    private static func shoot<Content: View>(_ content: Content, _ name: String, _ folder: URL,
                                             editorial: Bool = true, height: CGFloat = EO.pageSize.height) {
        let view: AnyView = editorial
            ? AnyView(content.frame(width: EO.pageSize.width, height: height).environment(\.eoStill, true))
            : AnyView(content)
        write(render(view, background: editorial ? NSColor(hex: 0xF5F4EE) : NSColor(hex: 0xD9E0E6)),
              to: folder.appendingPathComponent(name + ".png"))
    }

    static func render(_ content: AnyView, background: NSColor) -> NSImage {
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: hosting.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = background
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let bounds = hosting.bounds
        let rep = hosting.bitmapImageRepForCachingDisplay(in: bounds)!
        hosting.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// The real panel and the experiment, side by side at the same scale.
    private static func compare(_ folder: URL, pairs: [String]) {
        for name in pairs {
            guard let prod = NSImage(contentsOf: folder.appendingPathComponent("prod-\(name).png")),
                  let eo = NSImage(contentsOf: folder.appendingPathComponent("eo-\(name).png")) else { continue }
            let gap: CGFloat = 40
            let size = NSSize(width: prod.size.width + eo.size.width + gap * 3, height: max(prod.size.height, eo.size.height) + gap * 2 + 24)
            let sheet = NSImage(size: size, flipped: false) { rect in
                NSColor(hex: 0xE4E2DA).setFill()
                rect.fill()
                prod.draw(in: NSRect(x: gap, y: size.height - gap - 24 - prod.size.height, width: prod.size.width, height: prod.size.height))
                eo.draw(in: NSRect(x: gap * 2 + prod.size.width, y: size.height - gap - 24 - eo.size.height, width: eo.size.width, height: eo.size.height))
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold),
                                                                 .foregroundColor: NSColor(hex: 0x1A1A1A)]
                ("CURRENT — " + name.uppercased() as NSString).draw(at: NSPoint(x: gap, y: size.height - gap), withAttributes: attributes)
                ("EXPERIMENT — EDITORIAL ORANGE" as NSString).draw(at: NSPoint(x: gap * 2 + prod.size.width, y: size.height - gap), withAttributes: attributes)
                return true
            }
            write(sheet, to: folder.appendingPathComponent("compare-\(name).png"))
        }
    }

    static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
#endif
