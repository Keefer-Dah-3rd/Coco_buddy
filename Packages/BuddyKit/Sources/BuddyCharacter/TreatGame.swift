import Foundation

/// A treat, start to finish: after begging, Coco follows the toss, chases while it's still
/// in the air (paced to reach it as it settles), eats it where it lands, and celebrates
/// with a happy jump on the spot.
///
/// The same pieces as fetch — a `Dash` and a `BallFlight` (with treat physics) — and, like
/// it, a pure function of time, so her movement and the treat always agree. Unlike the
/// ball, the treat is eaten, not carried: it's gone at the bite, and she stays put.
public struct TreatGame: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Eyes following the toss, 0…1.
        case notice(Double)
        /// After it (the chase dash's own phase).
        case chase(Dash.Phase)
        /// Last step, head down, bite, chew, lick, 0…1.
        case eat(Double)
        /// Crouch, jump, land, wag, sit, 0…1.
        case celebrate(Double)
        case finished
    }

    public static let noticeDuration: TimeInterval = 0.22
    public static let chaseWindUp: TimeInterval = 0.15
    public static let eatDuration: TimeInterval = 1.35
    /// When in the eating the treat is bitten (and gone).
    public static let bite = 0.3
    /// When the chewing gives way to licking her lips.
    public static let chewEnd = 0.8
    public static let celebrateDuration: TimeInterval = 1.35
    /// When in the celebration she leaves the floor, peaks, and lands.
    public static let takeoff = 0.3
    public static let landing = 0.6
    /// When she sits back down (the running drawing hands back).
    public static let handback = 0.84
    /// How high the jump goes, in model units of the running Coco.
    public static let jumpHeight = 24.0

    public let startTime: TimeInterval
    public let home: SIMD2<Double>
    public let treat: BallFlight
    public let chase: Dash
    /// Where she stands to eat it: her mouth over it.
    public let eatSpot: SIMD2<Double>
    public let eatFacing: SIMD2<Double>

    /// - Parameter reach: how far ahead of her paws her lowered mouth is, in points.
    public init(home: SIMD2<Double>, treat: BallFlight, at time: TimeInterval, reach: Double) {
        self.home = home
        self.treat = treat
        startTime = time
        (eatSpot, eatFacing) = Fetch.approach(treat.rest, from: home, reach: reach)
        chase = Dash(from: home, to: eatSpot, at: time + Self.noticeDuration, readyDuration: Self.chaseWindUp,
                     settleDuration: 0, earliestArrival: treat.restTime + 0.05)
    }

    public var eatStart: TimeInterval { chase.arrivalTime }
    public var biteTime: TimeInterval { eatStart + Self.eatDuration * Self.bite }
    public var celebrateStart: TimeInterval { eatStart + Self.eatDuration }
    public var endTime: TimeInterval { celebrateStart + Self.celebrateDuration }

    public func phase(at t: TimeInterval) -> Phase {
        if t < chase.startTime { return .notice(max(0, (t - startTime) / Self.noticeDuration)) }
        if t < chase.arrivalTime { return .chase(chase.phase(at: t)) }
        if t < celebrateStart { return .eat((t - eatStart) / Self.eatDuration) }
        if t < endTime { return .celebrate((t - celebrateStart) / Self.celebrateDuration) }
        return .finished
    }

    /// Where her paws are. The jump goes straight up and comes straight down — she
    /// never drifts while celebrating.
    public func position(at t: TimeInterval) -> SIMD2<Double> {
        switch phase(at: t) {
        case .notice: home
        case .chase: chase.position(at: t)
        case .eat, .celebrate, .finished: eatSpot
        }
    }

    /// The treat's floor position, height and turn, until it's eaten.
    public func looseTreat(at t: TimeInterval) -> (ground: SIMD2<Double>, height: Double, spin: Double)? {
        guard t < biteTime else { return nil }
        return (treat.ground(at: t), treat.height(at: t), treat.spin(at: t))
    }

    public func chaseFacing(at t: TimeInterval) -> SIMD2<Double> {
        chase.length > 20 ? chase.facing(at: t) : eatFacing
    }

    /// Height of the celebration jump at a point in the celebration, 0…1 of the jump height.
    public static func jump(_ k: Double) -> Double {
        guard k > takeoff, k < landing else { return 0 }
        let u = (k - takeoff) / (landing - takeoff)
        return 4 * u * (1 - u)
    }
}
