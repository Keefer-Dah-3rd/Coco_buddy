#if DEBUG
import AppKit
import SwiftUI
import BuddyCharacter
import BuddyCore
import BuddyIntegrations

/// Renders the character in every state, plus the panel, to PNG files — a visual
/// regression sheet and design QA tool. Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --snapshots ~/Desktop/coco-snapshots
///
/// (Run an unsandboxed build, or pass a folder inside the app's container.)
enum SnapshotRenderer {
    static func run(into folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        renderIcon(to: folder.appendingPathComponent("icon-1024.png"))
        exportMascot(to: folder.appendingPathComponent("mascot"))
        RunPreview.exportTricks(to: folder.appendingPathComponent("mascot"))
        renderBubbleWindow(to: folder.appendingPathComponent("bubble-window.png"))
        write(callTargetSheet(), to: folder.appendingPathComponent("call-target.png"))
        for (name, background) in [("light", NSColor(hex: 0xD9E0E6)), ("dark", NSColor(hex: 0x1E252D))] {
            write(characterSheet(background: background), to: folder.appendingPathComponent("character-\(name).png"))
        }
        let model = demoModel()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            model.panelTab = .today
            write(view(PanelRootView(model: model), appearance: appearance), to: folder.appendingPathComponent("panel-today-\(name).png"))
            model.panelTab = .focus
            write(view(PanelRootView(model: model), appearance: appearance), to: folder.appendingPathComponent("panel-focus-\(name).png"))
            write(view(SpeechBubbleView(text: "Focusing on “Homepage hero”. I'll be quiet.", tail: .bottom, tailAnchor: 0.5)
                .padding(8), appearance: appearance), to: folder.appendingPathComponent("bubble-\(name).png"))
        }
        let review = demoModel()
        review.taskDrafts = TaskSplitter.split("I need to finish the homepage, review three portfolio projects for about an hour, and send two emails today")
            .map(AppModel.TaskDraft.init)
        review.speak(BuddyVoice.heardTasks(review.taskDrafts.count), .acknowledge)
        write(view(PanelRootView(model: review), appearance: .aqua), to: folder.appendingPathComponent("panel-voice-review.png"))

        let glyph = NSImage(size: NSSize(width: 144, height: 128), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            BuddyGlyph.menuBar.draw(in: rect)
            return true
        }
        write(glyph, to: folder.appendingPathComponent("menubar-glyph.png"))

        let connected = demoModel()
        let day = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date { day.addingTimeInterval(hour * 3600) }
        connected.calendar.loadPreview(events: [
            CalendarEvent(id: "1", title: "Design review", start: Date.now.addingTimeInterval(18 * 60),
                          end: Date.now.addingTimeInterval(48 * 60), meetingLink: URL(string: "https://meet.google.com/abc")),
            CalendarEvent(id: "2", title: "1:1 with Sam", start: Date.now.addingTimeInterval(5 * 3600),
                          end: Date.now.addingTimeInterval(5.5 * 3600)),
            CalendarEvent(id: "3", title: "Portfolio critique", start: at(24 * 2 + 14), end: at(24 * 2 + 15.5)),
        ], account: "keefer@example.com")
        // Apple Calendar too: a copy of the design review (shown once) and events of its own.
        let work = AppleCalendarInfo(id: "work", title: "Work", account: "Google", color: "#1BADF8", kind: .calDAV, isWritable: true)
        let home = AppleCalendarInfo(id: "home", title: "Home", account: "iCloud", color: "#63DA38", kind: .calDAV, isWritable: true)
        let birthdays = AppleCalendarInfo(id: "birthdays", title: "Birthdays", account: "Other", kind: .birthdays, isWritable: false)
        connected.appleCalendar.loadPreview(calendars: [work, home, birthdays], events: [
            CalendarEvent(id: "apple:r", title: "Design Review", start: Date.now.addingTimeInterval(18 * 60),
                          end: Date.now.addingTimeInterval(48 * 60), colorID: work.color, canEdit: false, provider: .apple,
                          calendarID: work.id, calendarName: work.title),
            CalendarEvent(id: "apple:d", title: "Dentist", start: Date.now.addingTimeInterval(2.5 * 3600),
                          end: Date.now.addingTimeInterval(3.25 * 3600), location: "Dr. Patel, 22 Court St", colorID: home.color,
                          canEdit: false, provider: .apple, calendarID: home.id, calendarName: home.title),
            CalendarEvent(id: "apple:l", title: "Lunch with Ana", start: at(24 + 12.5), end: at(24 + 13.5), colorID: home.color,
                          canEdit: false, provider: .apple, calendarID: home.id, calendarName: home.title),
        ])
        connected.notion.loadPreview(
            mapping: NotionMapping(dataSourceID: "ds", dataSourceTitle: "Portfolio tasks", titleProperty: "Name"),
            tasks: [
                NotionTask(id: "n1", title: "Write case study intro", isDone: false, due: at(12), priority: .high),
                NotionTask(id: "n2", title: "Export hero renders", isDone: false, due: nil, priority: .none),
                NotionTask(id: "n3", title: "Email the printer", isDone: false, due: at(24 * 3), priority: .low),
            ],
            workspace: "Keefer's Notion")
        write(view(PanelRootView(model: connected), appearance: .aqua), to: folder.appendingPathComponent("panel-connected.png"))

        // Signed in to Google, but today hasn't arrived yet: "Loading today…", not "wide open".
        let loading = demoModel()
        loading.calendar.loadTestSignIn(canChangeEvents: false)
        write(view(PanelRootView(model: loading), appearance: .aqua), to: folder.appendingPathComponent("panel-calendar-loading.png"))

        // The week browser, with a sample week (snapshots only).
        let week = demoModel()
        let sample = sampleWeek(model: week)
        week.calendar.loadPreview(events: sample.events, account: "keefer@example.com")
        week.showScheduleDay(sample.busyDay)
        week.scheduleExpanded = true
        write(view(PanelRootView(model: week), appearance: .aqua), to: folder.appendingPathComponent("panel-week.png"))
        week.showScheduleDay(sample.quietDay)
        write(view(PanelRootView(model: week), appearance: .darkAqua), to: folder.appendingPathComponent("panel-week-dark.png"))
        let asking = demoModel()
        asking.calendar.loadPreview(events: sample.events, account: "keefer@example.com")
        asking.panelTab = .chat
        var found = AssistantService.Turn(role: .coco, text: "Tuesday afternoon is tight — your portfolio critique runs 2 to 3:30. 2:00 overlaps it; 3:30 is the first clear hour. Here's 2:00 as you asked:")
        found.activities = ["Looked at your calendar for Tue", "Suggested adding “Design review” — confirm below"]
        asking.assistant.loadPreview([AssistantService.Turn(role: .user, text: "Schedule a design review Tuesday at 2"), found], cost: 0.011)
        let tuesday = sample.busyDay
        asking.loadPreviewEventRequests([AppModel.EventRequest(
            kind: .create(EventDraft(title: "Design review", start: tuesday.addingTimeInterval(14 * 3600), end: tuesday.addingTimeInterval(15 * 3600))),
            conflicts: sample.events.filter { $0.id == "critique" })])
        write(view(PanelRootView(model: asking), appearance: .aqua), to: folder.appendingPathComponent("panel-chat-event.png"))
        write(view(ConnectionsView(model: connected), appearance: .aqua), to: folder.appendingPathComponent("connections-connected.png"))
        write(view(ConnectionsView(model: connected, height: 2200), appearance: .aqua), to: folder.appendingPathComponent("connections-all.png"))
        // Notion connected, no calendar: the picker card is the first thing in the list.
        let notionOnly = demoModel()
        notionOnly.notion.loadPreview(
            mapping: NotionMapping(dataSourceID: "ds", dataSourceTitle: "Portfolio tasks", titleProperty: "Name"),
            tasks: [
                NotionTask(id: "n1", title: "Write case study intro", isDone: false, due: at(12), priority: .high),
                NotionTask(id: "n2", title: "Export hero renders", isDone: false, due: nil, priority: .none),
                NotionTask(id: "n3", title: "Email the printer", isDone: false, due: at(24 * 3), priority: .low),
            ],
            workspace: "Keefer's Notion")
        write(view(PanelRootView(model: notionOnly), appearance: .aqua), to: folder.appendingPathComponent("panel-notion.png"))
        write(view(ConnectionsView(model: AppModel(preview: true)), appearance: .darkAqua),
              to: folder.appendingPathComponent("connections-setup-dark.png"))

        let chatting = demoModel()
        chatting.panelTab = .chat
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
        write(view(PanelRootView(model: chatting), appearance: .aqua), to: folder.appendingPathComponent("panel-chat.png"))
        write(view(PanelRootView(model: { let m = AppModel(preview: true); m.panelTab = .chat; return m }()), appearance: .darkAqua),
              to: folder.appendingPathComponent("panel-chat-empty-dark.png"))
        let starters = demoModel()
        starters.panelTab = .chat
        starters.assistant.loadPreview([], cost: 0)
        write(view(PanelRootView(model: starters), appearance: .aqua), to: folder.appendingPathComponent("panel-chat-starters.png"))

        let fresh = demoModel()
        write(view(SettingsView(model: fresh, height: 1240), appearance: .aqua), to: folder.appendingPathComponent("settings.png"))
        for step in 0..<4 {
            write(view(OnboardingView(model: fresh, finish: {}, step: step, animated: false), appearance: step == 2 ? .darkAqua : .aqua),
                  to: folder.appendingPathComponent("welcome-\(step + 1).png"))
        }

        let editing = demoModel()
        editing.editingTaskID = editing.tasks.today().first(where: { $0.title.hasPrefix("Take Coco") })?.id
        write(view(PanelRootView(model: editing), appearance: .aqua), to: folder.appendingPathComponent("panel-editor.png"))

        let empty = AppModel(preview: true)
        write(view(PanelRootView(model: empty), appearance: .aqua), to: folder.appendingPathComponent("panel-empty.png"))
        print("Snapshots written to \(folder.path)")
    }

    // MARK: - App icon

    /// Renders the 1024 px app icon: Coco on a warm paper tile in the macOS icon shape.
    static func renderIcon(to url: URL) {
        let art = CocoLayerView(frame: NSRect(x: 0, y: 0, width: 330, height: 392))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 330, height: 392),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = art
        window.orderFrontRegardless()
        var animator = CharacterAnimator()
        animator.setState(.idle, at: 0)
        var pose = animator.pose(at: 1000.25)
        pose.eyeOpen = 1
        pose.headTilt = 0.1
        pose.mouthOpen = 0.32
        pose.tongue = 0.75
        pose.earPerk = 0.95
        art.layoutSubtreeIfNeeded()
        art.render(pose, focusProgress: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        art.render(pose, focusProgress: nil)
        // Draw Coco's layer tree into a transparent, top-left-origin image (her layers are y-down).
        let coco = NSImage(size: art.bounds.size, flipped: true) { _ in
            guard let context = NSGraphicsContext.current?.cgContext,
                  let root = art.layer?.sublayers?.first else { return false }
            root.render(in: context)
            return true
        }
        window.orderOut(nil)

        let size = NSSize(width: 1024, height: 1024)
        let icon = NSImage(size: size, flipped: false) { _ in
            let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
            let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.set()
            BrandPalette.iconTile.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            // A darker floor band gives the tile a little physical depth.
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            BrandPalette.iconFloor.setFill()
            NSRect(x: 100, y: 100, width: 824, height: 210).fill()
            NSGraphicsContext.restoreGraphicsState()
            BrandPalette.iconStroke.setStroke()
            shape.lineWidth = 3
            shape.stroke()
            // Coco, feet on the floor band.
            coco.draw(in: NSRect(x: 512 - 330, y: 150, width: 660, height: 784))
            return true
        }
        write(icon, to: url)
    }

    // MARK: - Character

    private struct Frame {
        var label: String
        var pose: CharacterPose
        var progress: Double? = nil
        var scale: CGFloat = 1
    }

    private static func characterFrames() -> [Frame] {
        let t0: TimeInterval = 800_000_000
        func pose(_ state: CharacterState, at dt: TimeInterval = 2.0, _ configure: (inout CharacterAnimator, TimeInterval) -> Void = { _, _ in }) -> CharacterPose {
            var animator = CharacterAnimator()
            animator.setState(state, at: t0 - 10)
            var t = t0 + dt
            // Step past blinks and idle fidgets so each expression reads clearly.
            while CharacterAnimator.blinkAmount(at: t) > 0 || (state == .idle && !CharacterAnimator.idleEvents(at: t).isEmpty) {
                t += 0.2
            }
            configure(&animator, t)
            return animator.pose(at: t)
        }
        /// An idle pose caught in the middle of one of Coco's unprompted behaviours.
        func idle(_ kind: CharacterAnimator.IdleEvent.Kind, offset: TimeInterval = 0.5) -> CharacterPose {
            var animator = CharacterAnimator()
            animator.setState(.idle, at: t0 - 10)
            let event = stride(from: t0, to: t0 + 600, by: 0.1)
                .lazy.compactMap { CharacterAnimator.idleEvents(at: $0).first { $0.kind == kind } }.first!
            var t = event.start + min(offset, event.duration / 2)
            while CharacterAnimator.blinkAmount(at: t) > 0 { t += 0.05 }
            return animator.pose(at: t)
        }
        let blinkTime = stride(from: t0, to: t0 + 10, by: 0.005).first { CharacterAnimator.blinkAmount(at: $0) > 0.95 }!
        var blinker = CharacterAnimator()
        blinker.setState(.idle, at: t0 - 10)

        return [
            Frame(label: "idle", pose: pose(.idle)),
            Frame(label: "blink", pose: blinker.pose(at: blinkTime)),
            Frame(label: "looking", pose: pose(.idle) { a, t in a.look(at: SIMD2(0.9, -0.5), at: t - 1) }),
            Frame(label: "listening", pose: pose(.listening, at: 0.6)),
            Frame(label: "talking", pose: pose(.talking, at: 0.12)),
            Frame(label: "thinking", pose: pose(.thinking)),
            Frame(label: "celebrating", pose: pose(.celebrating, at: 0.5 / 2.3 + 2 / 2.3)),
            Frame(label: "focused 60%", pose: pose(.focused), progress: 0.6),
            Frame(label: "sleeping", pose: pose(.sleeping, at: 1.4)),
            Frame(label: "panting", pose: idle(.pant, offset: 1.2)),
            Frame(label: "wagging", pose: idle(.wag, offset: 0.4)),
            Frame(label: "curious tilt", pose: idle(.curiousTilt, offset: 0.8)),
            Frame(label: "carried", pose: pose(.idle) { a, t in a.setCarried(true, at: t - 1) }),
            Frame(label: "poked", pose: pose(.idle) { a, t in a.react(.poke, at: t - 0.02) }),
            Frame(label: "compact", pose: pose(.idle), scale: CharacterLayout.compactScale),
            Frame(label: "focused small", pose: pose(.focused), progress: 0.25, scale: CharacterLayout.compactScale),
        ]
    }

    /// The real bubble window path (measure → size → place), as the app shows it at launch.
    static func renderBubbleWindow(to url: URL) {
        let parent = NSWindow(contentRect: NSRect(x: 600, y: 200, width: 124, height: 140), styleMask: .borderless, backing: .buffered, defer: false)
        parent.backgroundColor = .clear
        parent.orderFrontRegardless()
        let bubble = BubbleWindowController(parent: parent)
        bubble.show(BuddyVoice.greeting(), near: parent.frame, on: NSScreen.main)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        if let window = parent.childWindows?.first, let view = window.contentView {
            print("bubble window: \(Int(window.frame.width)) × \(Int(window.frame.height))")
            let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        } else {
            print("bubble window: not shown")
        }
        parent.orderOut(nil)
    }

    /// The call circle while aiming (left of each pair) and as the destination marker,
    /// on a light, a dark and a bright wallpaper.
    static func callTargetSheet() -> NSImage {
        let tile: CGFloat = 120
        let walls = [NSColor(hex: 0xD9E0E6), NSColor(hex: 0x1E252D), NSColor(hex: 0xF2A65A)]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: tile * CGFloat(walls.count), height: tile))
        view.wantsLayer = true
        for (index, wall) in walls.enumerated() {
            let x = CGFloat(index) * tile
            let background = CALayer()
            background.frame = CGRect(x: x, y: 0, width: tile, height: tile)
            background.backgroundColor = wall.cgColor
            view.layer?.addSublayer(background)
            let aim = CallTarget()
            aim.layer.position = CGPoint(x: x + 38, y: tile / 2)
            view.layer?.addSublayer(aim.layer)
            let marker = CallTarget()
            marker.layer.position = CGPoint(x: x + 88, y: tile / 2)
            marker.layer.opacity = 0.6
            marker.layer.transform = CATransform3DMakeScale(0.8, 0.8, 1)
            view.layer?.addSublayer(marker.layer)
        }
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: view.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        window.orderOut(nil)
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    /// Coco's states as SVG, straight from her layers — the source for the Figma Mascot page.
    static func exportMascot(to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let art = CocoLayerView(frame: NSRect(x: 0, y: 0, width: 192, height: 228))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 192, height: 228),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = art
        window.orderFrontRegardless()
        for frame in characterFrames() where frame.scale == 1 {
            art.layoutSubtreeIfNeeded()
            art.render(frame.pose, focusProgress: frame.progress)
            let name = frame.label.replacingOccurrences(of: " 60%", with: "").replacingOccurrences(of: " ", with: "-")
            try? LayerSVGExporter.svg(of: art).write(to: folder.appendingPathComponent("coco-\(name).svg"), atomically: true, encoding: .utf8)
        }
        window.orderOut(nil)
    }

    private static func characterSheet(background: NSColor) -> NSImage {
        let frames = characterFrames()
        let cell = NSSize(width: 200, height: 266)
        let columns = 4
        let rows = (frames.count + columns - 1) / columns
        let size = NSSize(width: cell.width * CGFloat(columns), height: cell.height * CGFloat(rows))

        // Render each pose through a real (offscreen) window, the same path the app uses.
        let art = CocoLayerView(frame: NSRect(x: 0, y: 0, width: 192, height: 228))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 192, height: 228),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = background
        window.contentView = art
        art.layer?.backgroundColor = background.cgColor
        window.orderFrontRegardless()

        var tiles: [NSBitmapImageRep] = []
        for frame in frames {
            art.characterScale = frame.scale
            art.layoutSubtreeIfNeeded()
            art.render(frame.pose, focusProgress: frame.progress)
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))  // let the scale spring settle
            art.render(frame.pose, focusProgress: frame.progress)
            let rep = art.bitmapImageRepForCachingDisplay(in: art.bounds)!
            art.cacheDisplay(in: art.bounds, to: rep)
            tiles.append(rep)
        }
        window.orderOut(nil)

        return NSImage(size: size, flipped: false) { _ in
            background.setFill()
            NSRect(origin: .zero, size: size).fill()
            let isDark = background.brightnessComponent < 0.5
            for (index, frame) in frames.enumerated() {
                let column = index % columns
                let row = rows - 1 - index / columns
                let origin = NSPoint(x: CGFloat(column) * cell.width, y: CGFloat(row) * cell.height)
                tiles[index].draw(in: NSRect(x: origin.x + 4, y: origin.y + 30, width: 192, height: 228))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: isDark ? NSColor.white.withAlphaComponent(0.7) : NSColor.black.withAlphaComponent(0.6),
                ]
                NSString(string: frame.label.uppercased()).draw(at: NSPoint(x: origin.x + 12, y: origin.y + 10), withAttributes: attributes)
            }
            return true
        }
    }

    // MARK: - SwiftUI views

    /// A believable week: standups, back-to-back calls, someone else's meeting, an all-day
    /// marker, a workshop that fills a day, and a late event crossing midnight.
    private static func sampleWeek(model: AppModel) -> (events: [CalendarEvent], busyDay: Date, quietDay: Date) {
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
            CalendarEvent(id: "launch", title: "Launch watch", start: at(4, 23), end: at(5, 1), colorID: "11"),
            CalendarEvent(id: "park", title: "Park with Coco", start: at(6, 10), end: at(6, 11), colorID: "10"),
        ]
        return (events, day(1), day(5))
    }

    private static func demoModel() -> AppModel {
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
        model.tasks.restore(BuddyTask(title: "Water the plants", scope: .today, createdAt: .now.addingTimeInterval(-86_400)))
        model.focusLog.record(taskID: nil, seconds: 25 * 60, finished: true)
        model.focusLog.record(taskID: nil, seconds: 20 * 60, finished: false)
        model.speak("Good morning. Tail's wagging — what are we working on?", .ambient)
        return model
    }

    private static func view<Content: View>(_ content: Content, appearance: NSAppearance.Name) -> NSImage {
        let hosting = NSHostingView(rootView: content)
        hosting.frame.size = hosting.fittingSize
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: hosting.frame.size),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = appearance == .darkAqua ? NSColor(hex: 0x1E252D) : NSColor(hex: 0xD9E0E6)
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        let bounds = window.contentView!.bounds
        let rep = window.contentView!.bitmapImageRepForCachingDisplay(in: bounds)!
        window.contentView!.cacheDisplay(in: bounds, to: rep)
        window.orderOut(nil)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
#endif
