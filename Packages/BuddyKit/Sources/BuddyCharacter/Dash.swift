import Foundation

/// A dash across the desktop when Coco is called: where her paws are at any moment,
/// how fast she's going and which way she's headed.
///
/// Like `CharacterAnimator`, it's a pure function of time. The window controller samples
/// `position(at:)` for every frame and the animator samples speed, direction and stride
/// for the pose, so the two always agree. Points are screen coordinates with y up; the
/// position is where her paws touch the ground.
public struct Dash: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Winding up on the spot before the launch, 0…1.
        case ready(Double)
        /// On her way, 0…1 of the running time.
        case running(Double)
        /// Arrived; sitting back down, 0…1.
        case settling(Double)
        case finished
    }

    /// Points per second at full tilt.
    public static let topSpeed: Double = 1400
    /// Leg cycles per second at full tilt — short corgi legs go fast.
    public static let topCadence: Double = 5.5
    /// The wind-up before she launches.
    public static let windUp: TimeInterval = 0.5
    /// From arriving to sitting back down.
    public static let settle: TimeInterval = 0.5

    public let start: SIMD2<Double>
    public let end: SIMD2<Double>
    public let startTime: TimeInterval
    public let readyDuration: TimeInterval
    public let settleDuration: TimeInterval
    private let course: Course
    private let profile: SpeedProfile
    /// Strides completed before this dash began (carried over when she changes course).
    private let strideOffset: Double
    /// Strides completed, sampled every `strideStep` seconds of running.
    private let strideTable: [Double]
    private static let strideStep: TimeInterval = 1.0 / 120

    /// From a standstill: wind up, run, settle.
    public init(from start: SIMD2<Double>, to end: SIMD2<Double>, at time: TimeInterval) {
        self.init(from: start, to: end, at: time, readyDuration: Self.windUp, speed: 0, heading: nil, strideOffset: 0)
    }

    /// From a standstill, with its own wind-up and settle lengths. With `earliestArrival` she
    /// paces herself — a lower top speed, same easing — so as not to get there before then.
    public init(from start: SIMD2<Double>, to end: SIMD2<Double>, at time: TimeInterval,
                readyDuration: TimeInterval, settleDuration: TimeInterval, earliestArrival: TimeInterval? = nil,
                strideOffset: Double = 0) {
        self.init(from: start, to: end, at: time, readyDuration: readyDuration, speed: 0, heading: nil,
                  strideOffset: strideOffset, settleDuration: settleDuration, earliestArrival: earliestArrival)
    }

    private init(from start: SIMD2<Double>, to end: SIMD2<Double>, at time: TimeInterval,
                 readyDuration: TimeInterval, speed: Double, heading: SIMD2<Double>?, strideOffset: Double,
                 settleDuration: TimeInterval = Dash.settle, earliestArrival: TimeInterval? = nil) {
        self.start = start
        self.end = end
        startTime = time
        self.readyDuration = readyDuration
        self.settleDuration = settleDuration
        course = Course(from: start, to: end, leaving: heading, speed: speed)
        var profile = SpeedProfile(distance: course.length, startSpeed: speed)
        if let earliestArrival, time + readyDuration + profile.duration < earliestArrival {
            let wanted = earliestArrival - time - readyDuration
            var fast = Self.topSpeed
            var slow = 60.0
            // Duration only grows as the speed limit drops: find the limit that fits.
            for _ in 0..<30 {
                let limit = (fast + slow) / 2
                if SpeedProfile(distance: course.length, startSpeed: speed, speedLimit: limit).duration < wanted {
                    fast = limit
                } else {
                    slow = limit
                }
            }
            profile = SpeedProfile(distance: course.length, startSpeed: speed, speedLimit: slow)
        }
        self.profile = profile
        self.strideOffset = strideOffset
        strideTable = Self.strideTable(for: profile)
    }

    // MARK: - Timeline

    public var launchTime: TimeInterval { startTime + readyDuration }
    public var arrivalTime: TimeInterval { launchTime + profile.duration }
    public var endTime: TimeInterval { arrivalTime + settleDuration }
    /// Length of the course in points.
    public var length: Double { course.length }

    public func phase(at t: TimeInterval) -> Phase {
        if t < launchTime { return .ready(readyDuration > 0 ? max(0, (t - startTime) / readyDuration) : 1) }
        if t < arrivalTime { return .running((t - launchTime) / profile.duration) }
        if t < endTime { return .settling((t - arrivalTime) / settleDuration) }
        return .finished
    }

    // MARK: - Motion

    public func position(at t: TimeInterval) -> SIMD2<Double> {
        course.point(atDistance: profile.distance(at: t - launchTime))
    }

    /// Points per second along the course.
    public func speed(at t: TimeInterval) -> Double {
        profile.speed(at: t - launchTime)
    }

    /// Unit vector of where she's headed (screen space, y up). Before the launch it points
    /// at the course; after arriving it keeps the direction she arrived in.
    public func direction(at t: TimeInterval) -> SIMD2<Double> {
        course.tangent(atDistance: profile.distance(at: t - launchTime))
    }

    public func velocity(at t: TimeInterval) -> SIMD2<Double> {
        direction(at: t) * speed(at: t)
    }

    /// 0 standing … 1 full tilt.
    public func effort(at t: TimeInterval) -> Double {
        min(1, speed(at: t) / Self.topSpeed)
    }

    // MARK: - Facing

    /// The desktop is drawn as a floor seen from above at this angle, so running up the
    /// screen means running away from the viewer. Artwork projects her with the same angle.
    public static let viewElevation = 24.0 * Double.pi / 180
    /// She faces one of this many directions around the compass.
    public static let facings = 32
    /// Steps between facings blend over this long, so a curving run turns smoothly.
    static let facingBlend: TimeInterval = 0.1

    /// Which way she faces on the floor: a unit vector, x right, y away from the viewer.
    /// It's her course direction snapped to the nearest of the 32 facings, averaged over
    /// the last tenth of a second so each step glides into the next.
    public func facing(at t: TimeInterval) -> SIMD2<Double> {
        let samples = 6
        var sum = SIMD2<Double>.zero
        for k in 0..<samples {
            sum += Self.facing(forScreenDirection: direction(at: t - Self.facingBlend * Double(k) / Double(samples - 1)))
        }
        return sum.normalized ?? Self.facing(forScreenDirection: direction(at: t))
    }

    /// The facing for a direction of travel on screen (y up), snapped to the 32 facings.
    /// Up the screen is foreshortened by the view, so it maps to a steeper angle on the floor.
    public static func facing(forScreenDirection screen: SIMD2<Double>) -> SIMD2<Double> {
        let angle = atan2(screen.y / sin(viewElevation), screen.x)
        let step = 2 * Double.pi / Double(facings)
        let snapped = (angle / step).rounded() * step
        return SIMD2(cos(snapped), sin(snapped))
    }

    /// Leg cycles so far; the fractional part is where she is in her stride. Cadence
    /// follows her speed, so her paws never look like they're sliding.
    public func strides(at t: TimeInterval) -> Double {
        let x = (t - launchTime) / Self.strideStep
        guard x > 0 else { return strideOffset }
        let i = Int(x)
        guard i + 1 < strideTable.count else { return strideOffset + (strideTable.last ?? 0) }
        let f = x - Double(i)
        return strideOffset + strideTable[i] + (strideTable[i + 1] - strideTable[i]) * f
    }

    /// Changes course: from where she is now, at her current speed and heading,
    /// curving round to `newEnd`.
    public func redirected(to newEnd: SIMD2<Double>, at t: TimeInterval) -> Dash {
        switch phase(at: t) {
        case .ready:
            // Hasn't left yet: same spot and wind-up, new direction.
            return Dash(from: start, to: newEnd, at: startTime, readyDuration: readyDuration,
                        speed: 0, heading: nil, strideOffset: 0)
        case .running:
            return Dash(from: position(at: t), to: newEnd, at: t, readyDuration: 0,
                        speed: speed(at: t), heading: direction(at: t), strideOffset: strides(at: t))
        case .settling(let k) where k < CharacterAnimator.handback:
            // Still on her feet: straight off again, no second wind-up.
            return Dash(from: end, to: newEnd, at: t, readyDuration: 0, speed: 0, heading: nil, strideOffset: strides(at: t))
        case .settling, .finished:
            return Dash(from: end, to: newEnd, at: t)
        }
    }

    static func cadence(atSpeed speed: Double) -> Double {
        topCadence * min(1, max(0, speed) / topSpeed).squareRoot()
    }

    private static func strideTable(for profile: SpeedProfile) -> [Double] {
        let steps = Int((profile.duration / strideStep).rounded(.up))
        var table = [0.0]
        table.reserveCapacity(steps + 1)
        var total = 0.0
        for i in 0..<steps {
            let v = profile.speed(at: (Double(i) + 0.5) * strideStep)
            total += cadence(atSpeed: v) * strideStep
            table.append(total)
        }
        return table
    }
}

// MARK: - Course

/// The line she runs along. From a standstill it's straight; when she changes course
/// mid-run it leaves along her current heading and bends round to the new spot.
struct Course: Sendable, Equatable {
    let p0: SIMD2<Double>
    let p1: SIMD2<Double>
    let p2: SIMD2<Double>
    let p3: SIMD2<Double>
    /// Direction when the course has no length.
    let fallback: SIMD2<Double>
    /// Arc length at `samples + 1` evenly spaced curve parameters.
    let lengths: [Double]
    static let samples = 64

    init(from a: SIMD2<Double>, to b: SIMD2<Double>, leaving heading: SIMD2<Double>?, speed: Double) {
        let chord = b - a
        let d = chord.length
        let straight = d > 1e-6 ? chord / d : nil
        // Facing the viewer (down the screen) when there's nowhere to go.
        fallback = heading ?? straight ?? SIMD2(0, -1)
        p0 = a
        p3 = b
        if let heading, d > 1 {
            // The faster she's going, the wider she swings round.
            let reach = min(d * 0.5, 30 + speed * 0.15)
            p1 = a + heading * reach
            let arrival = (b - p1).normalized ?? fallback
            p2 = b - arrival * (d * 0.3)
        } else {
            p1 = a + chord / 3
            p2 = a + chord * 2 / 3
        }
        var lengths = [0.0]
        lengths.reserveCapacity(Self.samples + 1)
        var previous = a
        var total = 0.0
        for i in 1...Self.samples {
            let point = Self.bezier(a, p1, p2, b, Double(i) / Double(Self.samples))
            total += (point - previous).length
            lengths.append(total)
            previous = point
        }
        self.lengths = lengths
    }

    var length: Double { lengths[lengths.count - 1] }

    func point(atDistance s: Double) -> SIMD2<Double> {
        Self.bezier(p0, p1, p2, p3, parameter(atDistance: s))
    }

    func tangent(atDistance s: Double) -> SIMD2<Double> {
        let u = parameter(atDistance: s)
        let v = 1 - u
        let derivative = 3 * v * v * (p1 - p0) + 6 * v * u * (p2 - p1) + 3 * u * u * (p3 - p2)
        return derivative.normalized ?? fallback
    }

    private func parameter(atDistance s: Double) -> Double {
        guard length > 0 else { return 0 }
        let s = min(max(s, 0), length)
        var lo = 0
        var hi = Self.samples
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if lengths[mid] < s { lo = mid } else { hi = mid }
        }
        let span = lengths[hi] - lengths[lo]
        let f = span > 0 ? (s - lengths[lo]) / span : 0
        return (Double(lo) + f) / Double(Self.samples)
    }

    private static func bezier(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>, _ d: SIMD2<Double>,
                               _ u: Double) -> SIMD2<Double> {
        let v = 1 - u
        return v * v * v * a + 3 * v * v * u * b + 3 * v * u * u * c + u * u * u * d
    }
}

// MARK: - Speed

/// Speed over time along the course: eases up from the starting speed, cruises, then
/// eases to a stop. Each ramp is a smoothstep, so acceleration itself starts and ends
/// at zero — no jolts at the joins.
struct SpeedProfile: Sendable, Equatable {
    let startSpeed: Double
    let peak: Double
    let rampUp: Double
    let cruise: Double
    let rampDown: Double

    var duration: Double { rampUp + cruise + rampDown }

    init(distance: Double, startSpeed v0: Double, speedLimit: Double = Dash.topSpeed) {
        startSpeed = v0
        guard distance > 0.5 else {
            peak = 0; rampUp = 0; cruise = 0; rampDown = 0
            return
        }
        // Short hops ease in and out quicker than long sprints.
        let k = min(1, distance / 400)
        let up = (0.16 + 0.19 * k) * (v0 > 0 ? 0.6 : 1)
        let down = 0.22 + 0.23 * k
        let unlimited = (2 * distance - up * v0) / (up + down)
        if unlimited < 0 {
            // Too close to ease anything in: brake all the way from her current speed.
            peak = v0; rampUp = 0; cruise = 0; rampDown = 2 * distance / v0
        } else if unlimited > speedLimit, speedLimit >= v0 {
            peak = speedLimit; rampUp = up; rampDown = down
            cruise = (distance - up * (v0 + peak) / 2 - down * peak / 2) / peak
        } else {
            peak = unlimited; rampUp = up; cruise = 0; rampDown = down
        }
    }

    func speed(at t: Double) -> Double {
        if t <= 0 { return startSpeed }
        if t >= duration { return 0 }
        if t < rampUp { return startSpeed + (peak - startSpeed) * Self.smoothstep(t / rampUp) }
        if t < rampUp + cruise { return peak }
        return peak * (1 - Self.smoothstep((t - rampUp - cruise) / rampDown))
    }

    func distance(at t: Double) -> Double {
        let t = min(max(t, 0), duration)
        if t < rampUp {
            let x = t / rampUp
            return rampUp * (startSpeed * x + (peak - startSpeed) * Self.smoothstepIntegral(x))
        }
        let afterRampUp = rampUp * (startSpeed + peak) / 2
        if t < rampUp + cruise { return afterRampUp + peak * (t - rampUp) }
        guard rampDown > 0 else { return afterRampUp + peak * cruise }
        let y = (t - rampUp - cruise) / rampDown
        return afterRampUp + peak * cruise + rampDown * peak * (y - Self.smoothstepIntegral(y))
    }

    private static func smoothstep(_ x: Double) -> Double {
        let k = min(1, max(0, x))
        return k * k * (3 - 2 * k)
    }

    /// ∫₀ˣ smoothstep.
    private static func smoothstepIntegral(_ x: Double) -> Double {
        let k = min(1, max(0, x))
        return k * k * k - k * k * k * k / 2
    }
}

extension SIMD2 where Scalar == Double {
    var length: Double { (x * x + y * y).squareRoot() }
    var normalized: SIMD2<Double>? {
        let l = length
        return l > 1e-9 ? self / l : nil
    }
}
