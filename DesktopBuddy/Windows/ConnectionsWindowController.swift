import AppKit
import SwiftUI

/// A regular window for setting up Claude, the calendars, Partiful and Notion — setup needs
/// more room (and a real window for the Google sign-in sheet) than the compact panel offers.
final class ConnectionsWindowController {
    private var window: NSWindow?
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            window.title = "Connections"
            window.titlebarAppearsTransparent = true
            // ConnectionsView draws the title in Owners beside the traffic lights, and the navy rim.
            window.titleVisibility = .hidden
            // Light like the panel: the Sky colours have no dark variant.
            window.appearance = NSAppearance(named: .aqua)
            window.isReleasedWhenClosed = false
            var view = ConnectionsView(model: model)
            if let zoom = window.standardWindowButton(.zoomButton) {
                view.titleLeading = zoom.convert(zoom.bounds, to: nil).maxX + 8
                view.titleBarHeight = window.frame.height - window.contentLayoutRect.height
            }
            let hosting = NSHostingView(rootView: view)
            // Keep the window 540 × 680: sized to fit, it would grow by the title bar.
            hosting.sizingOptions = []
            window.contentView = hosting
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
