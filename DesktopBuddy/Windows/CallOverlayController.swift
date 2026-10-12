import AppKit
import QuartzCore

/// While the call key is held: an invisible layer over every display, with a half-faded
/// circle under the cursor showing where Coco's paws will land. The layer catches the
/// click, so it calls Coco instead of landing in the app underneath. After the click, a
/// smaller marker waits at the spot until she gets there.
final class CallOverlayController {
    /// A click while aiming, in screen coordinates.
    var onCall: ((CGPoint) -> Void)?
    /// The cursor moved over the overlay (the usual mouse tracking can't see it there).
    var onCursorMoved: (() -> Void)?

    private(set) var isShowing = false
    private var panels: [OverlayPanel] = []
    private var hideWork: DispatchWorkItem?
    private let marker = MarkerPanel()

    func show() {
        guard !isShowing else { return }
        isShowing = true
        hideWork?.cancel()
        matchScreens()
        let mouse = NSEvent.mouseLocation
        for panel in panels {
            panel.surface.moveTarget(to: mouse)
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        panels.forEach { $0.surface.hideTarget() }
        // Out of the way promptly: while it's up, it catches every click.
        let work = DispatchWorkItem { [weak self] in self?.panels.forEach { $0.orderOut(nil) } }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
    }

    /// Marks where she's headed, just under her window so she runs onto it.
    func showMarker(at point: CGPoint, below window: NSWindow) {
        marker.show(at: point, level: window.level, below: window.windowNumber)
    }

    func hideMarker() {
        marker.pop()
    }

    private func cursorMoved() {
        let mouse = NSEvent.mouseLocation
        panels.forEach { $0.surface.moveTarget(to: mouse) }
        onCursorMoved?()
    }

    /// One panel per display, rebuilt when displays are added, removed or rearranged.
    private func matchScreens() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != panels.map(\.frame) else { return }
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let panel = OverlayPanel(frame: screen.frame)
            panel.surface.onClick = { [weak self] point in
                self?.panels.forEach { $0.surface.ping(at: point) }
                self?.onCall?(point)
            }
            panel.surface.onMouseMoved = { [weak self] in self?.cursorMoved() }
            return panel
        }
    }
}

// MARK: - Overlay

private final class OverlayPanel: NSPanel {
    let surface: OverlaySurface

    init(frame: NSRect) {
        surface = OverlaySurface(frame: NSRect(origin: .zero, size: frame.size))
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // Over the menu bar and Dock too, so a click there doesn't reach them either.
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Set explicitly: unlike the character window, this one should catch clicks on
        // its transparent pixels too.
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        contentView = surface
        setFrame(frame, display: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class OverlaySurface: NSView {
    var onClick: ((CGPoint) -> Void)?
    var onMouseMoved: (() -> Void)?
    private let target = CallTarget()
    private var targetShown = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        target.layer.opacity = 0
        layer?.addSublayer(target.layer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Shows the circle at a screen point if it's on this display, otherwise hides it.
    func moveTarget(to point: CGPoint) {
        guard let window, window.frame.contains(point) else {
            if targetShown { hideTarget() }
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.layer.position = CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY)
        CATransaction.commit()
        if !targetShown {
            targetShown = true
            target.appear()
        }
    }

    func hideTarget() {
        guard targetShown else { return }
        targetShown = false
        target.disappear()
    }

    /// A ripple where you clicked, so the click visibly registered.
    func ping(at point: CGPoint) {
        guard let window, window.frame.contains(point) else { return }
        CallTarget.ripple(at: CGPoint(x: point.x - window.frame.minX, y: point.y - window.frame.minY), in: layer)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // If the key went up unnoticed, this click isn't a call; the overlay is leaving.
        guard CallKeyMonitor.isCallKey(event.modifierFlags) else { return }
        onClick?(NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseDragged(with event: NSEvent) { onMouseMoved?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self))
    }
}

// MARK: - Destination marker

private final class MarkerPanel: NSPanel {
    private let target = CallTarget()
    private var popWork: DispatchWorkItem?
    private static let size: CGFloat = 64

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Self.size, height: Self.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: NSRect(x: 0, y: 0, width: Self.size, height: Self.size))
        view.wantsLayer = true
        target.layer.position = CGPoint(x: Self.size / 2, y: Self.size / 2)
        target.layer.opacity = 0
        view.layer?.addSublayer(target.layer)
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show(at point: CGPoint, level: NSWindow.Level, below windowNumber: Int) {
        popWork?.cancel()
        setFrameOrigin(NSPoint(x: point.x - Self.size / 2, y: point.y - Self.size / 2))
        self.level = level
        order(.below, relativeTo: windowNumber)
        target.appear(asMarker: true)
    }

    /// She's arrived: the marker pops and goes.
    func pop() {
        guard isVisible else { return }
        target.pop()
        let work = DispatchWorkItem { [weak self] in self?.orderOut(nil) }
        popWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

// MARK: - The circle

/// "Coco goes here": a soft disc and ring in Coco's orange with a paw print in the middle.
final class CallTarget {
    static let radius: CGFloat = 21
    let layer = CALayer()
    private let disc = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let paw = CAShapeLayer()

    init() {
        let r = Self.radius
        let box = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        layer.bounds = box
        let circle = CGPath(ellipseIn: box.insetBy(dx: 1, dy: 1), transform: nil)
        let accent = BrandPalette.accent
        disc.path = circle
        disc.fillColor = accent.withAlphaComponent(0.22).cgColor
        ring.path = circle
        ring.fillColor = nil
        ring.strokeColor = accent.withAlphaComponent(0.8).cgColor
        ring.lineWidth = 2
        // A faint dark edge keeps the ring readable on light and orange backgrounds alike.
        ring.shadowColor = NSColor.black.cgColor
        ring.shadowOpacity = 0.25
        ring.shadowRadius = 1.5
        ring.shadowOffset = .zero
        paw.path = Self.pawPrint(center: CGPoint(x: r, y: r), size: 16)
        paw.fillColor = accent.withAlphaComponent(0.85).cgColor
        for part in [disc, ring, paw] {
            part.frame = box
            layer.addSublayer(part)
        }
    }

    func appear(asMarker: Bool = false) {
        layer.removeAllAnimations()
        ring.removeAllAnimations()
        let opacity: Float = asMarker ? 0.6 : 1
        let scale: CGFloat = asMarker ? 0.8 : 1
        layer.opacity = opacity
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = opacity
        fade.duration = 0.12
        layer.add(fade, forKey: "fade")
        let grow = CASpringAnimation(keyPath: "transform.scale")
        grow.fromValue = scale * 0.55
        grow.toValue = scale
        grow.damping = 13
        grow.stiffness = 320
        grow.duration = grow.settlingDuration
        layer.add(grow, forKey: "grow")
        // A slow breath on the ring says "still aiming"; it runs in the render server, not here.
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 1
        breathe.toValue = asMarker ? 1.1 : 1.07
        breathe.duration = asMarker ? 0.45 : 0.7
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(breathe, forKey: "breathe")
    }

    func disappear() {
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = 0
        fade.duration = 0.12
        layer.add(fade, forKey: "fade")
        ring.removeAnimation(forKey: "breathe")
    }

    func pop() {
        let from = layer.presentation()?.opacity ?? layer.opacity
        layer.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = 0
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.toValue = 1.35
        let group = CAAnimationGroup()
        group.animations = [fade, grow]
        group.duration = 0.22
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "pop")
        ring.removeAnimation(forKey: "breathe")
    }

    /// An expanding ring that fades out — the click registered.
    static func ripple(at point: CGPoint, in host: CALayer?) {
        guard let host else { return }
        let r = radius
        let ring = CAShapeLayer()
        ring.bounds = CGRect(x: 0, y: 0, width: 2 * r, height: 2 * r)
        ring.position = point
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 1, dy: 1), transform: nil)
        ring.fillColor = nil
        ring.strokeColor = BrandPalette.accent.cgColor
        ring.lineWidth = 2
        ring.opacity = 0
        host.addSublayer(ring)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 1.9
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.85
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.38
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "ripple")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ring.removeFromSuperlayer() }
    }

    /// A paw print: one main pad and four toes, in a layer whose y points up.
    static func pawPrint(center c: CGPoint, size s: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: c.x - 0.3 * s, y: c.y - 0.42 * s, width: 0.6 * s, height: 0.46 * s))
        let toes: [(x: CGFloat, y: CGFloat, tilt: CGFloat)] = [
            (-0.38, 0.06, 0.45), (-0.14, 0.28, 0.15), (0.14, 0.28, -0.15), (0.38, 0.06, -0.45),
        ]
        for toe in toes {
            let transform = CGAffineTransform(translationX: c.x + toe.x * s, y: c.y + toe.y * s).rotated(by: toe.tilt)
            path.addEllipse(in: CGRect(x: -0.1 * s, y: -0.13 * s, width: 0.2 * s, height: 0.26 * s), transform: transform)
        }
        return path
    }
}
