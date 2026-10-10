import AppKit
import SwiftUI

/// A key-capable but non-activating panel: you can type into it while the app
/// you were using stays active underneath, the way Spotlight behaves.
final class InteractionPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

final class PanelWindowController: NSObject, NSWindowDelegate {
    let window = InteractionPanel()
    private(set) var isOpen = false
    var onOpenChanged: ((Bool) -> Void)?

    init(model: AppModel) {
        super.init()
        let hosting = NSHostingView(rootView: PanelRootView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight)
        window.contentView = hosting
        window.delegate = self
        window.onEscape = { [weak self] in self?.close() }
    }

    func open(beside character: NSRect, on screen: NSScreen?) {
        guard !isOpen else { return }
        isOpen = true
        let bounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = window.frame.size
        let gap: CGFloat = 8
        let inset = character.width * 0.1

        let leftX = character.minX + inset - gap - size.width
        let rightX = character.maxX - inset + gap
        let preferLeft = character.midX > bounds.midX
        var x = preferLeft ? leftX : rightX
        if preferLeft, x < bounds.minX + 8 { x = rightX }
        if !preferLeft, x + size.width > bounds.maxX - 8 { x = leftX }
        x = min(max(x, bounds.minX + 8), bounds.maxX - size.width - 8)
        let y = min(max(character.minY, bounds.minY + 8), bounds.maxY - size.height - 8)

        let final = NSRect(origin: NSPoint(x: x, y: y), size: size)
        let slide: CGFloat = x < character.midX ? 8 : -8
        window.setFrame(final.offsetBy(dx: slide, dy: 0), display: false)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        window.invalidateShadow()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(final, display: true)
        }
        onOpenChanged?(true)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.window.orderOut(nil)
            }
        })
        onOpenChanged?(false)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the panel, like a popover.
        close()
    }
}
