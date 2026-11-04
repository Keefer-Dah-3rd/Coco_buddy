import AppKit
import SwiftUI

/// A plain titled window hosting a SwiftUI view — Settings and the welcome flow.
/// (The buddy is a menu-bar app, so these windows bring the app forward when shown.)
/// With `drawsOwnEdge` the window is clear and untitled, so the view's own rounded paper and
/// rim are the edge — the welcome window's Blue Skies look — with the traffic lights on top.
final class HostedWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let title: String
    private let size: NSSize
    private let content: () -> AnyView
    private let drawsOwnEdge: Bool
    /// Called when the user closes the window (not when it's closed in code).
    var onUserClose: (() -> Void)?
    private var closingInCode = false

    init(title: String, size: NSSize, drawsOwnEdge: Bool = false, content: @escaping () -> AnyView) {
        self.title = title
        self.size = size
        self.drawsOwnEdge = drawsOwnEdge
        self.content = content
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = title
            window.titlebarAppearsTransparent = true
            if drawsOwnEdge {
                window.titleVisibility = .hidden
                window.isOpaque = false
                window.backgroundColor = .clear
            }
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
