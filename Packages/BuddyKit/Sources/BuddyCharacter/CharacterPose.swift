import Foundation

/// What the buddy is doing. Semantic, not visual — artwork decides how each looks.
public enum CharacterState: String, CaseIterable, Codable, Sendable {
    case idle, listening, talking, thinking, celebrating, focused, sleeping

    public var label: String { rawValue.capitalized }
}

/// Short, one-off physical responses layered on top of any state.
public enum CharacterReaction: Sendable, Equatable {
    /// Clicked: squash, eyes widen, ears boing.
    case poke
    /// Put down after being carried.
    case land
    /// Small acknowledging dip of the head.
    case nod
    /// Something interesting: ears up, little hop, tail wag.
    case perk

    var duration: TimeInterval {
        switch self {
        case .poke: 1.0
        case .land: 0.9
        case .nod: 0.5
        case .perk: 0.9
        }
    }
}

/// Every visual parameter an artwork needs, as plain numbers.
///
/// This is the contract between animation and art: the animator never draws,
/// the artwork never decides behaviour. Every field interpolates linearly, so
/// any two poses can be blended for smooth state transitions.
public struct CharacterPose: Equatable, Sendable {
    // Body
    /// Points the body is raised off the ground (hops).
    public var lift: Double = 0
    /// Positive squashes (wider, shorter); negative stretches.
    public var squash: Double = 0
    /// Whole-body rotation in radians around the feet.
    public var tilt: Double = 0

    // Head
    /// Head rotation in radians around the neck — the classic dog head tilt.
    public var headTilt: Double = 0
    /// Points the head drops (nods, dozing).
    public var headDip: Double = 0

    // Eyes
    /// 0 closed … 1 open.
    public var eyeOpen: Double = 1
    /// 0 normal … 1 happy "^ ^" eyes.
    public var eyeSmile: Double = 0
    /// Eye size multiplier — surprise.
    public var eyeScale: Double = 1
    /// Where the eyes look, each axis −1…1 (+y is down).
    public var gazeX: Double = 0
    public var gazeY: Double = 0

    // Mouth
    /// 0 closed … 1 wide open.
    public var mouthOpen: Double = 0
    /// −1 frown … 1 smile.
    public var mouthCurve: Double = 0.4
    /// 0 in … 1 hanging out (panting, happy).
    public var tongue: Double = 0

    // Ears and tail
    /// 0 relaxed (ears soften outward) … 1 fully perked.
    public var earPerk: Double = 0.8
    /// Extra rotation per ear in radians (twitches, flops). Positive turns outward.
    public var earLeft: Double = 0
    public var earRight: Double = 0
    /// Tail rotation in radians (wagging).
    public var tail: Double = 0

    // Extras
    /// Status light (collar tag), 0 off … 1 lit.
    public var led: Double = 0
    /// 0 standing … 1 hanging from the cursor.
    public var dangle: Double = 0
    /// Overlay strengths, 0…1.
    public var sleepZ: Double = 0
    public var thinking: Double = 0
    public var sparkles: Double = 0
    /// Seconds, for artwork that cycles its own overlay details.
    public var clock: Double = 0

    public init() {}

    public static func blend(_ a: Self, _ b: Self, _ t: Double) -> Self {
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        var p = Self()
        p.lift = mix(a.lift, b.lift)
        p.squash = mix(a.squash, b.squash)
        p.tilt = mix(a.tilt, b.tilt)
        p.headTilt = mix(a.headTilt, b.headTilt)
        p.headDip = mix(a.headDip, b.headDip)
        p.eyeOpen = mix(a.eyeOpen, b.eyeOpen)
        p.eyeSmile = mix(a.eyeSmile, b.eyeSmile)
        p.eyeScale = mix(a.eyeScale, b.eyeScale)
        p.gazeX = mix(a.gazeX, b.gazeX)
        p.gazeY = mix(a.gazeY, b.gazeY)
        p.mouthOpen = mix(a.mouthOpen, b.mouthOpen)
        p.mouthCurve = mix(a.mouthCurve, b.mouthCurve)
        p.tongue = mix(a.tongue, b.tongue)
        p.earPerk = mix(a.earPerk, b.earPerk)
        p.earLeft = mix(a.earLeft, b.earLeft)
        p.earRight = mix(a.earRight, b.earRight)
        p.tail = mix(a.tail, b.tail)
        p.led = mix(a.led, b.led)
        p.dangle = mix(a.dangle, b.dangle)
        p.sleepZ = mix(a.sleepZ, b.sleepZ)
        p.thinking = mix(a.thinking, b.thinking)
        p.sparkles = mix(a.sparkles, b.sparkles)
        p.clock = b.clock
        return p
    }
}
