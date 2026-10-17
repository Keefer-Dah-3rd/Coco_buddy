#if DEBUG
import AppKit
import SwiftUI
import BuddyCore
import BuddyIntegrations

/// EXPERIMENT — opens "Coco Tactile Orange" in its own window beside the real Coco. Only
/// with `--tactile-orange` (Xcode scheme "Coco Tactile Orange"). The window is the desk; the
/// card sits on it. Drag by any empty area, close with ✕ or Esc.
final class TactileOrangeWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    static var windowSize: NSSize {
        NSSize(width: TO.cardSize.width + TO.deskMargin * 2,
               height: TO.cardSize.height + TO.deskMargin * 2 + TO.cardDrop)
    }

    func show() {
        if window == nil {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = NSSize(width: Self.windowSize.width, height: min(Self.windowSize.height, visible.height - 40))
            let window = TOWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            window.title = "Coco — Tactile Orange (experiment)"
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            window.backgroundColor = NSColor(hex: 0xD5D3C8)
            window.appearance = NSAppearance(named: .aqua)
            window.minSize = NSSize(width: size.width, height: 600)
            window.maxSize = NSSize(width: size.width, height: 4000)
            window.delegate = self
            window.contentView = NSHostingView(rootView: TOPanelView(model: model) { [weak self] in self?.close() })
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width - 40, y: visible.midY - size.height / 2))
            window.collectionBehavior = [.moveToActiveSpace]
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
    }
}

private final class TOWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Every Tactile Orange state as PNG, from sample data only:
/// `DesktopBuddy --tactile-orange-snapshots <folder>` (unsandboxed Debug build).
enum TactileOrangeSnapshots {
    static func run(into folder: URL) {
        typealias S = EditorialOrangeSnapshots
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let connected = S.connectedModel()
        shoot(TOPanelView(model: connected), "to-today", folder)
        shoot(TOPanelView(model: connected, expandedEventID: "1"), "to-today-event-open", folder, height: 1500)

        let week = S.connectedModel()
        let sample = S.sampleWeek(model: week)
        week.calendar.loadPreview(events: sample.events, account: "keefer@example.com")
        week.showScheduleDay(sample.busyDay)
        week.scheduleExpanded = true
        shoot(TOPanelView(model: week, expandedEventID: "review"), "to-week", folder, height: 1500)

        shoot(TOPanelView(model: AppModel(preview: true)), "to-today-empty", folder)

        let editing = S.connectedModel()
        editing.editingTaskID = editing.tasks.today().first(where: { $0.title.hasPrefix("Take Coco") })?.id
        shoot(TOPanelView(model: editing), "to-editor", folder)

        let review = S.demoModel()
        review.taskDrafts = TaskSplitter.split("I need to finish the homepage, review three portfolio projects for about an hour, and send two emails today")
            .map(AppModel.TaskDraft.init)
        shoot(TOPanelView(model: review), "to-voice-review", folder)

        let focus = S.connectedModel()
        shoot(TOPanelView(model: focus, section: .focus), "to-focus", folder)
        focus.startSelectedPhase()
        shoot(TOPanelView(model: focus, section: .focus), "to-focus-running", folder)
        focus.focus.stop()

        let chatting = S.demoModel()
        var reply = AssistantService.Turn(role: .coco, text: "Your 1:1 with Sam is at 2. Before then you've got a clean 90 minutes — I'd spend it on the homepage hero, since it's your only high-priority task. Want me to start a focus session on it?")
        reply.activities = ["Looked at your tasks and calendar"]
        chatting.assistant.loadPreview([AssistantService.Turn(role: .user, text: "What should I do before my 1:1?"), reply], cost: 0.012)
        chatting.taskDrafts = [
            QuickAddParser.Result(title: "Sketch three hero layouts", estimateMinutes: 30),
            QuickAddParser.Result(title: "Write headline options", estimateMinutes: 20),
        ].map(AppModel.TaskDraft.init)
        chatting.setDraftOriginForPreview(.chat)
        shoot(TOPanelView(model: chatting, section: .chat), "to-chat", folder, height: 1100)

        let asking = S.connectedModel()
        asking.assistant.loadPreview([AssistantService.Turn(role: .user, text: "Schedule a design review Tuesday at 2")], cost: 0.011)
        asking.loadPreviewEventRequests([AppModel.EventRequest(
            kind: .create(EventDraft(title: "Design review", start: sample.busyDay.addingTimeInterval(14 * 3600),
                                     end: sample.busyDay.addingTimeInterval(15 * 3600))),
            conflicts: sample.events.filter { $0.id == "critique" })])
        shoot(TOPanelView(model: asking, section: .chat), "to-chat-event", folder)
        shoot(TOPanelView(model: AppModel(preview: true), section: .chat), "to-chat-needs-key", folder)

        shoot(TOPanelView(model: connected, section: .system), "to-power-ups", folder, height: 1300)
        print("Tactile Orange snapshots written to \(folder.path)")
    }

    private static func shoot<Content: View>(_ content: Content, _ name: String, _ folder: URL, height: CGFloat? = nil) {
        let size = TactileOrangeWindowController.windowSize
        let view = AnyView(content.frame(width: size.width, height: height ?? size.height).environment(\.eoStill, true))
        EditorialOrangeSnapshots.write(EditorialOrangeSnapshots.render(view, background: NSColor(hex: 0xD5D3C8)),
                                       to: folder.appendingPathComponent(name + ".png"))
    }
}
#endif
