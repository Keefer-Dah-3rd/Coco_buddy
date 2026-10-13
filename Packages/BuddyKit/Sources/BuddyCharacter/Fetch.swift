import Foundation

/// A game of fetch, start to finish: Coco notices the throw, chases while the ball is still
/// in the air (paced to reach it as it settles), picks it up, runs back to exactly where
/// she started, and drops it at her paws.
///
/// Built from the same pieces as being called — two `Dash`es and a `BallFlight` — and,
/// like them, a pure function of time. Coco's movement never follows the ball frame by
/// frame; both are planned up front from the ball's physics, so they agree.
public struct Fetch: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Spotting the throw, 0…1.
        case notice(Double)
        /// After the ball (the chase dash's own phase).
        case chase(Dash.Phase)
        /// Slowing the last step, head down, mouth on the ball, head up, 0…1.
        case pickup(Double)
        /// Turning round and running home with it.
        case homeward(Dash.Phase)
        /// Facing you, head down, letting go, sitting back down, 0…1.
        case drop(Double)
        case finished
    }

    public static let noticeDuration: TimeInterval = 0.32
    public static let chaseWindUp: TimeInterval = 0.2
    public static let pickupDuration: TimeInterval = 0.9
    /// When in the pickup her mouth closes on the ball.
    public static let contact = 0.5
    public static let turnAround: TimeInterval = 0.38
    public static let dropDuration: TimeInterval = 1.0
    /// When in the drop she lets go.
    public static let release = 0.42
    /// When in the drop she sits back down (the running drawing hands back).
    public static let handback = 0.64

    public let startTime: TimeInterval
    /// Where her paws were when the ball was thrown — always where she comes back to.
    public let home: SIMD2<Double>
    public let ball: BallFlight
    public let chase: Dash
    public let homeward: Dash
    /// Where she stands to pick the ball up: her mouth just over it.
    public let pickupSpot: SIMD2<Double>
    /// Which way she faces while picking it up (floor vector, x right, y away).
    public let pickupFacing: SIMD2<Double>
    /// The ball falling from her mouth at home.
    public let drop: BallFlight

    /// - Parameters:
    ///   - reach: how far ahead of her paws her lowered mouth is, in points.
    ///   - mouthHeight: how high above the floor her lowered mouth holds the ball.
    public init(home: SIMD2<Double>, ball: BallFlight, at time: TimeInterval, reach: Double, mouthHeight: Double) {
        self.home = home
        self.ball = ball
        startTime = time

        (pickupSpot, pickupFacing) = Self.approach(ball.rest, from: home, reach: reach)

        chase = Dash(from: home, to: pickupSpot, at: time + Self.noticeDuration, readyDuration: Self.chaseWindUp,
                     settleDuration: 0, earliestArrival: ball.restTime + 0.05)
        let pickupEnd = chase.arrivalTime + Self.pickupDuration
        homeward = Dash(from: pickupSpot, to: home, at: pickupEnd, readyDuration: Self.turnAround, settleDuration: 0)

        let mouth = home + Self.mouthOffset(facing: SIMD2(0, -1), reach: reach)
        let fall = (2 * mouthHeight / BallFlight.gravity).squareRoot()
        drop = BallFlight(from: mouth, height: mouthHeight, to: mouth + SIMD2(0, -4),
                          at: homeward.arrivalTime + Self.dropDuration * Self.release, flightTime: max(0.06, fall), bounciness: 0.5)
    }

    // MARK: - Timeline

    public var pickupStart: TimeInterval { chase.arrivalTime }
    public var contactTime: TimeInterval { pickupStart + Self.pickupDuration * Self.contact }
    public var dropStart: TimeInterval { homeward.arrivalTime }
    public var releaseTime: TimeInterval { dropStart + Self.dropDuration * Self.release }
    public var endTime: TimeInterval { dropStart + Self.dropDuration }

    public func phase(at t: TimeInterval) -> Phase {
        if t < chase.startTime { return .notice(max(0, (t - startTime) / Self.noticeDuration)) }
        if t < chase.arrivalTime { return .chase(chase.phase(at: t)) }
        if t < homeward.startTime { return .pickup((t - pickupStart) / Self.pickupDuration) }
        if t < homeward.arrivalTime { return .homeward(homeward.phase(at: t)) }
        if t < endTime { return .drop((t - dropStart) / Self.dropDuration) }
        return .finished
    }

    /// Where her paws are.
    public func position(at t: TimeInterval) -> SIMD2<Double> {
        switch phase(at: t) {
        case .notice: home
        case .chase: chase.position(at: t)
        case .pickup: pickupSpot
        case .homeward: homeward.position(at: t)
        case .drop, .finished: home
        }
    }

    /// The ball is in her mouth (drawn with her), not out in the world.
    public func isCarrying(at t: TimeInterval) -> Bool { t >= contactTime && t < releaseTime }

    /// The loose ball's floor position and height, or nil while she carries it.
    public func looseBall(at t: TimeInterval) -> (ground: SIMD2<Double>, height: Double, spin: Double)? {
        if isCarrying(at: t) { return nil }
        let flight = t < contactTime ? ball : drop
        return (flight.ground(at: t), flight.height(at: t), flight.spin(at: t))
    }

    /// Which way she faces while chasing: along her run, or at the ball if it's right there.
    public func chaseFacing(at t: TimeInterval) -> SIMD2<Double> {
        chase.length > 20 ? chase.facing(at: t) : pickupFacing
    }

    /// Which way she faces running home.
    public func homewardFacing(at t: TimeInterval) -> SIMD2<Double> {
        homeward.length > 20 ? homeward.facing(at: t) : SIMD2(0, -1)
    }

    /// Her mouth's offset on screen from her paws, for a facing on the floor.
    public static func mouthOffset(facing: SIMD2<Double>, reach: Double) -> SIMD2<Double> {
        SIMD2(facing.x * reach, facing.y * reach * sin(Dash.viewElevation))
    }

    /// Where to stand, and which way to face, so her mouth — not her paws — ends up over
    /// something on the floor. Her facing is snapped to the 32 facings, so the spot and the
    /// facing are settled together.
    public static func approach(_ target: SIMD2<Double>, from home: SIMD2<Double>, reach: Double)
        -> (spot: SIMD2<Double>, facing: SIMD2<Double>) {
        var facing = towards(target - home) ?? SIMD2(0, -1)
        var spot = target - mouthOffset(facing: facing, reach: reach)
        for _ in 0..<3 {
            guard let direction = towards(spot - home), (spot - home).length > 20 else { break }
            facing = direction
            spot = target - mouthOffset(facing: facing, reach: reach)
        }
        return (spot, facing)
    }

    private static func towards(_ screen: SIMD2<Double>) -> SIMD2<Double>? {
        screen.length > 1e-6 ? Dash.facing(forScreenDirection: screen) : nil
    }
}
