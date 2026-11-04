import AppKit
import QuartzCore
import BuddyCore

/// Draws one illustrated banner with Core Animation and moves it between states.
///
/// Every change builds the new frame's layers and fades them in over the old ones, so nothing
/// ever pops: a new light or weather dissolves in over `BannerMotion.lookChange`; a task done
/// lights its window or hangs its laundry over `progressChange` while the thumb (and the ferry)
/// slide to the new share. The banner's size never depends on its content, so changes never
/// move the layout around it.
final class BannerSceneView: NSView {
    private struct Frame {
        let state: BannerState
        let root: CALayer
        let movers: [BannerLayerBuilder.Mover]
        let railFill: CALayer?
    }

    private var frames: [Frame] = []
    private(set) var state: BannerState?
    /// When ambient loops count from, shared by every frame so crossfades stay in step.
    private let epoch = CACurrentMediaTime()
    private var builtWidth: CGFloat = 0
    private var builtScale: CGFloat = 0
    /// For snapshots: no ambient motion, so a still shows the art at rest.
    var staticOnly = false
    /// For snapshots: draw at this backing scale whatever the screen is.
    var renderScale: CGFloat?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(displayOptionsChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    @objc private func displayOptionsChanged() {
        rebuild()
    }

    override func layout() {
        super.layout()
        if bounds.width != builtWidth { rebuild() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if (window?.backingScaleFactor ?? 2) != builtScale { rebuild() }
    }

    /// Shows `new`, moving there from whatever is on screen.
    func show(_ new: BannerState, animated: Bool) {
        guard new != state else { return }
        let old = state
        state = new
        guard let old, animated, bounds.width > 0, !frames.isEmpty else {
            rebuild()
            return
        }
        let lookChanged = old.look != new.look
        let duration = lookChanged ? BannerMotion.lookChange : BannerMotion.progressChange
        let slides = !reduceMotion && old.progress != new.progress

        // Where the moving parts are on screen right now, before anything changes.
        let top = frames.last
        let thumbFrom = top.flatMap { offset(of: .thumb, in: $0) }
        let journeyFrom = top.flatMap { offset(of: .ferryJourney, in: $0) }
        let fillFrom = top?.railFill.flatMap { $0.presentation()?.bounds.width ?? $0.bounds.width }

        guard let frame = makeFrame(new) else { return }
        // Old frames slide along with the new one, so nothing ghosts while the new one fades in.
        for each in frames + [frame] {
            for mover in each.movers where mover.motion == .thumb || mover.motion == .ferryJourney {
                let target = targetOffset(mover.motion, in: frame)
                let from = mover.motion == .thumb ? thumbFrom : journeyFrom
                if slides {
                    BannerMotion.slide(mover.layer, to: target, duration: mover.motion == .thumb ? BannerMotion.thumbSlide : BannerMotion.journeySlide, from: from)
                } else {
                    setOffset(mover.layer, target)
                }
            }
            if let fill = each.railFill, let target = frame.railFill?.bounds.width {
                if slides { BannerMotion.resize(fill, to: target, duration: BannerMotion.thumbSlide, from: fillFrom) }
                else { CATransaction.withoutActions { fill.bounds.size.width = target } }
            }
        }

        frame.root.opacity = 0
        layer?.addSublayer(frame.root)
        frames.append(frame)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = BannerMotion.easeInOut
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in self?.settle(on: frame.root) }
        frame.root.opacity = 1
        frame.root.add(fade, forKey: "banner.fade")
        CATransaction.commit()
    }

    /// Drops the frames under `root` once it has fully faded in (unless it's been replaced since).
    private func settle(on root: CALayer) {
        guard let index = frames.firstIndex(where: { $0.root === root }) else { return }
        for old in frames[..<index] { old.root.removeFromSuperlayer() }
        frames.removeFirst(index)
    }

    private func rebuild() {
        guard let state, bounds.width > 0 else { return }
        for frame in frames { frame.root.removeFromSuperlayer() }
        frames = []
        guard let frame = makeFrame(state) else { return }
        layer?.addSublayer(frame.root)
        frames = [frame]
    }

    private func makeFrame(_ state: BannerState) -> Frame? {
        guard bounds.width > 0 else { return nil }
        let scale = renderScale ?? window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        builtWidth = bounds.width
        builtScale = scale
        var builder = BannerLayerBuilder(document: BannerArt.document(state), width: bounds.width)
        let result = CATransaction.withoutActions { builder.build() }
        result.root.setContentsScaleRecursively(scale)
        if !reduceMotion, !staticOnly {
            BannerMotion.startAmbient(result.movers, scale: builder.scale, epoch: epoch)
        }
        return Frame(state: state, root: result.root, movers: result.movers, railFill: result.railFill)
    }

    private func offset(of motion: BannerArt.Motion, in frame: Frame) -> CGFloat? {
        guard let layer = frame.movers.first(where: { $0.motion == motion })?.layer else { return nil }
        return (layer.presentation() ?? layer).value(forKeyPath: "transform.translation.x") as? CGFloat
    }

    private func targetOffset(_ motion: BannerArt.Motion, in frame: Frame) -> CGFloat {
        frame.movers.first { $0.motion == motion }?.offsetX ?? 0
    }

    private func setOffset(_ layer: CALayer, _ x: CGFloat) {
        CATransaction.withoutActions {
            layer.removeAnimation(forKey: "banner.slide")
            layer.transform = CATransform3DMakeTranslation(x, 0, 0)
        }
    }

    #if DEBUG
    /// Self-test: the layers playing `motion` in the frame on top.
    func movers(_ motion: BannerArt.Motion) -> [CALayer] {
        frames.last?.movers.filter { $0.motion == motion }.map(\.layer) ?? []
    }
    #endif

    // MARK: Accessibility (the SwiftUI card labels the whole banner)

    override func isAccessibilityElement() -> Bool { false }
}

extension CATransaction {
    static func withoutActions<T>(_ body: () -> T) -> T {
        begin()
        setDisableActions(true)
        defer { commit() }
        return body()
    }
}

extension CALayer {
    func setContentsScaleRecursively(_ scale: CGFloat) {
        contentsScale = scale
        mask?.setContentsScaleRecursively(scale)
        sublayers?.forEach { $0.setContentsScaleRecursively(scale) }
    }
}
