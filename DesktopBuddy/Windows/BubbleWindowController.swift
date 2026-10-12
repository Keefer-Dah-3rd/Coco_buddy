import AppKit
import SwiftUI

/// The speech bubble lives in its own small window, attached as a child of the
/// character window so it moves with it. It ignores the mouse entirely and only
/// exists while something is being said — no invisible area blocking clicks.
final class BubbleWindowController {
    private let parent: NSWindow
    private let window: NSPanel
    private let hosting = NSHostingView(rootView: SpeechBubbleView(text: "", tail: .bottom, tailAnchor: 0.5))
    private var hideWork: DispatchWorkItem?

    init(parent: NSWindow) {
        self.parent = parent
        window = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hosting.sizingOptions = []
        window.contentView = hosting
    }

    func show(_ text: String, near character: NSRect, on screen: NSScreen?) {
        guard parent.isVisible else { return }
        hideWork?.cancel()
        let bounds = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // Prefer above the head; fall back to the side with more room.
        var tail = SpeechBubbleView.Tail.bottom
        var size = measure(text, tail: tail)
        var origin = NSPoint(x: character.midX - size.width / 2, y: character.maxY + 2)
        if origin.y + size.height > bounds.maxY {
            tail = character.midX > bounds.midX ? .trailing : .leading
            size = measure(text, tail: tail)
            let x = tail == .trailing ? character.minX + character.width * 0.12 - size.width
                                      : character.maxX - character.width * 0.12
            origin = NSPoint(x: x, y: character.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, bounds.minX + 6), bounds.maxX - size.width - 6)
        origin.y = min(max(origin.y, bounds.minY + 6), bounds.maxY - size.height - 6)

        let anchor = tail == .bottom ? (character.midX - origin.x) / size.width : 0.5
        hosting.rootView = SpeechBubbleView(text: text, tail: tail, tailAnchor: min(0.85, max(0.15, anchor)))
        window.setFrame(NSRect(origin: origin, size: size), display: true)

        if window.parent == nil {
            parent.addChildWindow(window, ordered: .above)
        }
        window.alphaValue = 0
        window.orderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            window.animator().alphaValue = 1
        }
    }

    func hide() {
        guard window.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            window.animator().alphaValue = 0
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.parent.removeChildWindow(self.window)
            self.window.orderOut(nil)
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
    }

    private func measure(_ text: String, tail: SpeechBubbleView.Tail) -> NSSize {
        hosting.rootView = SpeechBubbleView(text: text, tail: tail, tailAnchor: 0.5)
        let size = hosting.fittingSize
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }
}

struct SpeechBubbleView: View {
    enum Tail { case bottom, leading, trailing }

    let text: String
    let tail: Tail
    /// Where along the bottom edge the tail sits, 0…1.
    let tailAnchor: CGFloat

    private static let tailSize: CGFloat = 7

    var body: some View {
        Text(text)
            .font(.style(.speechBubble))
            .foregroundStyle(Theme.ink)
            .lineSpacing(1.5)
            .frame(maxWidth: 210, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 11)
            .padding(.vertical, Space.sm)
            .padding(tailEdge, Self.tailSize)
            .background {
                let shape = BubbleShape(tail: tail, anchor: tailAnchor, tailSize: Self.tailSize)
                shape.fill(Theme.paper)
                shape.stroke(Theme.ink.opacity(0.85), lineWidth: 1)
            }
            .padding(1)
    }

    private var tailEdge: Edge.Set {
        switch tail {
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}

/// A rounded rectangle and its pointer as one outline, so the stroke is continuous.
private struct BubbleShape: Shape {
    let tail: SpeechBubbleView.Tail
    let anchor: CGFloat
    let tailSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var body = rect
        var pointer = Path()
        switch tail {
        case .bottom:
            body.size.height -= tailSize
            let x = body.minX + body.width * anchor
            pointer.move(to: CGPoint(x: x - 6, y: body.maxY - 1))
            pointer.addLine(to: CGPoint(x: x + 5, y: body.maxY - 1))
            pointer.addLine(to: CGPoint(x: x - 1, y: body.maxY + tailSize))
        case .leading:
            body.origin.x += tailSize
            body.size.width -= tailSize
            pointer.move(to: CGPoint(x: body.minX + 1, y: body.midY - 6))
            pointer.addLine(to: CGPoint(x: body.minX + 1, y: body.midY + 5))
            pointer.addLine(to: CGPoint(x: body.minX - tailSize, y: body.midY + 2))
        case .trailing:
            body.size.width -= tailSize
            pointer.move(to: CGPoint(x: body.maxX - 1, y: body.midY - 6))
            pointer.addLine(to: CGPoint(x: body.maxX - 1, y: body.midY + 5))
            pointer.addLine(to: CGPoint(x: body.maxX + tailSize, y: body.midY + 2))
        }
        pointer.closeSubpath()
        let bubble = Path(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), cornerRadius: Radius.bubble, style: .continuous)
        return bubble.union(pointer)
    }
}
