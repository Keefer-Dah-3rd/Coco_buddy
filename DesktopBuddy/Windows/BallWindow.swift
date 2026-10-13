import AppKit
import QuartzCore

/// Something Coco chases, out in the world — the tennis ball or a treat: a small
/// click-through window holding it and its shadow on the floor, moved to wherever the game
/// says it is. It sits just in front of Coco's window when it's nearer the viewer than she
/// is, behind it otherwise.
final class BallWindow {
    private let panel: BallPanel
    private let ball: TossedThing
    private var inFront: Bool?
    private var fadeWork: DispatchWorkItem?
    /// Room above the floor point for the highest arc.
    private static let size = CGSize(width: 64, height: 480)
    private static let floor = CGPoint(x: 32, y: 14)

    init(_ thing: TossedThing = TennisBallLayer()) {
        ball = thing
        panel = BallPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                          styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(origin: .zero, size: Self.size))
        view.wantsLayer = true
        view.layer?.addSublayer(ball.layer)
        panel.contentView = view
    }

    var isVisible: Bool { panel.isVisible }
    /// Where the ball touches the floor right now (screen coordinates).
    var floorPoint: CGPoint { CGPoint(x: panel.frame.minX + Self.floor.x, y: panel.frame.minY + Self.floor.y) }

    #if DEBUG
    /// Self-tests only: the ball is placed as usual but can't be seen.
    func makeInvisibleForTesting() { panel.alphaValue = 0 }
    #endif

    /// Puts the ball at a floor point (screen coordinates) with a height and spin.
    func place(ground: CGPoint, height: Double, spin: Double, scale: CGFloat, character: NSWindow, characterPaws: CGPoint) {
        fadeWork?.cancel()
        ball.setScale(scale)
        panel.setFrameOrigin(NSPoint(x: ground.x - Self.floor.x, y: ground.y - Self.floor.y))
        ball.place(ground: Self.floor, height: CGFloat(height), spin: CGFloat(spin))
        ball.layer.opacity = 1
        // Nearer the viewer — lower on screen — than her paws: in front of her.
        let front = ground.y < characterPaws.y
        if !panel.isVisible || front != inFront || panel.level != character.level {
            panel.level = character.level
            panel.order(front ? .above : .below, relativeTo: character.windowNumber)
            inFront = front
        }
    }

    func hide() {
        fadeWork?.cancel()
        panel.orderOut(nil)
        inFront = nil
    }

    /// A ball left lying around fades away after a while.
    func fade(after delay: TimeInterval) {
        fadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.6
                self.panel.animator().alphaValue = 0
            })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak self] in
                self?.panel.orderOut(nil)
                self?.panel.alphaValue = 1
                self?.inFront = nil
            }
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// The window is tall, with room above the ball for its highest arc. macOS would push it
/// down whenever that room pokes above the top of the screen, putting the ball below where
/// it really is — so it stays exactly where it's put.
private final class BallPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
