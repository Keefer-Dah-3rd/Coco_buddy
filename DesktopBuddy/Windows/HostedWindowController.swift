import AppKit
import SwiftUI

/// A plain titled window hosting a SwiftUI view — Settings and the welcome flow.
/// (The buddy is a menu-bar app, so these windows bring the app forward when shown.)
final class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let size: NSSize
    private let content: () -> AnyView
    /// Called when the user closes the window (not when it's closed in code).
    var onUserClose: (() -> Void)?
    private var closingInCode = false

    init(title: String, size: NSSize, content: @escaping () -> AnyView) {
        self.title = title
        self.size = size
        self.content = content
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = title
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content())
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        closingInCode = true
        window?.close()
        closingInCode = false
    }

    func windowWillClose(_ notification: Notification) {
        if !closingInCode { onUserClose?() }
    }
}
