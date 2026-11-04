import AppKit
import QuartzCore
import BuddyCore

/// The banners' motion, taken from the Figma Make file's CSS (`src/index.css`): the same
/// durations, easing and distances, played by Core Animation in the window server so they cost
/// the app nothing per frame.
///
/// | Class            | What moves                      | How (scene units)                     | Time   | Easing         |
/// |------------------|---------------------------------|---------------------------------------|--------|----------------|
/// | vector-cloud     | clouds                          | x 0 → 7, back                         | 9 s    | ease-in-out    |
/// | vector-star      | stars (night)                   | opacity .2 → 1, scale .7 → 1.1, back  | 3 s    | ease-in-out    |
/// | vector-rainfall  | rain                            | (3,−10) → (−3,25); opacity 0 → .7 → 0 | 1.2 s  | linear         |
/// | vector-snowfall  | snow                            | (−2,−4) → (8,42); opacity .1 → .9 → 0 | 4 s    | ease-in-out    |
/// | vector-gust      | wind lines                      | x 0 → 7, back                         | 3 s    | ease-in-out    |
/// | vector-sway      | the nook's plant (windy)        | rotate 0 → 4°, back; about its base   | 2.5 s  | ease-in-out    |
/// | ferry-bob        | the ferry                       | y 0 → 1.5 → 0                         | 4 s    | ease-in-out    |
/// | hanging-linen    | laundry (windy)                 | rotate 0 → 6°, back; from the peg     | 3 s    | ease-in-out    |
/// | carriage-scenery | houses past the train window    | x 0 → −7, back                        | 9 s    | ease-in-out    |
/// | tea-steam        | steam off the tea               | opacity .15 → .7 → .15, y 0 → −2 → 0  | 3 s    | ease-in-out    |
/// | vector-thumb     | the rail's thumb, on progress   | slides to the new share               | 0.35 s | (.2,.8,.2,1)   |
/// | ferry-journey    | the ferry's crossing, on progress | slides to the new share             | 0.6 s  | (.2,.8,.2,1)   |
///
/// Stars twinkle about their own centres; the Make file scaled them about the SVG origin
/// (CSS's default for SVG), which sent them sliding across the sky.
/// With Reduce Motion on, nothing ambient runs and progress changes without sliding; changes
/// of light and weather still crossfade, which is the system's own reduced-motion transition.
enum BannerMotion {
    /// Crossfade between looks (another light, weather or banner).
    static let lookChange: CFTimeInterval = 1.2
    /// Crossfade when only progress changed (a window lights, laundry goes up).
    static let progressChange: CFTimeInterval = 0.35
    static let thumbSlide: CFTimeInterval = 0.35
    static let journeySlide: CFTimeInterval = 0.6
    /// The Make file's `cubic-bezier(.2,.8,.2,1)`: quick off the mark, settling gently.
    static let settle = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
    static let easeInOut = CAMediaTimingFunction(name: .easeInEaseOut)
    static let ambientKey = "banner.ambient"

    /// Starts every ambient loop on a freshly built frame. All frames share `epoch`, so during a
    /// crossfade the old and new clouds are in step and nothing appears to jump.
    static func startAmbient(_ movers: [BannerLayerBuilder.Mover], scale: CGFloat, epoch: CFTimeInterval) {
        #if BANNER_STATIC
        return  // energy A/B builds only (OTHER_SWIFT_FLAGS=-DBANNER_STATIC), see scripts/energy-check.sh
        #endif
        for mover in movers {
            guard let animation = ambient(mover.motion, scale: scale) else { continue }
            if mover.motion == .sway || mover.motion == .linen || mover.motion == .star {
                pin(mover.layer, at: mover.pivot)
            }
            animation.beginTime = epoch
            animation.isRemovedOnCompletion = false
            if #available(macOS 12, *) {
                // Slow drifts look the same at 30 fps and cost half as much to composite.
                animation.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            }
            mover.layer.add(animation, forKey: ambientKey)
        }
    }

    /// Moves a layer's anchor to `pivot` (in its superlayer's points) without moving the layer.
    private static func pin(_ layer: CALayer, at pivot: CGPoint) {
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        layer.anchorPoint = CGPoint(x: pivot.x / size.width, y: pivot.y / size.height)
        layer.position = pivot
    }

    static func ambient(_ motion: BannerArt.Motion, scale s: CGFloat) -> CAAnimation? {
        switch motion {
        case .cloud: return drift(x: 7 * s, duration: 9)
        case .gust: return drift(x: 7 * s, duration: 3)
        case .scenery: return drift(x: -7 * s, duration: 9)
        case .star:
            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.2
            opacity.toValue = 1
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.7
            grow.toValue = 1.1
            return loop([opacity, grow], duration: 3, timing: easeInOut, alternate: true)
        case .rainfall:
            return loop([
                path("transform.translation.x", [3 * s, -3 * s], [0, 1]),
                path("transform.translation.y", [-10 * s, 25 * s], [0, 1]),
                path("opacity", [0, 0.7, 0], [0, 0.25, 1]),
            ], duration: 1.2, timing: CAMediaTimingFunction(name: .linear), alternate: false)
        case .snowfall:
            return loop([
                path("transform.translation.x", [-2 * s, 8 * s], [0, 1], easeInOut),
                path("transform.translation.y", [-4 * s, 42 * s], [0, 1], easeInOut),
                path("opacity", [0.1, 0.9, 0], [0, 0.3, 1], easeInOut),
            ], duration: 4, timing: nil, alternate: false)
        case .sway: return turn(degrees: 4, duration: 2.5)
        case .linen: return turn(degrees: 6, duration: 3)
        case .ferryBob:
            return loop([path("transform.translation.y", [0, 1.5 * s, 0], [0, 0.5, 1], easeInOut)],
                        duration: 4, timing: nil, alternate: false)
        case .steam:
            return loop([
                path("opacity", [0.15, 0.7, 0.15], [0, 0.5, 1], easeInOut),
                path("transform.translation.y", [0, -2 * s, 0], [0, 0.5, 1], easeInOut),
            ], duration: 3, timing: nil, alternate: false)
        case .ferryJourney, .thumb:
            return nil
        }
    }

    private static func drift(x: CGFloat, duration: CFTimeInterval) -> CAAnimation {
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = 0
        move.toValue = x
        return loop([move], duration: duration, timing: easeInOut, alternate: true)
    }

    private static func turn(degrees: CGFloat, duration: CFTimeInterval) -> CAAnimation {
        let turn = CABasicAnimation(keyPath: "transform.rotation.z")
        turn.fromValue = 0
        turn.toValue = degrees * .pi / 180
        return loop([turn], duration: duration, timing: easeInOut, alternate: true)
    }

    /// A keyframed property, eased per segment like a CSS keyframe list.
    private static func path(_ keyPath: String, _ values: [CGFloat], _ times: [Double],
                             _ timing: CAMediaTimingFunction? = nil) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values.map { NSNumber(value: Double($0)) }
        animation.keyTimes = times.map { NSNumber(value: $0) }
        if let timing { animation.timingFunctions = Array(repeating: timing, count: max(1, values.count - 1)) }
        return animation
    }

    private static func loop(_ parts: [CAAnimation], duration: CFTimeInterval, timing: CAMediaTimingFunction?,
                             alternate: Bool) -> CAAnimation {
        let group = CAAnimationGroup()
        for part in parts { part.duration = duration }
        group.animations = parts
        group.duration = duration
        group.autoreverses = alternate
        group.repeatCount = .infinity
        if let timing { group.timingFunction = timing }
        return group
    }

    // MARK: Progress

    /// Slides a thumb or the ferry to its new place, starting from wherever it is on screen now.
    static func slide(_ layer: CALayer, to offset: CGFloat, duration: CFTimeInterval, from start: CGFloat?) {
        let from = start ?? layer.presentation()?.value(forKeyPath: "transform.translation.x") as? CGFloat ?? offset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = CATransform3DMakeTranslation(offset, 0, 0)
        CATransaction.commit()
        guard abs(from - offset) > 0.01 else { return }
        let move = CABasicAnimation(keyPath: "transform.translation.x")
        move.fromValue = from
        move.toValue = offset
        move.duration = duration
        move.timingFunction = settle
        layer.add(move, forKey: "banner.slide")
    }

    /// Grows or shrinks the rail's done fill to `width` points.
    static func resize(_ layer: CALayer, to width: CGFloat, duration: CFTimeInterval, from start: CGFloat?) {
        let from = start ?? layer.presentation()?.bounds.width ?? layer.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.bounds.size.width = width
        CATransaction.commit()
        guard abs(from - width) > 0.01 else { return }
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = from
        grow.toValue = width
        grow.duration = duration
        grow.timingFunction = settle
        layer.add(grow, forKey: "banner.slide")
    }
}
