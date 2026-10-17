#if DEBUG
import AppKit
import SwiftUI

/// EXPERIMENT — opens "Coco Editorial Orange" in its own window, next to the real Coco and
/// her panel, so the two can be compared side by side. Only created when the app is
/// launched with `--editorial-orange` (Xcode scheme "Coco Editorial Orange").
///
/// The window is square-cornered and borderless like the reference's card (the 12pt orange
/// rule is its top edge); drag it by any empty area, close with ✕ or Esc.
final class EditorialOrangeWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let size = NSSize(width: EO.pageSize.width, height: min(EO.pageSize.height, visible.height - 40))
            let window = EOWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
            window.title = "Coco — Editorial Orange (experiment)"
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.hasShadow = true
            window.backgroundColor = NSColor(hex: 0xF5F4EE)
            window.appearance = NSAppearance(named: .aqua)
            window.minSize = NSSize(width: EO.pageSize.width, height: 560)
            window.maxSize = NSSize(width: EO.pageSize.width, height: 4000)
            window.delegate = self
            window.contentView = NSHostingView(rootView: EOPanelView(model: model) { [weak self] in self?.close() })
            // Left of centre, so the real panel (which opens beside Coco) stays in view.
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width - 40, y: visible.midY - size.height / 2))
            window.collectionBehavior = [.moveToActiveSpace]
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        // Drop the view tree so the masthead Coco's render loop stops while hidden.
        window?.contentView = nil
        window = nil
    }
}

/// A borderless window that can still take keyboard focus (text fields, shortcuts).
private final class EOWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
#endif
