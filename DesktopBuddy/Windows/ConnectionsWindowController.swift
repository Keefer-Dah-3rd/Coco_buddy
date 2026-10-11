import AppKit
import SwiftUI

/// A regular window for setting up Google Calendar and Notion — setup needs more room
/// (and a real window for the Google sign-in sheet) than the compact panel offers.
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
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: ConnectionsView(model: model))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// The window the Google sign-in sheet attaches to.
    var presentingWindow: NSWindow? { window }
}
