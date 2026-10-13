import AppKit
import QuartzCore
import BuddyCharacter

/// Coco on the run.
///
/// The sitting artwork is one front-facing drawing, but running needs her from every
/// side. So this builds her as a small 3D model — ellipsoids for her body and head,
/// capsules for her legs and tail, flat cards for those ears, markings laid on the
/// surfaces — looks at it through a fixed camera aimed down at the desktop "floor", and
/// redraws every part as a flat shape each frame in her palette and outline style. Any
/// heading works, so turning from one direction to the next blends by nature.
///
/// Parts are painted far to near. Each region (body, head and ears, a leg, the tail, the
/// collar) shares one outline, drawn behind all of the region's fills, so every region has
/// a single clean silhouette edge like the hand-drawn Coco.
///
/// Coordinates are `CocoLayerView`'s 100-unit box (y down), with the ground point under
/// her body at (50, 93) — where the sitting Coco's paws are.
final class RunningCoco {
    let layer = CALayer()

    private let shadow = CAShapeLayer()
    private let torso: Region
    private let head: Region
    private let tail: Region
    private let collar: Region
    private let legs: [Region]

    // Body
    private let chest: Part, belly: Part, rump: Part, bib: Part
    // Head
    private let skull: Part, muzzle: Part, nose: Part, blaze: Part, mouth: Part, tongue: Part
    private let ball: Part, ballSeams: Part
    private let ears: [(outer: Part, inside: Part)]
    private let eyes: [(open: Part, shine: Part, happy: Part)]
    // Tail, collar
    private let tailFur: Part, tailTip: Part
    private let band: Part, tag: Part, tagFace: Part, tagLight: Part
    // Legs, front left/right then hind left/right
    private let limbs: [(leg: Part, paw: Part)]

    init() {
        shadow.fillColor = NSColor.black.cgColor
        layer.addSublayer(shadow)
        let host = layer
        func part(_ style: Part.Style) -> Part { Part(style, in: host) }

        chest = part(.shape(Palette.fur, edge: Palette.rim))
        belly = part(.shape(Palette.fur, edge: Palette.rim))
        rump = part(.shape(Palette.fur, edge: Palette.rim))
        bib = part(.shape(Palette.white, edge: nil))
        torso = Region([chest, belly, rump, bib])

        skull = part(.shape(Palette.fur, edge: Palette.rim))
        muzzle = part(.shape(Palette.white, edge: Palette.rim))
        nose = part(.shape(Palette.nose, edge: nil))
        blaze = part(.shape(Palette.white, edge: nil))
        mouth = part(.shape(Palette.mouthInside, edge: nil))
        tongue = part(.limb(width: 4.4, Palette.tongue, edge: Palette.tongueGroove))
        ball = part(.shape(TennisBall.felt, edge: TennisBall.edge))
        ballSeams = part(.curve(width: 1.1, TennisBall.seam))
        ears = (0..<2).map { _ in (part(.shape(Palette.fur, edge: Palette.rim)), part(.shape(Palette.innerEar, edge: nil))) }
        eyes = (0..<2).map { _ in
            (part(.marking(Palette.eye, stroke: Palette.eyeRim, width: 0.7)),
             part(.marking(NSColor.white.withAlphaComponent(0.9))),
             part(.curve(width: 1.5, Palette.closedEye)))
        }
        head = Region([skull, muzzle, nose, blaze, mouth, tongue, ball, ballSeams]
                      + ears.flatMap { [$0.outer, $0.inside] }
                      + eyes.flatMap { [$0.open, $0.shine, $0.happy] })

        tailFur = part(.limb(width: 9, Palette.fur, edge: Palette.rim))
        tailTip = part(.limb(width: 7.4, Palette.white, edge: Palette.whiteEdge))
        tail = Region([tailFur, tailTip])

        band = part(.limb(width: 3.2, Palette.collar, edge: Palette.collarRim))
        tag = part(.shape(Palette.collar, edge: Palette.collarRim))
        tagFace = part(.shape(Palette.tagFace, edge: nil))
        tagLight = part(.shape(Palette.accent, edge: nil))
        collar = Region([band, tag, tagFace, tagLight])

        limbs = (0..<4).map { index in
            let fore = index < 2
            return (part(fore ? .limb(width: 7.4, Palette.white, edge: Palette.whiteEdge)
                              : .limb(width: 8.2, Palette.fur, edge: Palette.rim)),
                    part(.shape(Palette.white, edge: Palette.whiteEdge)))
        }
        legs = limbs.map { Region([$0.leg, $0.paw]) }
    }

    // MARK: - Drawing

    func render(_ p: CharacterPose) {
        let tau = 2 * Double.pi
        let g = min(1, max(0, p.gallop))
        let bow = min(1, max(0, p.bow))
        let phase = p.stride - p.stride.rounded(.down)
        let (floor, body, headFrame, lift) = Self.frames(p, reachPitch: Self.reachPitch)
        layoutShadow(on: floor, airborne: lift)
        layoutBody(body)
        layoutHead(headFrame, p, gallop: g, phase: phase)
        _ = tau
        layoutCollar(body, led: p.led)
        layoutTail(body, wag: p.tail, gallop: g, bow: bow)
        layoutLegs(body: body, floor: floor, gallop: g, bow: bow, phase: phase, jump: max(0, p.lift))
        arrange()
    }

    /// Where she stands and how her body and head are turned, for a pose. Drawing and the
    /// fetch geometry both use this, so they always agree.
    private static func frames(_ p: CharacterPose, reachPitch: Double) -> (floor: Frame, body: Frame, head: Frame, lift: Double) {
        let tau = 2 * Double.pi
        let g = min(1, max(0, p.gallop))
        let bow = min(1, max(0, p.bow))
        let crouch = min(1, max(0, p.crouch))
        let reach = min(1, max(0, p.reach))
        let phase = p.stride - p.stride.rounded(.down)

        // Facing on the floor; x right, y away from the viewer.
        let heading = Vec(p.headingX, p.headingY, 0)
        let facing = heading.length > 1e-6 ? heading / heading.length : Vec(0, -1, 0)
        let floor = Frame(origin: .zero, forward: facing, left: Vec(-facing.y, facing.x, 0), up: Vec(0, 0, 1))

        // The body bounds once per stride — highest in the stretched-out moment of flight —
        // and rocks nose-up while the hind legs drive.
        let bounce = 0.5 - 0.5 * cos(tau * (phase - 0.1))
        let rock = 0.1 * g * sin(tau * (phase + 0.05))
        let lift = p.lift + 4.5 * g * bounce + 2.5 * bow - 4.5 * crouch
        let body = Frame(origin: Vec(0, 0, lift), forward: floor.forward, left: floor.left, up: floor.up)
            .pitched(rock - 0.36 * bow, about: Vec(-2, 0, 22))
            .rolled(p.bank, about: Vec(0, 0, 4))
        // Reaching for the floor tips the head down at the neck.
        let head = body
            .pitched(-0.6 * rock + 0.32 * bow - 0.06 * crouch + 0.05 * g * sin(tau * (phase + 0.35)) - reachPitch * reach,
                     about: Anatomy.neck)
            .rolled(-p.headTilt * 0.8, about: Anatomy.skull.center)
        return (floor, body, head, lift)
    }

    /// The pose at the moment her mouth closes on a ball on the floor.
    static var pickupPose: CharacterPose {
        var p = CharacterPose()
        p.headingX = 1
        p.headingY = 0
        p.reach = 1
        p.bow = 0.3
        p.crouch = 0.25
        return p
    }

    /// How far the head tips down at full reach: just enough that the ball in her mouth
    /// touches the floor in the pickup pose.
    private static let reachPitch: Double = {
        var low = 0.0
        var high = 1.6
        for _ in 0..<40 {
            let mid = (low + high) / 2
            let height = frames(pickupPose, reachPitch: mid).head.point(Anatomy.ballHold).z
            if height > Anatomy.ballRadius { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }()

    /// Fetch geometry in points for an art view this wide: how far ahead of her paws the ball
    /// in her mouth is when her head is down, and how high its bottom is when she lets go.
    static func fetchReach(artWidth: Double) -> (reach: Double, mouthHeight: Double) {
        let points = artWidth / 100 * Camera.scale
        let ballAtFloor = frames(pickupPose, reachPitch: reachPitch).head.point(Anatomy.ballHold)
        var letGo = pickupPose
        letGo.reach = 0.55
        let ballAtRelease = frames(letGo, reachPitch: reachPitch).head.point(Anatomy.ballHold)
        return (ballAtFloor.x * points, max(2, ballAtRelease.z - Anatomy.ballRadius) * points)
    }

    private func layoutShadow(on floor: Frame, airborne: Double) {
        let air = min(1, max(0, airborne) / 16)
        let center = floor.point(-1, 0, 0)
        shadow.path = Camera.ellipsoid(center: center, floor.forward * 27 * (1 - air * 0.3),
                                       floor.left * 14 * (1 - air * 0.3), floor.up * 0.01)
        shadow.opacity = Float(0.2 * (1 - air * 0.6))
    }

    private func layoutBody(_ body: Frame) {
        chest.show(Anatomy.chest, in: body)
        belly.show(Anatomy.belly, in: body)
        rump.show(Anatomy.rump, in: body)
        // The white chest sits just inside the chest, so it shows from the front and
        // sides and is hidden by depth from behind.
        bib.show(Anatomy.bib, in: body, nearer: 0.5)
        torso.depth = Camera.depth(body.point(-1, 0, 23))
    }

    private func layoutHead(_ frame: Frame, _ p: CharacterPose, gallop g: Double, phase: Double) {
        let tau = 2 * Double.pi
        skull.show(Anatomy.skull, in: frame)
        muzzle.show(Anatomy.muzzle, in: frame, nearer: 1)
        nose.show(Anatomy.nose, in: frame, nearer: 1.5)
        blaze.show(Anatomy.blaze, in: frame, nearer: 0.5)

        // Mouth open under the muzzle, tongue hanging out and flapping with her stride.
        let open = min(1, max(0, p.mouthOpen))
        let mouthAt = frame.point(Anatomy.mouth)
        let mouthNormal = frame.vector(Vec(0.55, 0, -0.84))
        if open > 0.04, Camera.facing(mouthNormal) > -0.25 {
            let across = frame.left * 3.6
            let down = normalized(cross(mouthNormal, frame.left)) * (0.6 + 3 * open)
            mouth.show(Camera.card(Self.unitCircle, at: mouthAt, x: across, y: down), depth: Camera.depth(mouthAt) - 0.4)
        }
        let tongueOut = min(1, max(0, p.tongue))
        if tongueOut > 0.05 {
            let swing = 0.35 * g + 0.22 * g * sin(tau * (phase + 0.15))
            let length = 2.5 + 5.5 * tongueOut
            let start = frame.point(Anatomy.mouth + Vec(-1.2, 0, 0.6))
            let end = start + frame.vector(Vec(-sin(swing), 0, -cos(swing))) * length
            tongue.show(Camera.line([start, end]), depth: Camera.depth((start + end) / 2) - 0.2)
        }

        // A tennis ball held in the front of her mouth.
        if p.carry > 0.5 {
            let center = frame.point(Anatomy.ballHold)
            let r = Anatomy.ballRadius
            ball.show(Camera.ellipsoid(center: center, frame.forward * r, frame.left * r, frame.up * r),
                      depth: Camera.depth(center) - 1.2)
            let screen = Camera.vector(Vec(r, 0, 0)).dx
            ballSeams.show(Camera.card(TennisBall.seams, at: Camera.point(center), x: CGVector(dx: screen, dy: 0),
                                       y: CGVector(dx: 0, dy: screen)), depth: Camera.depth(center) - 1.21)
        }

        // Ears: the sitting Coco's own outline, laid on a card standing up from the skull.
        // They swing back with speed and flap on each stride.
        let flap = 0.18 * g * sin(tau * (phase - 0.2))
        let back = 0.06 + 0.38 * min(1, max(0, p.earBack)) + flap
        let splay = 0.14 + (1 - min(1, max(0, p.earPerk))) * 0.45
        for (index, ear) in ears.enumerated() {
            let side: Double = index == 0 ? 1 : -1
            let out = frame.left * side
            // Start upright facing forward, splay outward, turn to face forward-outward,
            // then tip back.
            var up = frame.up * cos(splay) + out * sin(splay)
            var across = -(out * cos(splay) - frame.up * sin(splay))
            var front = frame.forward
            let turn = 0.42 * side
            up = rotate(up, about: frame.up, by: turn)
            across = rotate(across, about: frame.up, by: turn)
            front = rotate(front, about: frame.up, by: turn)
            up = rotate(up, about: across, by: back * side)
            front = rotate(front, about: across, by: back * side)

            let base = frame.point(Anatomy.earBase.x, Anatomy.earBase.y * side, Anatomy.earBase.z)
            let scale = 1.14
            let lengthwise = Camera.vector(up * -scale)
            let crosswise = Self.readableWidth(Camera.vector(across * scale), along: lengthwise,
                                               outward: Camera.vector(out), minimum: 0.45 * scale)
            let outline = Camera.card(CocoLayerView.earOutline, at: Camera.point(base), x: crosswise, y: lengthwise)
            let center = base + up * 11
            ear.outer.show(outline, depth: Camera.depth(center))
            let seen = Camera.facing(front)
            if seen > 0.02 {
                let inside = Camera.card(CocoLayerView.earInside, at: Camera.point(base + up * 1.2), x: crosswise, y: lengthwise)
                ear.inside.show(inside, depth: Camera.depth(center) - 0.01, opacity: Float(Self.smoothstep(0.02, 0.3, seen)))
            }
        }

        // Eyes are markings on the skull, foreshortened as she turns. Happy "^" eyes
        // while she runs, round ones otherwise.
        let happy = Self.smoothstep(0.3, 0.7, p.eyeSmile)
        let openness = Self.smoothstep(0.12, 0.45, p.eyeOpen)
        for (index, eye) in eyes.enumerated() {
            let side: Double = index == 0 ? 1 : -1
            let surface = Anatomy.skull.surface(toward: Vec(0.66, 0.5 * side, 0.2))
            let at = frame.point(surface.point)
            let normal = frame.vector(surface.normal)
            let seen = Camera.facing(normal)
            guard seen > 0.02 else { continue }
            let visible = Float(Self.smoothstep(0.02, 0.25, seen))
            var across = cross(frame.up, normal)
            across = across.length > 1e-6 ? normalized(across) : frame.left
            var upward = normalized(cross(normal, across))
            if dot(upward, frame.up) < 0 { upward = -upward }
            let depth = Camera.depth(at)
            let scale = p.eyeScale
            if happy < 0.99, openness > 0.02 {
                let tall = max(0.08, min(1, p.eyeOpen))
                let disc = Camera.card(Self.unitCircle, at: at, x: across * 3.3 * scale, y: upward * (-3.7 * scale * tall))
                eye.open.show(disc, depth: depth, opacity: visible * Float(openness * (1 - happy)))
                let glint = Camera.card(Self.unitCircle, at: at + across * 1.3 * scale + upward * 1.5 * scale,
                                        x: across * 1.1 * scale, y: upward * (-1.1 * scale * tall))
                eye.shine.show(glint, depth: depth - 0.01, opacity: visible * Float(openness * (1 - happy)))
            }
            if happy > 0.01 {
                let arc = Camera.card(CocoLayerView.happyEye, at: at, x: across * scale, y: upward * -scale)
                eye.happy.show(arc, depth: depth - 0.02, opacity: visible * Float(happy))
            }
        }
        head.depth = Camera.depth(frame.point(Anatomy.skull.center)) - 3
    }

    private func layoutCollar(_ body: Frame, led: Double) {
        let center = body.point(Anatomy.collarCenter)
        let axis = normalized(body.vector(Anatomy.collarAxis))
        let e1 = body.left
        let e2 = normalized(cross(axis, e1))
        let r = Anatomy.collarRadius
        // Only the half of the ring nearest the viewer shows; the neck hides the rest.
        let d1 = Camera.depth(center + e1) - Camera.depth(center)
        let d2 = Camera.depth(center + e2) - Camera.depth(center)
        let nearest = atan2(-d2, -d1)
        let points = (0...14).map { i -> Vec in
            let a = nearest - .pi / 2 + .pi * Double(i) / 14
            return center + (e1 * cos(a) + e2 * sin(a)) * r
        }
        band.show(Camera.line(points), depth: Camera.depth(center))

        // The round tag hangs at the front of the collar.
        let hang = center - e2 * (r + 1.2)
        let facing = normalized(body.vector(Vec(0.92, 0, -0.38)))
        if Camera.facing(facing) > 0 {
            var across = cross(body.up, facing)
            across = normalized(across)
            let upward = normalized(cross(facing, across))
            let depth = Camera.depth(hang) - 0.5
            tag.show(Camera.card(Self.unitCircle, at: hang, x: across * 4.2, y: upward * -4.2), depth: depth)
            tagFace.show(Camera.card(Self.unitCircle, at: hang, x: across * 3, y: upward * -3), depth: depth - 0.01)
            if led > 0.02 {
                tagLight.show(Camera.card(Self.unitCircle, at: hang, x: across * 1.4, y: upward * -1.4),
                              depth: depth - 0.02, opacity: Float(min(1, led)))
            }
        }
        collar.depth = Camera.depth(center) - 1.5
    }

    private func layoutTail(_ body: Frame, wag: Double, gallop g: Double, bow: Double) {
        // Up and back, streaming lower at speed, high in a play bow, wagging side to side.
        let lift = 0.95 - 0.4 * g + 0.3 * bow
        let swing = wag * 1.3
        func direction(_ elevation: Double) -> Vec {
            body.vector(Vec(-cos(elevation) * cos(swing), cos(elevation) * sin(swing), sin(elevation)))
        }
        let base = body.point(Anatomy.tailBase)
        let middle = base + direction(lift) * 10
        let end = middle + direction(lift + 0.45) * 5.5
        tailFur.show(Camera.line([base, middle]), depth: Camera.depth((base + middle) / 2))
        tailTip.show(Camera.line([middle, end]), depth: Camera.depth((middle + end) / 2) - 0.1)
        tail.depth = Camera.depth(middle) + 2
    }

    /// `jump` lifts the paws off the floor with her (a leap, not a gallop's bounce).
    private func layoutLegs(body: Frame, floor: Frame, gallop g: Double, bow: Double, phase: Double, jump: Double) {
        // A bounding gallop: the hind pair drives together, then the front pair reaches.
        let offsets = [0.5, 0.57, 0.0, 0.07]
        let stance = 0.42
        for (index, limb) in limbs.enumerated() {
            let fore = index < 2
            let side: Double = index % 2 == 0 ? 1 : -1
            let joint = fore ? Anatomy.shoulder : Anatomy.hip
            let top = body.point(joint.x, joint.y * side, joint.z)

            let q = (phase + offsets[index]).truncatingRemainder(dividingBy: 1)
            let reach = 11 * g
            var dx: Double
            var dz = 0.0
            if q < stance {
                dx = reach * (1 - 2 * q / stance)
            } else {
                let u = (q - stance) / (1 - stance)
                dx = -reach + 2 * reach * Self.smoothstep(0, 1, u)
                dz = 7 * g * sin(.pi * u) * (fore ? 1 : 0.85)
            }
            dx += fore ? 3.5 * g + 9 * bow : -3.5 * g - 1.5 * bow
            let paw = floor.point(joint.x + dx, (joint.y + 0.6) * side, Anatomy.pawRadius + dz + jump)

            limb.leg.show(Camera.line([top, paw]), depth: Camera.depth((top + paw) / 2))
            limb.paw.show(Camera.ellipsoid(center: paw, floor.forward * 4.5, floor.left * 3.6, floor.up * Anatomy.pawRadius),
                          depth: Camera.depth(paw) - 0.05)
            legs[index].depth = Camera.depth((top + paw) / 2)
        }
    }

    /// Far regions first; legs always just before the body, which covers their tops. The
    /// layers themselves are reordered (only when the order changes), so the painting order
    /// holds everywhere the layers are drawn, offscreen snapshots included.
    private func arrange() {
        var order = [torso, head, tail, collar].sorted { $0.depth > $1.depth }
        let torsoIndex = order.firstIndex { $0 === torso } ?? 0
        order.insert(contentsOf: legs.sorted { $0.depth > $1.depth }, at: torsoIndex)
        var painted: [CALayer] = [shadow]
        var unused: [CALayer] = []
        for region in order {
            let shown = region.parts.filter(\.isShown)
            painted += shown.compactMap(\.edge)
            painted += shown.sorted { $0.depth > $1.depth }.map(\.fill)
            for part in region.parts where !part.isShown {
                unused.append(part.fill)
                if let edge = part.edge { unused.append(edge) }
            }
            region.parts.forEach { $0.commit() }
        }
        let layers = painted + unused
        if layer.sublayers != layers { layer.sublayers = layers }
    }

    // MARK: - Helpers

    private static let unitCircle = CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: nil)

    /// A flat ear seen edge-on would vanish into a line. Real ears are cupped, so on screen
    /// the ear's width (across its length) is kept to at least `minimum`, leaning outward.
    private static func readableWidth(_ across: CGVector, along length: CGVector, outward: CGVector,
                                      minimum: Double) -> CGVector {
        let size = (length.dx * length.dx + length.dy * length.dy).squareRoot()
        guard size > 1e-6 else { return across }
        let perpendicular = CGVector(dx: -length.dy / size, dy: length.dx / size)
        let width = across.dx * perpendicular.dx + across.dy * perpendicular.dy
        guard abs(width) < minimum else { return across }
        // The outline's tip leans toward −x, so −x should point outward on screen.
        let outwardSide = outward.dx * perpendicular.dx + outward.dy * perpendicular.dy
        let sign: Double = width != 0 ? (width > 0 ? 1 : -1) : (outwardSide > 0 ? -1 : 1)
        let extra = sign * minimum - width
        return CGVector(dx: across.dx + perpendicular.dx * extra, dy: across.dy + perpendicular.dy * extra)
    }

    private static func smoothstep(_ lower: Double, _ upper: Double, _ x: Double) -> Double {
        let k = min(1, max(0, (x - lower) / (upper - lower)))
        return k * k * (3 - 2 * k)
    }
}

/// Coco's colors come from the design tokens (Figma collection “Brand”).
private typealias Palette = BrandPalette

// MARK: - Anatomy

/// Her proportions, in units of the 100-unit box. x forward, y to her left, z up, with
/// the origin on the ground under the middle of her body.
private enum Anatomy {
    static let chest = Ellipsoid(center: Vec(13, 0, 24), radii: Vec(14, 14.5, 14))
    static let belly = Ellipsoid(center: Vec(0, 0, 22.5), radii: Vec(21, 13.5, 12))
    static let rump = Ellipsoid(center: Vec(-14.5, 0, 24), radii: Vec(13.5, 14.5, 13.5))
    static let bib = Ellipsoid(center: Vec(19.5, 0, 22), radii: Vec(6.5, 9, 9.5))

    static let neck = Vec(20, 0, 32)
    static let skull = Ellipsoid(center: Vec(30, 0, 43), radii: Vec(16, 19.5, 17))
    static let muzzle = Ellipsoid(center: Vec(43, 0, 35.5), radii: Vec(10, 8, 7))
    static let nose = Ellipsoid(center: Vec(52.5, 0, 38.3), radii: Vec(2.6, 3.5, 2.7))
    // A thin marking on the front of the face, leaning back with the forehead.
    static let blaze = Ellipsoid(center: Vec(43.2, 0, 46.5), radii: Vec(2, 3.6, 8), pitch: 0.35)
    static let mouth = Vec(48.5, 0, 31.2)
    /// Where a carried ball sits: gripped in the front of the mouth.
    static let ballHold = Vec(52, 0, 28)
    /// The ball's radius in model units (matches `BallFlight.radius` in points at full size).
    static let ballRadius = 6.3
    static let earBase = Vec(25.5, 10.5, 55.5)

    static let collarCenter = Vec(21, 0, 32)
    static let collarAxis = Vec(0.62, 0, 0.78)
    static let collarRadius = 12.2

    static let tailBase = Vec(-25, 0, 32)
    static let shoulder = Vec(14, 8, 14)
    static let hip = Vec(-15, 8.5, 14)
    static let pawRadius = 2.6
}

private struct Ellipsoid {
    var center: Vec
    var radii: Vec
    /// Tilt nose-up about its own centre, for markings that follow a slope.
    var pitch = 0.0

    /// The point on the surface in a direction from the centre, and the outward normal there.
    func surface(toward direction: Vec) -> (point: Vec, normal: Vec) {
        let d = direction / radii
        let t = 1 / d.length
        let offset = direction * t
        return (center + offset, normalized(offset / (radii * radii)))
    }
}

// MARK: - Parts and regions

/// One drawn piece: a fill layer, and for outlined styles a wider edge layer behind it.
private final class Part {
    enum Style {
        /// A filled shape whose outline merges with the rest of its region.
        case shape(NSColor, edge: NSColor?)
        /// A capsule — a thick round-capped line — outlined like a shape.
        case limb(width: CGFloat, NSColor, edge: NSColor?)
        /// A marking with its own thin stroke (or none), never merged.
        case marking(NSColor, stroke: NSColor? = nil, width: CGFloat = 0)
        /// An open stroked curve.
        case curve(width: CGFloat, NSColor)
    }

    let fill = CAShapeLayer()
    let edge: CAShapeLayer?
    private(set) var isShown = false
    private(set) var depth = 0.0
    private var opacity: Float = 1
    private static let rim: CGFloat = 0.9

    init(_ style: Style, in host: CALayer) {
        for layer in [fill] {
            layer.lineCap = .round
            layer.lineJoin = .round
        }
        switch style {
        case let .shape(color, edgeColor):
            fill.fillColor = color.cgColor
            edge = edgeColor.map { Self.edgeLayer($0, width: Self.rim * 2) }
        case let .limb(width, color, edgeColor):
            fill.fillColor = nil
            fill.strokeColor = color.cgColor
            fill.lineWidth = width
            edge = edgeColor.map { Self.edgeLayer($0, width: width + Self.rim * 2) }
        case let .marking(color, stroke, width):
            fill.fillColor = color.cgColor
            fill.strokeColor = stroke?.cgColor
            fill.lineWidth = width
            edge = nil
        case let .curve(width, color):
            fill.fillColor = nil
            fill.strokeColor = color.cgColor
            fill.lineWidth = width
            edge = nil
        }
        if let edge { host.addSublayer(edge) }
        host.addSublayer(fill)
        fill.isHidden = true
        edge?.isHidden = true
    }

    private static func edgeLayer(_ color: NSColor, width: CGFloat) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.strokeColor = color.cgColor
        layer.lineWidth = width
        layer.lineCap = .round
        layer.lineJoin = .round
        return layer
    }

    func show(_ path: CGPath, depth: Double, opacity: Float = 1) {
        fill.path = path
        edge?.path = path
        self.depth = depth
        self.opacity = opacity
        isShown = true
    }

    func show(_ shape: Ellipsoid, in frame: Frame, nearer bias: Double = 0) {
        var forward = frame.forward
        var up = frame.up
        if shape.pitch != 0 {
            forward = frame.forward * cos(shape.pitch) + frame.up * sin(shape.pitch)
            up = frame.up * cos(shape.pitch) - frame.forward * sin(shape.pitch)
        }
        let center = frame.point(shape.center)
        let path = Camera.ellipsoid(center: center, forward * shape.radii.x, frame.left * shape.radii.y, up * shape.radii.z)
        show(path, depth: Camera.depth(center) - bias)
    }

    /// Applies this frame's visibility and opacity; parts not shown this frame hide.
    func commit() {
        fill.isHidden = !isShown
        edge?.isHidden = !isShown
        fill.opacity = opacity
        edge?.opacity = opacity
        isShown = false
        opacity = 1
    }
}

/// Parts that share one outline and are painted together.
private final class Region {
    let parts: [Part]
    var depth = 0.0

    init(_ parts: [Part]) { self.parts = parts }
}

// MARK: - Camera and frames

private typealias Vec = SIMD3<Double>

private extension SIMD3 where Scalar == Double {
    var length: Double { (x * x + y * y + z * z).squareRoot() }
}

private func normalized(_ v: Vec) -> Vec {
    let l = v.length
    return l > 1e-9 ? v / l : v
}

private func cross(_ a: Vec, _ b: Vec) -> Vec {
    Vec(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

private func dot(_ a: Vec, _ b: Vec) -> Double { (a * b).sum() }

/// Rotates `v` about a unit axis (Rodrigues).
private func rotate(_ v: Vec, about axis: Vec, by angle: Double) -> Vec {
    let k = normalized(axis)
    return v * cos(angle) + cross(k, v) * sin(angle) + k * dot(k, v) * (1 - cos(angle))
}

/// An orthonormal frame placed in the world.
private struct Frame {
    var origin: Vec
    var forward: Vec
    var left: Vec
    var up: Vec

    func point(_ x: Double, _ y: Double, _ z: Double) -> Vec { origin + forward * x + left * y + up * z }
    func point(_ p: Vec) -> Vec { point(p.x, p.y, p.z) }
    func vector(_ v: Vec) -> Vec { forward * v.x + left * v.y + up * v.z }

    /// Turned nose-up by `angle` about a pivot given in this frame.
    func pitched(_ angle: Double, about pivot: Vec) -> Frame {
        turned(about: pivot, forward: forward * cos(angle) + up * sin(angle), left: left,
               up: up * cos(angle) - forward * sin(angle))
    }

    /// Leaned to her left by `angle` about a pivot given in this frame.
    func rolled(_ angle: Double, about pivot: Vec) -> Frame {
        turned(about: pivot, forward: forward, left: left * cos(angle) - up * sin(angle),
               up: up * cos(angle) + left * sin(angle))
    }

    private func turned(about pivot: Vec, forward f: Vec, left l: Vec, up u: Vec) -> Frame {
        let anchor = point(pivot)
        var frame = Frame(origin: .zero, forward: f, left: l, up: u)
        frame.origin = anchor - frame.vector(pivot)
        return frame
    }
}

/// The fixed view: looking down at the desktop "floor" at `Dash.viewElevation`.
/// World x is right, y away from the viewer, z up.
private enum Camera {
    static let sinE = sin(Dash.viewElevation)
    static let cosE = cos(Dash.viewElevation)
    /// From the scene toward the viewer.
    static let toViewer = Vec(0, -cosE, sinE)

    /// The model is a touch larger than its units, so seen from the front she's about the
    /// size of the sitting drawing she swaps with.
    static let scale = 1.12

    static func point(_ p: Vec) -> CGPoint {
        CGPoint(x: 50 + p.x * scale, y: 93 - (p.y * sinE + p.z * cosE) * scale)
    }

    static func vector(_ v: Vec) -> CGVector {
        CGVector(dx: v.x * scale, dy: -(v.y * sinE + v.z * cosE) * scale)
    }

    /// Larger is farther from the viewer.
    static func depth(_ p: Vec) -> Double { p.y * cosE - p.z * sinE }

    /// Above zero when a surface with this normal faces the viewer.
    static func facing(_ normal: Vec) -> Double { dot(normal, toViewer) }

    /// The outline of an ellipsoid with these semi-axes, as the image of a unit circle.
    static func ellipsoid(center: Vec, _ a: Vec, _ b: Vec, _ c: Vec) -> CGPath {
        let m = [vector(a), vector(b), vector(c)]
        let q11 = m.reduce(0) { $0 + $1.dx * $1.dx }
        let q12 = m.reduce(0) { $0 + $1.dx * $1.dy }
        let q22 = m.reduce(0) { $0 + $1.dy * $1.dy }
        let l11 = max(1e-6, q11.squareRoot())
        let l21 = q12 / l11
        let l22 = max(1e-6, (q22 - l21 * l21)).squareRoot()
        let o = point(center)
        var transform = CGAffineTransform(a: l11, b: l21, c: 0, d: l22, tx: o.x, ty: o.y)
        return CGPath(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2), transform: &transform)
    }

    /// A flat 2D drawing laid on a plane in the world: its x along `x`, its y along `y`.
    static func card(_ path: CGPath, at origin: Vec, x: Vec, y: Vec) -> CGPath {
        card(path, at: point(origin), x: vector(x), y: vector(y))
    }

    /// The same, with the plane's axes already on screen.
    static func card(_ path: CGPath, at origin: CGPoint, x: CGVector, y: CGVector) -> CGPath {
        var transform = CGAffineTransform(a: x.dx, b: x.dy, c: y.dx, d: y.dy, tx: origin.x, ty: origin.y)
        return path.copy(using: &transform) ?? path
    }

    static func line(_ points: [Vec]) -> CGPath {
        let path = CGMutablePath()
        path.addLines(between: points.map(point))
        return path
    }
}
