import AppKit
import SwiftUI
import BuddyCharacter

/// A borderless, transparent panel that never takes keyboard focus or activates
/// the app, so clicking the buddy doesn't pull you out of what you're doing.
final class CharacterPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: CharacterLayout.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Every Space, over full-screen apps, ignored by Mission Control and ⌘`.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Note: `ignoresMouseEvents` is deliberately never set. Left at its default,
        // the window server passes clicks on fully transparent pixels through to
        // whatever is underneath, so only the drawn character is clickable.
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Owns the character window: placement, dragging, clicks and visibility.
final class CharacterWindowController: NSObject, NSWindowDelegate {
    let window = CharacterPanel()

    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    var onDragChanged: ((Bool) -> Void)?
    /// Normalised cursor direction relative to the face, or nil when the cursor is far away.
    var onGaze: ((SIMD2<Double>?) -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onOcclusionChanged: ((Bool) -> Void)?
    /// She has arrived (or been stopped) after being called somewhere.
    var onDashFinished: (() -> Void)?
    /// Whether the eyes should follow a nearby cursor at all (interactive presence).
    var followsCursor = true
    /// While you aim where to call her, she watches the cursor wherever it is.
    var isWatchingAim = false {
        didSet { if isWatchingAim != oldValue { cursorMoved() } }
    }

    private let model: CharacterModel
    private let interaction = InteractionView()
    private let art = CocoLayerView(frame: CharacterLayout.artViewFrame)
    private let renderLoop: CharacterRenderLoop
    private var globalMouseMonitor: Any?
    private var cursorIsNear = false

    init(model: CharacterModel) {
        self.model = model
        renderLoop = CharacterRenderLoop(model: model, view: art)
        super.init()

        let container = NSView(frame: NSRect(origin: .zero, size: CharacterLayout.windowSize))
        container.wantsLayer = true
        container.addSubview(art)
        let chip = NSHostingView(rootView: CountdownChipView(model: model))
        chip.sizingOptions = []
        chip.frame = CharacterLayout.chipFrame
        container.addSubview(chip)
        interaction.frame = container.bounds
        interaction.autoresizingMask = [.width, .height]
        container.addSubview(interaction)
        window.contentView = container
        window.delegate = self

        // Grabbing her mid-run stops her where she is.
        interaction.onMouseDown = { [weak self] in self?.stopDash() }
        interaction.onClick = { [weak self] in self?.onClick?() }
        interaction.onRightClick = { [weak self] event, view in self?.onRightClick?(event, view) }
        interaction.onDragChanged = { [weak self] dragging in
            guard let self else { return }
            self.onDragChanged?(dragging)
            if !dragging { self.settleOnScreen(animated: true) }
        }
        interaction.onMouseMoved = { [weak self] in self?.cursorMoved() }
        interaction.onMouseExited = { [weak self] in self?.cursorMoved() }
        interaction.accessibilityState = { model.state.label }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cursorMoved() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stopDash(atDestination: true)
                self?.settleOnScreen(animated: false)
            }
        }
        connectRendering()
    }

    /// Redraw whenever the animator or what it draws changes; the loop handles the rest.
    private func connectRendering() {
        let model = model, art = art, renderLoop = renderLoop
        track({ (model.animator, model.focusProgress) }) { _ in renderLoop.setNeedsFrame() }
        track({ model.scale }) { art.characterScale = $0 }
        // A covered buddy normally stops drawing, but one that's running has to keep
        // going — she's on her way out from under whatever covers her.
        track({ (model.isRenderingPaused, model.dash != nil) }) { renderLoop.isPaused = $0 && !$1 }
        renderLoop.onFrame = { [weak self] t in self?.followDash(at: t) }
        track({ model.isLowPower }) { renderLoop.applyPowerMode(lowPower: $0) }
        track({ model.isDimmed }) { dimmed in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.5
                art.animator().alphaValue = dimmed ? 0.5 : 1
            }
        }
    }

    // MARK: - Visibility & level

    func setVisible(_ visible: Bool) {
        if visible {
            window.orderFrontRegardless()
        } else {
            stopDash(atDestination: true)
            window.orderOut(nil)
        }
    }

    func setAlwaysOnTop(_ onTop: Bool) {
        window.level = onTop ? .floating : .normal
    }

    // MARK: - Geometry

    /// The drawn character's rect in screen coordinates (used to place the bubble and panel).
    var characterFrame: NSRect { characterFrame(at: window.frame.origin) }

    private func characterFrame(at origin: NSPoint) -> NSRect {
        let art = CharacterLayout.artFrame
        let size = art.width * model.scale
        let local = NSRect(x: art.midX - size / 2, y: art.minY, width: size, height: size)
        return local.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// Where her paws touch the ground, relative to the window origin (the art's ground
    /// line sits 7% up from the bottom of its box).
    private var pawOffset: CGPoint {
        let art = CharacterLayout.artFrame
        return CGPoint(x: art.midX, y: art.minY + art.height * 0.07 * model.scale)
    }

    var screen: NSScreen? {
        window.screen ?? NSScreen.screens.first { $0.frame.contains(characterFrame.center) } ?? NSScreen.main
    }

    /// Puts the window at a saved origin, or the bottom-right corner of the main display.
    func place(at savedOrigin: CGPoint?) {
        if let savedOrigin {
            window.setFrameOrigin(savedOrigin)
        } else if let visible = NSScreen.main?.visibleFrame {
            let art = CharacterLayout.artFrame
            window.setFrameOrigin(NSPoint(x: visible.maxX - art.maxX - 24, y: visible.minY + 12))
        }
        settleOnScreen(animated: false)
    }

    func resetPosition() {
        place(at: nil)
        onMoved?(window.frame.origin)
    }

    /// Nudges the window so the whole character is on a display, e.g. after a drag
    /// or when a monitor is unplugged.
    func settleOnScreen(animated: Bool) {
        let origin = onScreenOrigin(near: window.frame.origin)
        if origin != window.frame.origin {
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrameOrigin(origin)
                }
            } else {
                window.setFrameOrigin(origin)
            }
        }
        onMoved?(origin)
    }

    /// The closest window origin that keeps the whole character on a display.
    private func onScreenOrigin(near origin: NSPoint) -> NSPoint {
        let character = characterFrame(at: origin)
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return origin }
        let target = screens.first { $0.visibleFrame.contains(character.center) }
            ?? screens.min { $0.visibleFrame.center.distance(to: character.center) < $1.visibleFrame.center.distance(to: character.center) }!
        let bounds = target.visibleFrame

        var dx: CGFloat = 0
        var dy: CGFloat = 0
        if character.minX < bounds.minX { dx = bounds.minX - character.minX }
        if character.maxX > bounds.maxX { dx = bounds.maxX - character.maxX }
        // The art box has a little headroom above the antenna, so allow some overlap at the top.
        let headroom = character.height * 0.12
        if character.minY < bounds.minY { dy = bounds.minY - character.minY }
        if character.maxY - headroom > bounds.maxY { dy = bounds.maxY - (character.maxY - headroom) }
        return NSPoint(x: origin.x + dx, y: origin.y + dy)
    }

    // MARK: - Being called

    var isDashing: Bool { model.dash != nil }

    /// Where she'll actually stand for a click at `point`: her paws on it, or as close as
    /// she can get while staying fully on a display (not on the menu bar or Dock).
    func destination(forClickAt point: CGPoint) -> CGPoint {
        let paws = pawOffset
        let origin = onScreenOrigin(near: NSPoint(x: point.x - paws.x, y: point.y - paws.y))
        return CGPoint(x: origin.x + paws.x, y: origin.y + paws.y)
    }

    /// Sends her running to a click at `point`. A second call mid-run changes course.
    func call(to point: CGPoint) {
        guard window.isVisible, !interaction.isDragging else { return }
        let target = destination(forClickAt: point)
        let paws = CGPoint(x: window.frame.minX + pawOffset.x, y: window.frame.minY + pawOffset.y)
        let now = CharacterModel.clock
        if model.animator.reduceMotion {
            fade(toPaws: target)
        } else if let dash = model.dash {
            model.setDash(dash.redirected(to: SIMD2(target.x, target.y), at: now))
        } else if paws.distance(to: target) < 6 {
            // Already there: a happy perk instead of a run.
            model.react(.perk)
            onDashFinished?()
        } else {
            model.setDash(Dash(from: SIMD2(paws.x, paws.y), to: SIMD2(target.x, target.y), at: now))
        }
    }

    /// Every frame of a dash: put the window where the dash says she is.
    private func followDash(at t: TimeInterval) {
        guard let dash = model.dash else { return }
        let paws = dash.position(at: t)
        window.setFrameOrigin(NSPoint(x: paws.x - pawOffset.x, y: paws.y - pawOffset.y))
        if t >= dash.endTime { stopDash() }
    }

    /// Ends a dash where she is, or (when she can't be watched running) at the destination.
    func stopDash(atDestination: Bool = false) {
        guard let dash = model.dash else { return }
        if atDestination {
            window.setFrameOrigin(NSPoint(x: dash.end.x - pawOffset.x, y: dash.end.y - pawOffset.y))
        }
        model.setDash(nil)
        onMoved?(window.frame.origin)
        onDashFinished?()
    }

    /// Reduce Motion: no run across the screen — she fades out and back in at the spot.
    private func fade(toPaws target: CGPoint) {
        let window = window
        let origin = NSPoint(x: target.x - pawOffset.x, y: target.y - pawOffset.y)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            window.animator().alphaValue = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in
            window.setFrameOrigin(origin)
            self?.onMoved?(origin)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                window.animator().alphaValue = 1
            }
            self?.onDashFinished?()
        }
    }

    // MARK: - Cursor following

    func cursorMoved() {
        let face = characterFrame.center.offsetBy(dy: characterFrame.height * 0.12)
        let mouse = NSEvent.mouseLocation
        if isWatchingAim, window.isVisible, !isDashing {
            // Eyes on the spot you're pointing at, however far away.
            let reach = max(140, face.distance(to: mouse))
            cursorIsNear = true
            onGaze?(SIMD2((mouse.x - face.x) / reach, -(mouse.y - face.y) / reach))
            return
        }
        guard window.isVisible, followsCursor, !interaction.isDragging, !isDashing else {
            if cursorIsNear { cursorIsNear = false; onGaze?(nil) }
            return
        }
        let distance = face.distance(to: mouse)
        // Hysteresis so the eyes don't flicker at the boundary.
        let near = cursorIsNear ? distance < 260 : distance < 220
        if near {
            cursorIsNear = true
            onGaze?(SIMD2((mouse.x - face.x) / 140, -(mouse.y - face.y) / 140))
        } else if cursorIsNear {
            cursorIsNear = false
            onGaze?(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidChangeOcclusionState(_ notification: Notification) {
        onOcclusionChanged?(!window.occlusionState.contains(.visible))
    }
}

/// Transparent overlay that tells clicks from drags and moves the window by hand,
/// which gives exact drag-start/drag-end moments for the "being carried" pose.
private final class InteractionView: NSView {
    var onMouseDown: (() -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent, NSView) -> Void)?
    var onDragChanged: ((Bool) -> Void)?
    var onMouseMoved: (() -> Void)?
    var onMouseExited: (() -> Void)?
    private(set) var isDragging = false

    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint = .zero

    var accessibilityState: () -> String = { "" }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "\(Buddy.name), your desktop corgi" }
    override func accessibilityValue() -> Any? { accessibilityState() }
    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin ?? .zero
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x
        let dy = now.y - start.y
        if !isDragging {
            guard hypot(dx, dy) > 3 else { return }
            isDragging = true
            NSCursor.closedHand.push()
            onDragChanged?(true)
        }
        window.setFrameOrigin(NSPoint(x: windowOriginAtMouseDown.x + dx, y: windowOriginAtMouseDown.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil }
        if isDragging {
            isDragging = false
            NSCursor.pop()
            onDragChanged?(false)
        } else if mouseDownLocation != nil {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event, self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) { onMouseMoved?() }
    override func mouseEntered(with event: NSEvent) { onMouseMoved?() }
    override func mouseExited(with event: NSEvent) { onMouseExited?() }
}

extension NSRect {
    var center: NSPoint { NSPoint(x: midX, y: midY) }
}

extension NSPoint {
    func distance(to other: NSPoint) -> CGFloat { hypot(other.x - x, other.y - y) }
    func offsetBy(dx: CGFloat = 0, dy: CGFloat = 0) -> NSPoint { NSPoint(x: x + dx, y: y + dy) }
}
