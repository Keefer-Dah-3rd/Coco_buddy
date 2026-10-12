import AppKit
import QuartzCore
import BuddyCharacter

/// Coco: a black-and-white corgi with a white blaze, giant ears and a collar tag.
///
/// Built from Core Animation layers. Every shape is a static path created once;
/// each frame only changes transforms, opacity and a couple of small paths, and
/// the window server does the drawing — a frame costs a fraction of a millisecond.
///
/// This is the *artwork* layer: it knows nothing about states or timing. It draws
/// whatever `CharacterPose` it's given. To redesign the character, replace this view;
/// the animator and state machine stay as they are.
final class CocoLayerView: NSView {
    /// Shrinks the character toward its feet (compact presence / small focus mode).
    var characterScale: CGFloat = 1 {
        didSet { if characterScale != oldValue { updateRootTransform(animated: true) } }
    }

    /// The design is authored in a 100 × 100 unit box with y pointing down.
    private let root = CALayer()
    private let groundShadow = CAShapeLayer()
    /// Everything that hops and squashes; origin at the bottom-centre of the body.
    private let body = CALayer()
    private let tail = CALayer()
    private let legs = [CALayer(), CALayer()]
    private let tagLight = CAShapeLayer()
    private let tagGlow = CAShapeLayer()
    private let progressTrack = CAShapeLayer()
    private let progressRing = CAShapeLayer()
    /// Head group; origin at the neck so tilts pivot naturally.
    private let head = CALayer()
    private let ears = [CALayer(), CALayer()]
    private let eyes = [Eye(), Eye()]
    private let mouthInside = CAShapeLayer()
    private let tongue = CALayer()
    private let mouthLine = CAShapeLayer()
    private let thoughtDots = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    private let sleepZ = (0..<3).map { _ in (halo: CAShapeLayer(), ink: CAShapeLayer()) }
    private let sparkles = (0..<6).map { _ in CAShapeLayer() }
    /// Coco on the move, drawn in place of the sitting artwork while she runs.
    private let runner = RunningCoco()

    private var lastMouthCurve: Double = .nan
    private static let ground: CGFloat = 93
    private static let bodyOrigin = CGPoint(x: 50, y: 91)
    private static let neck = CGPoint(x: 50, y: 57)

    private final class Eye {
        let container = CALayer()
        let open = CAShapeLayer()
        let shine = CAShapeLayer()
        let closed = CAShapeLayer()
        let happy = CAShapeLayer()
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        root.isGeometryFlipped = true
        root.masksToBounds = false
        // sublayerTransform applies around the anchor point; anchor at the origin so the
        // unit-box mapping in `updateRootTransform` is measured from the top-left.
        root.anchorPoint = .zero
        layer?.addSublayer(root)
        build()
        setContentsScale(3)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.frame = bounds
        updateRootTransform(animated: false)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        setContentsScale((window?.backingScaleFactor ?? 2) * 1.5)
    }

    // MARK: - Per-frame update

    func render(_ p: CharacterPose, focusProgress: Double?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let lift = CGFloat(p.lift)
        let dangle = CGFloat(p.dangle)
        let run = CGFloat(min(1, max(0, p.run)))

        // While she runs, the running Coco takes over from the sitting drawing.
        body.opacity = Float(1 - run)
        runner.layer.isHidden = run < 0.001
        if run >= 0.001 {
            runner.layer.opacity = Float(run)
            runner.render(p)
        }

        // Contact shadow: shrinks and fades as Coco leaves the ground.
        let air = min(1, lift / 14)
        groundShadow.opacity = Float(0.22 * (1 - air * 0.6) * (1 - dangle) * (1 - run))
        groundShadow.setAffineTransform(CGAffineTransform(scaleX: 1 - air * 0.35, y: 1))

        // Squash/stretch anchored at the paws, then tilt around the same point.
        body.position = CGPoint(x: Self.bodyOrigin.x, y: Self.bodyOrigin.y - lift)
        body.transform = CATransform3DConcat(
            CATransform3DMakeScale(1 + p.squash, 1 - p.squash, 1),
            CATransform3DMakeRotation(p.tilt, 0, 0, 1)
        )

        tail.setAffineTransform(CGAffineTransform(rotationAngle: 0.75 + p.tail + dangle * 1.5))
        for (index, leg) in legs.enumerated() {
            let swing = dangle * 0.22 * sin(p.clock * 7 + Double(index) * 1.7)
            leg.setAffineTransform(CGAffineTransform(translationX: 0, y: 3 * dangle).rotated(by: swing))
        }

        head.position = CGPoint(x: 0, y: Self.neck.y - Self.bodyOrigin.y + p.headDip)
        head.setAffineTransform(CGAffineTransform(rotationAngle: p.headTilt))

        let relax = (1 - min(1.1, max(0, p.earPerk))) * 0.55
        ears[0].setAffineTransform(CGAffineTransform(rotationAngle: -(relax + p.earLeft)))
        ears[1].setAffineTransform(CGAffineTransform(rotationAngle: relax + p.earRight))

        renderEyes(p)
        renderMouth(p)
        renderTag(p, focusProgress: focusProgress)
        renderOverlays(p)
    }

    private func renderEyes(_ p: CharacterPose) {
        let gx = CGFloat(p.gazeX) * 1.6
        let gy = CGFloat(p.gazeY) * 1.2
        let scale = CGFloat(p.eyeScale)
        let happy = Self.smoothstep(0.3, 0.7, p.eyeSmile)
        let openness = Self.smoothstep(0.12, 0.45, p.eyeOpen)

        for (index, eye) in eyes.enumerated() {
            eye.container.position = CGPoint(x: (index == 0 ? -9.5 : 9.5) + gx, y: -22 + gy)
            eye.open.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale * max(0.08, min(1, p.eyeOpen))))
            eye.open.opacity = Float(openness * (1 - happy))
            eye.closed.opacity = Float((1 - openness) * (1 - happy))
            eye.happy.opacity = Float(happy)
            eye.happy.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        }
    }

    private func renderMouth(_ p: CharacterPose) {
        let open = CGFloat(max(0, p.mouthOpen))
        let tongueOut = CGFloat(min(1, max(0, p.tongue)))
        let mouthTop = CGPoint(x: 0, y: 47 - Self.neck.y)

        // One fixed ellipse, scaled — cheaper than a new path every frame.
        mouthInside.isHidden = open < 0.04
        mouthInside.position = CGPoint(x: mouthTop.x, y: mouthTop.y - 0.6)
        mouthInside.setAffineTransform(CGAffineTransform(scaleX: (6.5 + 3 * open) / 9.5, y: max(0.01, (1 + 6 * open) / 7)))

        tongue.isHidden = tongueOut < 0.02 && open < 0.2
        let tongueLength = 2 + 7 * tongueOut + 2 * open
        tongue.bounds = CGRect(x: 0, y: 0, width: 5.2, height: tongueLength)
        tongue.position = CGPoint(x: mouthTop.x, y: mouthTop.y + 0.8)

        if abs(p.mouthCurve - lastMouthCurve) > 0.01 || lastMouthCurve.isNaN {
            lastMouthCurve = p.mouthCurve
            let c = CGFloat(p.mouthCurve)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: -2.4))
            path.addLine(to: .zero)
            path.addQuadCurve(to: CGPoint(x: -5, y: -0.8 - 0.6 * c), control: CGPoint(x: -2.5, y: 2.2 + 1.4 * c))
            path.move(to: .zero)
            path.addQuadCurve(to: CGPoint(x: 5, y: -0.8 - 0.6 * c), control: CGPoint(x: 2.5, y: 2.2 + 1.4 * c))
            mouthLine.path = path
        }
        mouthLine.position = mouthTop
    }

    private func renderTag(_ p: CharacterPose, focusProgress: Double?) {
        let led = Float(min(1, max(0, p.led)))
        tagLight.opacity = led
        tagGlow.opacity = 0.35 * led
        progressTrack.isHidden = focusProgress == nil
        progressRing.isHidden = focusProgress == nil
        if let focusProgress {
            progressRing.strokeEnd = CGFloat(min(1, max(0.001, focusProgress)))
        }
    }

    private func renderOverlays(_ p: CharacterPose) {
        // Thought dots float up one after another.
        let thinking = Float(min(1, max(0, p.thinking)))
        let step = Int(Self.fract(p.clock * 0.9) * 4)
        for (index, dot) in thoughtDots.enumerated() {
            dot.isHidden = thinking < 0.01
            dot.opacity = thinking * (index < step ? 1 : 0.15)
        }

        for (index, z) in sleepZ.enumerated() {
            let visible = p.sleepZ > 0.01
            z.halo.isHidden = !visible
            z.ink.isHidden = !visible
            guard visible else { continue }
            let phase = Self.fract(p.clock * 0.32 + Double(index) / 3)
            let size = CGFloat(4 + phase * 3.5)
            let x = CGFloat(78 + phase * 10 + sin(phase * 6) * 1.5)
            let y = CGFloat(28 - phase * 22)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x - size / 2, y: y - size / 2))
            path.addLine(to: CGPoint(x: x + size / 2, y: y - size / 2))
            path.addLine(to: CGPoint(x: x - size / 2, y: y + size / 2))
            path.addLine(to: CGPoint(x: x + size / 2, y: y + size / 2))
            let opacity = Float(sin(phase * .pi) * p.sleepZ)
            for layer in [z.halo, z.ink] {
                layer.path = path
                layer.opacity = opacity
            }
        }

        for (index, sparkle) in sparkles.enumerated() {
            let phase = Self.fract(p.clock * 1.3 + Double(index) * 0.37)
            let s = CGFloat(sin(phase * .pi) * p.sparkles)
            sparkle.isHidden = s < 0.05
            guard s >= 0.05 else { continue }
            let angle = Double(index) / 6 * 2 * .pi + 0.4
            let radius = 43 + phase * 5
            sparkle.position = CGPoint(x: 50 + cos(angle) * radius, y: 50 + sin(angle) * radius * 0.85)
            sparkle.setAffineTransform(CGAffineTransform(scaleX: s, y: s))
        }
    }

    private func updateRootTransform(animated: Bool) {
        // Map the unit box into the view, scaled toward the bottom-centre (the paws).
        let size = bounds.size
        let s = size.width / 100 * characterScale
        let transform = CATransform3DConcat(
            CATransform3DMakeScale(s, s, 1),
            CATransform3DMakeTranslation(size.width / 2 - 50 * s, size.height - 100 * s, 0)
        )
        if animated {
            let spring = CASpringAnimation(keyPath: "sublayerTransform")
            spring.fromValue = root.presentation()?.sublayerTransform ?? root.sublayerTransform
            spring.toValue = transform
            spring.damping = 14
            spring.stiffness = 180
            spring.duration = spring.settlingDuration
            root.add(spring, forKey: "scale")
        }
        root.sublayerTransform = transform
    }

    private func setContentsScale(_ scale: CGFloat) {
        root.allSublayers.forEach { $0.contentsScale = scale }
    }

    private static func fract(_ x: Double) -> Double {
        x - x.rounded(.down)
    }

    private static func smoothstep(_ lower: Double, _ upper: Double, _ x: Double) -> Double {
        let k = min(1, max(0, (x - lower) / (upper - lower)))
        return k * k * (3 - 2 * k)
    }
}

// MARK: - Shared outlines

/// Shapes the running Coco reuses, so both drawings have the very same ears and eyes.
extension CocoLayerView {
    /// One ear's outline, its base at the origin and its tip leaning toward −x (y down).
    static let earOutline: CGPath = {
        let outer = CGMutablePath()
        outer.move(to: CGPoint(x: -9, y: 3))
        outer.addCurve(to: CGPoint(x: -6.5, y: -23.5), control1: CGPoint(x: -12.5, y: -6), control2: CGPoint(x: -10.5, y: -18))
        outer.addQuadCurve(to: CGPoint(x: -2.6, y: -22), control: CGPoint(x: -4.5, y: -26.5))
        outer.addCurve(to: CGPoint(x: 9, y: 1), control1: CGPoint(x: 1.5, y: -15), control2: CGPoint(x: 6, y: -6))
        outer.closeSubpath()
        return outer
    }()

    /// The darker inside of the ear, in the same coordinates as `earOutline`.
    static let earInside: CGPath = {
        let inner = CGMutablePath()
        inner.move(to: CGPoint(x: -5.8, y: 0))
        inner.addCurve(to: CGPoint(x: -5.4, y: -18), control1: CGPoint(x: -8.4, y: -6), control2: CGPoint(x: -7.6, y: -14))
        inner.addQuadCurve(to: CGPoint(x: -3.2, y: -17), control: CGPoint(x: -4.2, y: -20.2))
        inner.addCurve(to: CGPoint(x: 4.8, y: -0.5), control1: CGPoint(x: -0.4, y: -11), control2: CGPoint(x: 3, y: -5))
        inner.closeSubpath()
        return inner
    }()

    /// A closed eye, centred on the origin (y down).
    static let closedEye: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -3.3, y: 0))
        path.addQuadCurve(to: CGPoint(x: 3.3, y: 0), control: CGPoint(x: 0, y: 2.4))
        return path
    }()

    /// A happy "^" eye, centred on the origin (y down).
    static let happyEye: CGPath = {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -3.4, y: 1.4))
        path.addQuadCurve(to: CGPoint(x: 3.4, y: 1.4), control: CGPoint(x: 0, y: -3.4))
        return path
    }()
}

// MARK: - Construction

/// Coco's colors come from the design tokens (Figma collection “Brand”).
private typealias Palette = BrandPalette

private extension CocoLayerView {
    /// Paths are drawn in absolute unit-box coordinates, then shifted into a group's space.
    static func shifted(_ path: CGPath, by origin: CGPoint) -> CGPath {
        var transform = CGAffineTransform(translationX: -origin.x, y: -origin.y)
        return path.copy(using: &transform) ?? path
    }

    static func shape(_ path: CGPath, fill: NSColor?, stroke: NSColor? = nil, width: CGFloat = 0.9) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.path = path
        layer.fillColor = fill?.cgColor
        layer.strokeColor = stroke?.cgColor
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    static func ellipse(_ rect: CGRect) -> CGPath {
        CGPath(ellipseIn: rect, transform: nil)
    }

    func build() {
        groundShadow.path = Self.ellipse(CGRect(x: -29, y: -2.5, width: 58, height: 5))
        groundShadow.fillColor = NSColor.black.cgColor
        groundShadow.position = CGPoint(x: 50, y: Self.ground)
        root.addSublayer(groundShadow)

        root.addSublayer(body)
        buildTail()
        buildBody()
        buildCollar()
        buildHead()
        runner.layer.isHidden = true
        root.addSublayer(runner.layer)
        buildOverlays()
    }

    func buildTail() {
        // A fluffy tail peeking out behind her right side; pivots at its base.
        let fluff = CGMutablePath()
        fluff.move(to: CGPoint(x: -3.6, y: 0))
        fluff.addCurve(to: CGPoint(x: -1, y: -21), control1: CGPoint(x: -7.5, y: -7), control2: CGPoint(x: -6, y: -16))
        fluff.addQuadCurve(to: CGPoint(x: 3, y: -20.5), control: CGPoint(x: 1.5, y: -24.5))
        fluff.addCurve(to: CGPoint(x: 3.6, y: 0), control1: CGPoint(x: 6.2, y: -14), control2: CGPoint(x: 6.5, y: -6))
        fluff.closeSubpath()
        let tip = CGMutablePath()
        tip.move(to: CGPoint(x: -3.6, y: -15))
        tip.addCurve(to: CGPoint(x: -1, y: -21), control1: CGPoint(x: -4.8, y: -17.5), control2: CGPoint(x: -3, y: -20))
        tip.addQuadCurve(to: CGPoint(x: 3, y: -20.5), control: CGPoint(x: 1.5, y: -24.5))
        tip.addCurve(to: CGPoint(x: 4.8, y: -15), control1: CGPoint(x: 4.4, y: -19), control2: CGPoint(x: 4.9, y: -17))
        tip.addQuadCurve(to: CGPoint(x: -3.6, y: -15), control: CGPoint(x: 0.6, y: -13.2))
        tip.closeSubpath()

        tail.position = CGPoint(x: 69 - Self.bodyOrigin.x, y: 83 - Self.bodyOrigin.y)
        tail.addSublayer(Self.shape(fluff, fill: Palette.fur, stroke: Palette.rim))
        tail.addSublayer(Self.shape(tip, fill: Palette.white))
        body.addSublayer(tail)
    }

    func buildBody() {
        let o = Self.bodyOrigin
        let silhouette = CGMutablePath()
        silhouette.move(to: CGPoint(x: 36, y: 57))
        silhouette.addCurve(to: CGPoint(x: 25.5, y: 84), control1: CGPoint(x: 28, y: 63), control2: CGPoint(x: 24.5, y: 74))
        silhouette.addCurve(to: CGPoint(x: 32, y: 91), control1: CGPoint(x: 26, y: 89), control2: CGPoint(x: 28.5, y: 91))
        silhouette.addLine(to: CGPoint(x: 68, y: 91))
        silhouette.addCurve(to: CGPoint(x: 74.5, y: 84), control1: CGPoint(x: 71.5, y: 91), control2: CGPoint(x: 74, y: 89))
        silhouette.addCurve(to: CGPoint(x: 64, y: 57), control1: CGPoint(x: 75.5, y: 74), control2: CGPoint(x: 72, y: 63))
        silhouette.closeSubpath()
        body.addSublayer(Self.shape(Self.shifted(silhouette, by: o), fill: Palette.fur, stroke: Palette.rim))

        // Haunch lines give the sitting pose some depth.
        let haunches = CGMutablePath()
        haunches.move(to: CGPoint(x: 28.5, y: 75))
        haunches.addQuadCurve(to: CGPoint(x: 35, y: 90), control: CGPoint(x: 36.5, y: 79))
        haunches.move(to: CGPoint(x: 71.5, y: 75))
        haunches.addQuadCurve(to: CGPoint(x: 65, y: 90), control: CGPoint(x: 63.5, y: 79))
        body.addSublayer(Self.shape(Self.shifted(haunches, by: o), fill: nil, stroke: Palette.rim, width: 0.8))

        let bib = CGMutablePath()
        bib.move(to: CGPoint(x: 40.5, y: 60))
        bib.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 38.5, y: 72), control2: CGPoint(x: 44, y: 84))
        bib.addCurve(to: CGPoint(x: 59.5, y: 60), control1: CGPoint(x: 56, y: 84), control2: CGPoint(x: 61.5, y: 72))
        bib.addQuadCurve(to: CGPoint(x: 40.5, y: 60), control: CGPoint(x: 50, y: 63))
        bib.closeSubpath()
        body.addSublayer(Self.shape(Self.shifted(bib, by: o), fill: Palette.white))

        // Front legs with white paws; each hangs from its top for the "carried" dangle.
        for (index, x) in [CGFloat(38.5), 54].enumerated() {
            let leg = legs[index]
            leg.position = CGPoint(x: x + 3.75 - o.x, y: 72 - o.y)
            let local = CGPoint(x: x + 3.75, y: 72)
            let column = CGPath(roundedRect: CGRect(x: x, y: 72, width: 7.5, height: 17.5), cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
            leg.addSublayer(Self.shape(Self.shifted(column, by: local), fill: Palette.white, stroke: Palette.whiteEdge, width: 0.7))
            let paw = Self.ellipse(CGRect(x: x - 1.8, y: 86.3, width: 11, height: 6.4))
            leg.addSublayer(Self.shape(Self.shifted(paw, by: local), fill: Palette.white, stroke: Palette.whiteEdge, width: 0.7))
            let toes = CGMutablePath()
            for toeX in [x + 1.9, x + 5.6] {
                toes.move(to: CGPoint(x: toeX, y: 89.6))
                toes.addLine(to: CGPoint(x: toeX, y: 91.6))
            }
            leg.addSublayer(Self.shape(Self.shifted(toes, by: local), fill: nil, stroke: Palette.whiteEdge, width: 0.6))
            body.addSublayer(leg)
        }
    }

    func buildCollar() {
        let o = Self.bodyOrigin
        let band = CGMutablePath()
        band.move(to: CGPoint(x: 33, y: 56.5))
        band.addQuadCurve(to: CGPoint(x: 67, y: 56.5), control: CGPoint(x: 50, y: 63))
        band.addLine(to: CGPoint(x: 66.5, y: 60))
        band.addQuadCurve(to: CGPoint(x: 33.5, y: 60), control: CGPoint(x: 50, y: 66.5))
        band.closeSubpath()
        body.addSublayer(Self.shape(Self.shifted(band, by: o), fill: Palette.collar, stroke: Palette.collarRim, width: 0.6))

        // The round tag on her collar doubles as Coco's status light and focus meter.
        let center = CGPoint(x: 50, y: 65.5)
        func circle(_ r: CGFloat) -> CGPath {
            Self.shifted(Self.ellipse(CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)), by: o)
        }
        tagGlow.path = circle(7.5)
        tagGlow.fillColor = Palette.accent.cgColor
        body.addSublayer(tagGlow)
        body.addSublayer(Self.shape(circle(4.6), fill: Palette.collar, stroke: Palette.collarRim, width: 0.6))
        body.addSublayer(Self.shape(circle(3.4), fill: Palette.tagFace))
        tagLight.path = circle(1.6)
        tagLight.fillColor = Palette.accent.cgColor
        body.addSublayer(tagLight)

        // Progress ring starts at 12 o'clock and runs clockwise.
        let ring = CGMutablePath()
        let local = CGPoint(x: center.x - o.x, y: center.y - o.y)
        ring.addArc(center: local, radius: 6.3, startAngle: -.pi / 2, endAngle: 1.5 * .pi, clockwise: false)
        progressTrack.path = ring
        progressTrack.fillColor = nil
        progressTrack.strokeColor = Palette.whiteEdge.cgColor
        progressTrack.lineWidth = 1.5
        progressRing.path = ring
        progressRing.fillColor = nil
        progressRing.strokeColor = Palette.accent.cgColor
        progressRing.lineWidth = 1.5
        progressRing.lineCap = .round
        for layer in [progressTrack, progressRing] {
            layer.isHidden = true
            body.addSublayer(layer)
        }
    }

    func buildHead() {
        let n = Self.neck
        body.addSublayer(head)

        // Ears first, so the head covers their bases.
        let outer = Self.earOutline
        let inner = Self.earInside
        for (index, ear) in ears.enumerated() {
            let mirror = index == 0 ? CGFloat(1) : -1
            let base = CGPoint(x: index == 0 ? 35 : 65, y: 25)
            ear.position = CGPoint(x: base.x - n.x, y: base.y - n.y)
            var flip = CGAffineTransform(scaleX: mirror, y: 1)
            ear.addSublayer(Self.shape(outer.copy(using: &flip)!, fill: Palette.fur, stroke: Palette.rim))
            ear.addSublayer(Self.shape(inner.copy(using: &flip)!, fill: Palette.innerEar))
            head.addSublayer(ear)
        }

        let skull = CGMutablePath()
        skull.move(to: CGPoint(x: 50, y: 17))
        skull.addCurve(to: CGPoint(x: 27, y: 31), control1: CGPoint(x: 36, y: 17), control2: CGPoint(x: 28, y: 22))
        skull.addCurve(to: CGPoint(x: 31, y: 51), control1: CGPoint(x: 26, y: 40), control2: CGPoint(x: 27, y: 46))
        skull.addCurve(to: CGPoint(x: 50, y: 58), control1: CGPoint(x: 35, y: 56), control2: CGPoint(x: 42, y: 58))
        skull.addCurve(to: CGPoint(x: 69, y: 51), control1: CGPoint(x: 58, y: 58), control2: CGPoint(x: 65, y: 56))
        skull.addCurve(to: CGPoint(x: 73, y: 31), control1: CGPoint(x: 73, y: 46), control2: CGPoint(x: 74, y: 40))
        skull.addCurve(to: CGPoint(x: 50, y: 17), control1: CGPoint(x: 72, y: 22), control2: CGPoint(x: 64, y: 17))
        skull.closeSubpath()
        head.addSublayer(Self.shape(Self.shifted(skull, by: n), fill: Palette.fur, stroke: Palette.rim))

        // White blaze running down into the muzzle.
        let blaze = CGMutablePath()
        blaze.move(to: CGPoint(x: 48.6, y: 19.5))
        blaze.addQuadCurve(to: CGPoint(x: 51.4, y: 19.5), control: CGPoint(x: 50, y: 18.6))
        blaze.addCurve(to: CGPoint(x: 55.5, y: 41), control1: CGPoint(x: 52.2, y: 28), control2: CGPoint(x: 53.5, y: 36))
        blaze.addLine(to: CGPoint(x: 44.5, y: 41))
        blaze.addCurve(to: CGPoint(x: 48.6, y: 19.5), control1: CGPoint(x: 46.5, y: 36), control2: CGPoint(x: 47.8, y: 28))
        blaze.closeSubpath()
        head.addSublayer(Self.shape(Self.shifted(blaze, by: n), fill: Palette.white))

        let muzzle = CGMutablePath()
        muzzle.move(to: CGPoint(x: 50, y: 38.5))
        muzzle.addCurve(to: CGPoint(x: 38.5, y: 46.5), control1: CGPoint(x: 43, y: 38.5), control2: CGPoint(x: 38.5, y: 41.5))
        muzzle.addCurve(to: CGPoint(x: 50, y: 55.5), control1: CGPoint(x: 38.5, y: 52), control2: CGPoint(x: 44, y: 55.5))
        muzzle.addCurve(to: CGPoint(x: 61.5, y: 46.5), control1: CGPoint(x: 56, y: 55.5), control2: CGPoint(x: 61.5, y: 52))
        muzzle.addCurve(to: CGPoint(x: 50, y: 38.5), control1: CGPoint(x: 61.5, y: 41.5), control2: CGPoint(x: 57, y: 38.5))
        muzzle.closeSubpath()
        head.addSublayer(Self.shape(Self.shifted(muzzle, by: n), fill: Palette.white))

        buildEyes()

        mouthInside.path = Self.ellipse(CGRect(x: -4.75, y: 0, width: 9.5, height: 7))
        mouthInside.fillColor = Palette.mouthInside.cgColor
        head.addSublayer(mouthInside)
        tongue.backgroundColor = Palette.tongue.cgColor
        tongue.cornerRadius = 2.6
        tongue.anchorPoint = CGPoint(x: 0.5, y: 0)
        let groove = CALayer()
        groove.frame = CGRect(x: 2.35, y: 1, width: 0.5, height: 3)
        groove.backgroundColor = Palette.tongueGroove.cgColor
        tongue.addSublayer(groove)
        head.addSublayer(tongue)
        mouthLine.fillColor = nil
        mouthLine.strokeColor = Palette.mouthLine.cgColor
        mouthLine.lineWidth = 1.1
        mouthLine.lineCap = .round
        head.addSublayer(mouthLine)

        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: 45.4, y: 40.2))
        nose.addCurve(to: CGPoint(x: 54.6, y: 40.2), control1: CGPoint(x: 47, y: 38.4), control2: CGPoint(x: 53, y: 38.4))
        nose.addCurve(to: CGPoint(x: 50, y: 44.8), control1: CGPoint(x: 55.2, y: 42.2), control2: CGPoint(x: 52.2, y: 44.8))
        nose.addCurve(to: CGPoint(x: 45.4, y: 40.2), control1: CGPoint(x: 47.8, y: 44.8), control2: CGPoint(x: 44.8, y: 42.2))
        nose.closeSubpath()
        head.addSublayer(Self.shape(Self.shifted(nose, by: n), fill: Palette.nose))
        head.addSublayer(Self.shape(Self.shifted(Self.ellipse(CGRect(x: 46.6, y: 39.4, width: 2.8, height: 1.3)), by: n),
                                    fill: NSColor.white.withAlphaComponent(0.55)))
    }

    func buildEyes() {
        let closedPath = Self.closedEye
        let happyPath = Self.happyEye

        for eye in eyes {
            eye.open.path = Self.ellipse(CGRect(x: -3.3, y: -3.7, width: 6.6, height: 7.4))
            eye.open.fillColor = Palette.eye.cgColor
            eye.open.strokeColor = Palette.eyeRim.cgColor
            eye.open.lineWidth = 0.7
            eye.shine.path = Self.ellipse(CGRect(x: 0.2, y: -2.8, width: 2.2, height: 2.2))
            eye.shine.fillColor = NSColor.white.withAlphaComponent(0.9).cgColor
            eye.open.addSublayer(eye.shine)
            let glint = Self.shape(Self.ellipse(CGRect(x: -1.9, y: 1.1, width: 1, height: 1)), fill: NSColor.white.withAlphaComponent(0.5))
            eye.open.addSublayer(glint)

            eye.closed.path = closedPath
            eye.closed.fillColor = nil
            eye.closed.strokeColor = Palette.closedEye.cgColor
            eye.closed.lineWidth = 1.3
            eye.closed.lineCap = .round
            eye.happy.path = happyPath
            eye.happy.fillColor = nil
            eye.happy.strokeColor = Palette.closedEye.cgColor
            eye.happy.lineWidth = 1.5
            eye.happy.lineCap = .round

            for layer in [eye.open, eye.closed, eye.happy] { eye.container.addSublayer(layer) }
            head.addSublayer(eye.container)
        }
    }

    func buildOverlays() {
        for (index, dot) in thoughtDots.enumerated() {
            let r = [1.5, 2.1, 2.8][index]
            let center = [CGPoint(x: 76, y: 15), CGPoint(x: 81.5, y: 9.5), CGPoint(x: 88.5, y: 4.5)][index]
            dot.path = Self.ellipse(CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            dot.fillColor = Palette.white.cgColor
            dot.strokeColor = Palette.rim.cgColor
            dot.lineWidth = 0.7
            dot.isHidden = true
            root.addSublayer(dot)
        }
        for z in sleepZ {
            z.halo.strokeColor = Palette.white.cgColor
            z.halo.lineWidth = 3.4
            z.ink.strokeColor = Palette.ink.cgColor
            z.ink.lineWidth = 1.5
            for layer in [z.halo, z.ink] {
                layer.fillColor = nil
                layer.lineCap = .round
                layer.lineJoin = .round
                layer.isHidden = true
                root.addSublayer(layer)
            }
        }
        let plus = CGMutablePath()
        plus.addRect(CGRect(x: -3.5, y: -0.9, width: 7, height: 1.8))
        plus.addRect(CGRect(x: -0.9, y: -3.5, width: 1.8, height: 7))
        for sparkle in sparkles {
            sparkle.path = plus
            sparkle.fillColor = Palette.accent.cgColor
            sparkle.isHidden = true
            root.addSublayer(sparkle)
        }
    }
}

private extension CALayer {
    var allSublayers: [CALayer] {
        (sublayers ?? []).flatMap { [$0] + $0.allSublayers }
    }
}
