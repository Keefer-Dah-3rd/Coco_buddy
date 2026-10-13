import Foundation

/// A tennis ball's whole journey once thrown: an arc under gravity, a few bounces that each
/// keep less of their height and lose speed to friction, then a roll to a stop.
///
/// Like `Dash`, a pure function of time, in screen points with y up. The ball is tracked as
/// a point on the desktop "floor" (`ground`) plus a height above it (`height`), so its
/// shadow, and the spot Coco runs to, stay on the floor while the ball itself flies.
public struct BallFlight: Sendable, Equatable {
    /// Points per second squared — tuned for a lively, readable arc at desktop scale.
    public static let gravity = 1900.0
    /// Drawn radius in points (at Coco's full size).
    public static let radius = 7.0

    struct Segment: Sendable, Equatable {
        var start: TimeInterval
        var duration: TimeInterval
        var ground: SIMD2<Double>
        /// Ground velocity at the start; constant in the air, slowing on a roll.
        var velocity: SIMD2<Double>
        /// Upward speed at the start; nil for a roll.
        var lift: Double?
        var height: Double
        /// Roll deceleration, points per second squared.
        var braking: Double
        var spin: Double
        var spinRate: Double
    }

    public let startTime: TimeInterval
    let segments: [Segment]
    /// Where it comes to rest.
    public let rest: SIMD2<Double>
    /// The first time it touches the ground.
    public let landTime: TimeInterval
    public let restTime: TimeInterval
    /// Where it first lands.
    public let landing: SIMD2<Double>

    /// How a thrown thing flies, bounces and comes to rest.
    public struct Material: Sendable, Equatable {
        /// Upward speed kept at the first bounce.
        public var bounciness: Double
        /// Speed kept along the floor at the first bounce, and at each one after.
        public var firstFriction: Double
        public var laterFriction: Double
        /// Slowing once it's down, points per second squared.
        public var braking: Double
        /// A ball rolls (turning with its travel); a biscuit skids and stops turning.
        public var rolls: Bool
        /// A fixed end-over-end turn in flight, radians per second; nil spins with its speed.
        public var tumble: Double?
        /// Time in the air: base plus a little per point thrown, within limits.
        public var airBase: TimeInterval
        public var airPerPoint: TimeInterval
        public var airRange: ClosedRange<TimeInterval>

        public static let tennisBall = Material(bounciness: 0.5, firstFriction: 0.5, laterFriction: 0.65, braking: 1100,
                                                rolls: true, tumble: nil, airBase: 0.42, airPerPoint: 1.0 / 1500, airRange: 0.45...1.15)
        /// Lighter and flatter: a lower, quicker arc, flipping end over end, one small flat
        /// bounce and a short skid.
        public static let treat = Material(bounciness: 0.28, firstFriction: 0.35, laterFriction: 0.45, braking: 2600,
                                           rolls: false, tumble: 14, airBase: 0.3, airPerPoint: 1.0 / 1900, airRange: 0.32...0.85)
    }

    /// Thrown from `start` (on the floor) at `height` above it, landing first at `landing`.
    /// Pass `flightTime` for a short drop; otherwise longer throws stay up longer.
    /// `bounciness` overrides how much upward speed survives the first bounce.
    public init(from start: SIMD2<Double>, height: Double, to landing: SIMD2<Double>, at time: TimeInterval,
                flightTime: TimeInterval? = nil, bounciness: Double? = nil, material: Material = .tennisBall) {
        let g = Self.gravity
        let r = Self.radius
        let throwLength = (landing - start).length
        let airTime = flightTime ?? min(material.airRange.upperBound,
                                        max(material.airRange.lowerBound, material.airBase + throwLength * material.airPerPoint))
        var velocity = (landing - start) / airTime
        let lift = (0.5 * g * airTime * airTime - height) / airTime
        let direction = velocity.length > 1e-6 ? (velocity.x >= 0 ? 1.0 : -1.0) : 1.0

        var segments: [Segment] = []
        var clock = 0.0
        var spin = 0.0
        // A ball goes with topspin, a little slower than it would roll; a biscuit tumbles.
        var spinRate = direction * (material.tumble ?? velocity.length / r * 0.6)
        var position = start
        segments.append(Segment(start: 0, duration: airTime, ground: start, velocity: velocity, lift: lift, height: height,
                                braking: 0, spin: 0, spinRate: spinRate))
        clock += airTime
        spin += spinRate * airTime
        position += velocity * airTime
        var impact = lift - g * airTime

        // Each bounce keeps less of its height, with a little irregularity so it doesn't
        // look mechanical, and friction takes speed off along the ground.
        var keep = bounciness ?? material.bounciness
        for bounce in 0..<6 {
            let up = -impact * keep
            let peak = up * up / (2 * g)
            if peak < 1.2 { break }
            velocity *= bounce == 0 ? material.firstFriction : material.laterFriction
            spinRate = material.rolls ? direction * velocity.length / r * 0.9 : spinRate * 0.35
            let airborne = 2 * up / g
            segments.append(Segment(start: clock, duration: airborne, ground: position, velocity: velocity, lift: up, height: 0,
                                    braking: 0, spin: spin, spinRate: spinRate))
            clock += airborne
            spin += spinRate * airborne
            position += velocity * airborne
            impact = -up
            keep *= bounce % 2 == 0 ? 0.83 : 0.9
        }

        // Then it rolls (or skids) to a stop.
        let sliding = velocity.length * 0.85
        let braking = material.braking
        let slideTime = sliding / braking
        let slideDirection = velocity.length > 1e-6 ? velocity / velocity.length : SIMD2(0, 0)
        if slideTime > 0.01 {
            segments.append(Segment(start: clock, duration: slideTime, ground: position, velocity: slideDirection * sliding, lift: nil,
                                    height: 0, braking: braking, spin: spin, spinRate: material.rolls ? direction * sliding / r : 0))
            position += slideDirection * (sliding * slideTime / 2)
            clock += slideTime
        }

        startTime = time
        self.segments = segments
        rest = position
        self.landing = landing
        landTime = time + airTime
        restTime = time + clock
    }

    /// Where it touches (or is above) the floor.
    public func ground(at t: TimeInterval) -> SIMD2<Double> {
        guard let (segment, dt) = locate(t) else { return t < startTime ? segments[0].ground : rest }
        if segment.lift != nil { return segment.ground + segment.velocity * dt }
        let speed = segment.velocity.length
        let travelled = speed * dt - 0.5 * segment.braking * dt * dt
        return segment.ground + (speed > 0 ? segment.velocity / speed : .zero) * travelled
    }

    /// Height above the floor, never below it.
    public func height(at t: TimeInterval) -> Double {
        guard let (segment, dt) = locate(t), let lift = segment.lift else {
            return t < startTime ? segments[0].height : 0
        }
        return max(0, segment.height + lift * dt - 0.5 * Self.gravity * dt * dt)
    }

    /// How far it has turned, in radians (positive is clockwise on screen).
    public func spin(at t: TimeInterval) -> Double {
        guard let (segment, dt) = locate(t) else {
            guard let last = segments.last, t >= startTime else { return 0 }
            return last.spin + rollSpin(last, last.duration)
        }
        return segment.spin + rollSpin(segment, dt)
    }

    public func isResting(at t: TimeInterval) -> Bool { t >= restTime }

    /// Times it hits the floor: the first landing and every bounce.
    public var impacts: [TimeInterval] {
        segments.filter { $0.lift != nil }.map { startTime + $0.start + $0.duration }
    }

    private func rollSpin(_ segment: Segment, _ dt: Double) -> Double {
        guard segment.lift == nil else { return segment.spinRate * dt }
        // Rolling slows, so the turning slows with it.
        let fraction = segment.duration > 0 ? dt / segment.duration : 1
        return segment.spinRate * dt * (1 - fraction / 2)
    }

    private func locate(_ t: TimeInterval) -> (Segment, TimeInterval)? {
        let local = t - startTime
        guard local >= 0 else { return nil }
        for segment in segments where local < segment.start + segment.duration {
            return (segment, local - segment.start)
        }
        return nil
    }
}
