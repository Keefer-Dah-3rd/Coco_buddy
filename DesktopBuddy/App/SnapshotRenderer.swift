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
        ], account: "keefer@example.com")
        connected.notion.loadPreview(
            mapping: NotionMapping(dataSourceID: "ds", dataSourceTitle: "Portfolio tasks", titleProperty: "Name"),
            tasks: [
                NotionTask(id: "n1", title: "Write case study intro", isDone: false, due: at(12), priority: .high),
                NotionTask(id: "n2", title: "Export hero renders", isDone: false, due: nil, priority: .none),
                NotionTask(id: "n3", title: "Email the printer", isDone: false, due: at(24 * 3), priority: .low),
            ],
            workspace: "Keefer's Notion")
        write(view(PanelRootView(model: connected), appearance: .aqua), to: folder.appendingPathComponent("panel-connected.png"))
        write(view(ConnectionsView(model: connected), appearance: .aqua), to: folder.appendingPathComponent("connections-connected.png"))
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

        let editing = demoModel()
        editing.editingTaskID = editing.tasks.today().first(where: { $0.title.hasPrefix("Take Coco") })?.id
        write(view(PanelRootView(model: editing), appearance: .aqua), to: folder.appendingPathComponent("panel-editor.png"))

        let empty = AppModel(preview: true)
        write(view(PanelRootView(model: empty), appearance: .aqua), to: folder.appendingPathComponent("panel-empty.png"))
        print("Snapshots written to \(folder.path)")
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
