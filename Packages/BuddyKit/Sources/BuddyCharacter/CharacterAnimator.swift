import Foundation

/// Turns a state plus recent events into a `CharacterPose` for any moment in time.
///
/// `pose(at:)` is a pure function of time: blinks, glances, ear twitches, wags and
/// breathing are derived from the clock with deterministic noise rather than stored
/// timers. That makes the character testable, lets the renderer sample at any frame
/// rate, and lets `nextFrameTime(after:)` predict exactly when something will next
/// move — so the view can idle at a few frames per second and only run at 60 fps
/// during motion.
public struct CharacterAnimator: Sendable {
    public static let transitionDuration: TimeInterval = 0.3
    public static let fastFrameInterval: TimeInterval = 1.0 / 60
    /// Slow, rhythmic motion (wagging, panting, listening) looks the same at half the rate.
    public static let gentleFrameInterval: TimeInterval = 1.0 / 30

    public private(set) var state: CharacterState = .idle
    /// Body motion (hops, squash, sway) is suppressed; expressions remain.
    public var reduceMotion = false

    private var transitionFrom: CharacterPose?
    private var stateChangedAt: TimeInterval = -.greatestFiniteMagnitude

    private struct ActiveReaction: Sendable {
        var kind: CharacterReaction
        var start: TimeInterval
    }
    private var reactions: [ActiveReaction] = []

    // Cursor-following gaze, eased between successive targets.
    private var gazeFrom = SIMD2<Double>.zero
    private var gazeTo = SIMD2<Double>.zero
    private var gazeChangedAt: TimeInterval = -.greatestFiniteMagnitude
    private var hovering = false
    private var hoverChangedAt: TimeInterval = -.greatestFiniteMagnitude
    private static let gazeEase: TimeInterval = 0.18
    private static let hoverFade: TimeInterval = 0.25

    private var carried = false
    private var carriedChangedAt: TimeInterval = -.greatestFiniteMagnitude

    /// Running somewhere she was called to.
    public private(set) var dash: Dash?

    public init() {}

    // MARK: - Inputs

    public mutating func setState(_ newState: CharacterState, at t: TimeInterval) {
        guard newState != state else { return }
        transitionFrom = basePose(at: t)
        state = newState
        stateChangedAt = t
    }

    public mutating func react(_ reaction: CharacterReaction, at t: TimeInterval) {
        reactions.removeAll { t - $0.start > $0.kind.duration }
        reactions.append(ActiveReaction(kind: reaction, start: t))
    }

    /// Point the eyes at a normalised target (−1…1 per axis), or nil to stop following.
    public mutating func look(at target: SIMD2<Double>?, at t: TimeInterval) {
        gazeFrom = hoverGaze(at: t)
        if let target {
            gazeTo = target.clamped(lowerBound: SIMD2(-1, -1), upperBound: SIMD2(1, 1))
        }
        gazeChangedAt = t
        if (target != nil) != hovering {
            hovering = target != nil
            hoverChangedAt = t
        }
    }

    public mutating func setCarried(_ isCarried: Bool, at t: TimeInterval) {
        guard isCarried != carried else { return }
        carried = isCarried
        carriedChangedAt = t
    }

    /// Starts, redirects or (with nil) ends a dash.
    public mutating func setDash(_ newDash: Dash?) {
        dash = newDash
    }

    // MARK: - Output

    public func pose(at t: TimeInterval) -> CharacterPose {
        var p = basePose(at: t)

        let blink = Self.blinkAmount(at: t)
        p.eyeOpen *= 1 - blink * (1 - p.eyeSmile)

        if state == .idle {
            for event in Self.idleEvents(at: t) where !(event.kind == .glance && hovering) {
                Self.apply(event, at: t, to: &p)
            }
        }

        let base = SIMD2(p.gazeX, p.gazeY)
        let weight = hoverInfluence(at: t) * Self.hoverWeight(state)
        let gaze = base + (hoverGaze(at: t) - base) * weight
        p.gazeX = gaze.x
        p.gazeY = gaze.y

        let carry = carryAmount(at: t)
        if carry > 0 {
            p.dangle = carry
            p.eyeOpen += (1 - p.eyeOpen) * carry
            p.eyeScale += 0.14 * carry
            p.mouthOpen = max(p.mouthOpen, 0.35 * carry)
            p.mouthCurve *= 1 - carry
            p.tongue *= 1 - carry
            p.squash -= 0.05 * carry
            p.headDip *= 1 - carry
            p.earPerk += (0.35 - p.earPerk) * carry
            p.earLeft += carry * (0.2 + 0.12 * sin(t * 6.5))
            p.earRight += carry * (0.2 + 0.12 * sin(t * 6.5 + 1))
            p.tail += carry * 0.3 * sin(t * 5)
        }

        for reaction in reactions {
            let dt = t - reaction.start
            if dt >= 0, dt < reaction.kind.duration {
                Self.apply(reaction.kind, dt: dt, to: &p)
            }
        }

        if let dash, t < dash.endTime {
            Self.apply(dash, at: t, to: &p)
        }

        if reduceMotion {
            p.lift = 0
            p.squash = 0
            p.tilt = 0
            p.tail *= 0.3
            p.earLeft *= 0.3
            p.earRight *= 0.3
        }
        p.clock = t
        return p
    }

    /// The next moment worth rendering. Returns ~1/60 s ahead while anything is moving
    /// visibly, otherwise sleeps until the next scheduled blink or idle event, or a slow
    /// "breathing" tick, whichever comes first.
    public func nextFrameTime(after t: TimeInterval) -> TimeInterval {
        if let interval = motionFrameInterval(at: t) { return t + interval }
        let rest = t + (state == .sleeping ? 1.0 / 6 : 1.0 / 10)
        let upcoming = min(nextBlinkStart(after: t), nextIdleEventEdge(after: t))
        return max(t + Self.fastFrameInterval, min(rest, upcoming))
    }

    public func isMovingQuickly(at t: TimeInterval) -> Bool {
        motionFrameInterval(at: t) == Self.fastFrameInterval
    }

    /// How often to draw right now, or nil when nothing is moving.
    public func motionFrameInterval(at t: TimeInterval) -> TimeInterval? {
        let fast = Self.fastFrameInterval
        switch state {
        case .talking, .celebrating: return fast
        case .idle, .focused, .sleeping, .thinking, .listening: break
        }
        if t - stateChangedAt < Self.transitionDuration { return fast }
        if let dash, t < dash.endTime { return fast }
        if reactions.contains(where: { t >= $0.start && t - $0.start < $0.kind.duration }) { return fast }
        if carried || t - carriedChangedAt < 0.25 { return fast }
        if t - gazeChangedAt < Self.gazeEase || t - hoverChangedAt < Self.hoverFade { return fast }
        if Self.blinkAmount(at: t) > 0 { return fast }
        if state == .thinking || state == .listening { return Self.gentleFrameInterval }
        if state == .idle {
            let moving = Self.idleEvents(at: t).filter { $0.isMoving(at: t) && !($0.kind == .glance && hovering) }
            if moving.contains(where: { $0.kind == .earTwitch || $0.kind == .glance || $0.kind == .curiousTilt }) { return fast }
            if !moving.isEmpty { return Self.gentleFrameInterval }
        }
        return nil
    }

    // MARK: - Composition

    private func basePose(at t: TimeInterval) -> CharacterPose {
        let target = Self.statePose(state, at: t)
        guard let from = transitionFrom else { return target }
        let k = (t - stateChangedAt) / Self.transitionDuration
        guard k < 1 else { return target }
        return .blend(from, target, Self.ease(k))
    }

    private func hoverGaze(at t: TimeInterval) -> SIMD2<Double> {
        let k = Self.ease((t - gazeChangedAt) / Self.gazeEase)
        return gazeFrom + (gazeTo - gazeFrom) * k
    }

    private func hoverInfluence(at t: TimeInterval) -> Double {
        let k = Self.ease((t - hoverChangedAt) / Self.hoverFade)
        return hovering ? k : 1 - k
    }

    private func carryAmount(at t: TimeInterval) -> Double {
        let dt = t - carriedChangedAt
        return carried ? Self.ease(dt / 0.15) : 1 - Self.ease(dt / 0.2)
    }

    private static func hoverWeight(_ state: CharacterState) -> Double {
        switch state {
        case .idle: 1
        case .talking: 0.8
        case .listening: 0.5
        case .focused: 0.35
        case .celebrating: 0.3
        case .thinking: 0.15
        case .sleeping: 0
        }
    }
}

// MARK: - Per-state poses

extension CharacterAnimator {
    static func statePose(_ state: CharacterState, at t: TimeInterval) -> CharacterPose {
        var p = CharacterPose()
        switch state {
        case .idle:
            p.squash = 0.012 * sin(t * 2 * .pi / 4.2)
            p.tail = 0.07 * sin(t * 1.3)

        case .listening:
            // Ears up, head cocked — the "did you say walk?" pose. The collar tag
            // glows while the microphone is on.
            p.earPerk = 1
            p.headTilt = 0.16 + 0.02 * sin(t * 1.4)
            p.eyeScale = 1.08
            p.mouthCurve = 0.25
            p.tail = 0.22 * sin(t * 6)
            p.squash = 0.01 * sin(t * 2 * .pi / 3.5)
            p.led = 0.6 + 0.4 * sin(t * 3)

        case .talking:
            p.mouthOpen = max(0, sin(t * 13)) * (0.6 + 0.4 * sin(t * 3.7))
            p.mouthCurve = 0.5
            p.earPerk = 0.9
            p.lift = 0.8 * abs(sin(t * 6.5))
            p.headTilt = 0.04 * sin(t * 2.1)
            p.tail = 0.25 * sin(t * 9)

        case .thinking:
            p.headTilt = 0.22 + 0.03 * sin(t * 1.2)
            p.earPerk = 0.85
            p.earRight = 0.25
            p.gazeX = 0.5 + 0.1 * sin(t * 0.9)
            p.gazeY = -0.6
            p.mouthCurve = 0
            p.thinking = 1
            p.tail = 0.05 * sin(t * 1.5)

        case .celebrating:
            let hops = t * 2.3
            let h = abs(sin(.pi * hops))
            p.lift = 9 * h
            p.squash = 0.08 * pow(1 - h, 4) - 0.03 * h
            p.tilt = 0.05 * sin(.pi * hops)
            p.eyeSmile = 1
            p.mouthCurve = 1
            p.mouthOpen = 0.55
            p.tongue = 1
            p.earPerk = 0.7
            p.earLeft = 0.25 * (1 - h)
            p.earRight = 0.25 * (1 - h)
            p.tail = 0.55 * sin(t * 22)
            p.sparkles = 1
            p.led = 1

        case .focused:
            // On guard: perfectly still, ears up, eyes on the work.
            p.squash = 0.008 * sin(t * 2 * .pi / 5)
            p.earPerk = 1
            p.eyeOpen = 0.78
            p.gazeY = 0.3
            p.mouthCurve = 0.15
            p.led = 1

        case .sleeping:
            let breath = sin(t * 2 * .pi / 5.5)
            p.squash = 0.022 * breath
            p.eyeOpen = 0
            p.headDip = 4 + 0.6 * breath
            p.headTilt = -0.08
            p.earPerk = 0.1
            p.mouthCurve = 0.2
            p.sleepZ = 1
        }
        return p
    }

    static func apply(_ reaction: CharacterReaction, dt: Double, to p: inout CharacterPose) {
        switch reaction {
        case .poke:
            p.squash += 0.13 * exp(-dt * 6.5) * cos(dt * 24)
            p.eyeScale += 0.22 * exp(-dt * 5)
            p.earLeft += 0.3 * exp(-dt * 4) * sin(dt * 17)
            p.earRight += 0.3 * exp(-dt * 4) * sin(dt * 17 + 0.6)
            p.tail += 0.4 * exp(-dt * 3) * sin(dt * 20)
        case .land:
            p.squash += 0.11 * exp(-dt * 8) * cos(dt * 26)
            let flop = 0.3 * exp(-dt * 3.5) * sin(dt * 15)
            p.earLeft += flop
            p.earRight += flop
        case .nod:
            let bump = sin(min(1, dt / reaction.duration) * .pi)
            p.headDip += 3 * bump
            p.squash += 0.03 * bump
            p.eyeSmile = min(1, p.eyeSmile + 0.5 * bump)
        case .bark:
            // Matches the ~0.2 s sound: open fast, close a touch slower.
            let open = dt < 0.06 ? dt / 0.06 : max(0, 1 - (dt - 0.06) / 0.16)
            p.mouthOpen = max(p.mouthOpen, 0.95 * open)
            p.earPerk = min(1, p.earPerk + 0.3 * open)
            p.squash -= 0.04 * open
            p.lift += 2 * open
            p.eyeScale += 0.08 * open
            p.tail += 0.3 * exp(-dt * 4) * sin(dt * 20)
        case .perk:
            p.earPerk = min(1, p.earPerk + 0.3 * exp(-dt * 4))
            p.earLeft -= 0.12 * exp(-dt * 5)
            p.earRight -= 0.12 * exp(-dt * 5)
            p.eyeScale += 0.1 * exp(-dt * 6)
            p.lift += 2.5 * sin(min(1, dt / 0.3) * .pi)
            p.tail += 0.45 * exp(-dt * 2.5) * sin(dt * 18)
        }
    }

    /// Called somewhere. Each handover between the sitting and running drawings is a
    /// single-frame swap hidden inside a squash, so the two never show at once.
    static func apply(_ dash: Dash, at t: TimeInterval, to p: inout CharacterPose) {
        switch dash.phase(at: t) {
        case .ready(let k):
            if k < spotted {
                // Spots the place: eyes lock on, ears shoot up, a little "!" hop.
                let s = k / spotted
                let heading = dash.direction(at: t)
                p.earPerk = 1
                p.eyeScale += 0.2 * ease(s / 0.4)
                p.gazeX = heading.x
                p.gazeY = -heading.y
                p.lift += 3 * sin(s * .pi)
                p.squash += 0.06 * ease((s - 0.6) / 0.4)
                p.mouthOpen = max(p.mouthOpen, 0.25 * sin(s * .pi))
            } else {
                p = windUp(dash, (k - spotted) / (1 - spotted), at: t, from: p)
            }
        case .running:
            var r = runningPose(from: p, facing: dash.facing(at: t), strides: dash.strides(at: t),
                                effort: dash.effort(at: t), at: t)
            // Leans into turns: how fast her facing is swinging round, signed left-positive.
            let now = dash.facing(at: t)
            let before = dash.facing(at: t - 0.05)
            let swing = (before.x * now.y - before.y * now.x) / 0.05
            r.bank = min(0.3, max(-0.3, swing * 0.06))
            p = r
        case .settling(let k):
            if k < handback {
                // Brakes low and turns to face you, gathering for the sit.
                let s = k / handback
                let facing = turn(from: dash.facing(at: t), to: SIMD2(0, -1), by: ease(s / 0.85))
                var r = runningPose(from: p, facing: facing, strides: dash.strides(at: t), effort: 0, at: t)
                r.crouch = 0.4 * ease(s)
                r.earBack = 0.4 * (1 - s)
                p = r
            } else {
                // Plops down: the sitting drawing lands squashed and wobbles back up.
                let s = (k - handback) / (1 - handback)
                p.squash += 0.13 * exp(-s * 5) * cos(s * 13)
                p.tongue = max(p.tongue, 1)
                p.mouthOpen = max(p.mouthOpen, 0.45)
                p.eyeSmile = max(p.eyeSmile, 0.7 * (1 - s))
                p.tail += 0.5 * sin(t * 18)
            }
        case .finished:
            break
        }
    }

    /// Share of the wind-up spent spotting the place, in the sitting drawing.
    static let spotted = 0.2
    /// Share of the settle spent braking and turning, in the running drawing.
    static let handback = 0.45

    /// Getting ready, s from 0 to 1: she turns to the spot and drops into a play bow — front
    /// down, butt up and wiggling, tail going — gathers low, then lets go into the dash.
    static func windUp(_ dash: Dash, _ s: Double, at t: TimeInterval, from base: CharacterPose) -> CharacterPose {
        let target = dash.facing(at: t)
        let bow = ease(s / 0.25) * (1 - ease((s - 0.8) / 0.2))
        // A quick wiggle from side to side while she's down in the bow.
        let wiggle = 0.09 * sin(t * 34) * bow
        let toward = turn(from: SIMD2(0, -1), to: target, by: ease(s / 0.35))
        let facing = SIMD2(toward.x * cos(wiggle) - toward.y * sin(wiggle), toward.x * sin(wiggle) + toward.y * cos(wiggle))
        var p = runningPose(from: base, facing: facing, strides: 0, effort: 0, at: t)
        p.bow = bow
        // Lands from the swap squashed, then sinks lower just before the launch.
        p.crouch = 0.6 * exp(-s * 14) + 0.45 * ease((s - 0.45) / 0.35) * (1 - ease((s - 0.88) / 0.12))
        p.tail = 0.65 * sin(t * 28)
        p.earBack = 0
        p.eyeSmile = 0
        p.eyeScale = 1.12
        p.mouthOpen = 0.35
        p.tongue = 0.5
        return p
    }

    /// The running Coco mid-dash: bounding along in a direction with a happy, open-mouthed
    /// face, ears blown back and tail going. `effort` is 0 standing … 1 full tilt.
    public static func runningPose(from base: CharacterPose = CharacterPose(), facing: SIMD2<Double>,
                                   strides: Double, effort: Double, at t: TimeInterval) -> CharacterPose {
        var p = base
        p.run = 1
        p.headingX = facing.x
        p.headingY = facing.y
        p.stride = strides
        // Even a short trot bounds a little.
        p.gallop = min(1, 0.35 * min(1, effort / 0.03) + effort)
        p.earBack = min(1, 0.2 + effort)
        p.earPerk = 1
        p.eyeSmile = 0.85
        p.eyeOpen = 1
        p.mouthOpen = 0.55
        p.mouthCurve = 0.8
        p.tongue = 1
        p.tail = 0.45 * sin(t * 20)
        p.lift = 0
        p.squash = 0
        p.tilt = 0
        p.headTilt = 0
        p.headDip = 0
        return p
    }
}

// MARK: - Blinks

extension CharacterAnimator {
    static let blinkPeriod: TimeInterval = 4.4
    static let blinkLength: TimeInterval = 0.17
    static let doubleBlinkGap: TimeInterval = 0.26

    /// 0 = open, 1 = fully closed.
    public static func blinkAmount(at t: TimeInterval) -> Double {
        let cycle = (t / blinkPeriod).rounded(.down)
        let local = t - blinkStart(cycle: cycle)
        var amount = blinkCurve(local)
        if hasDoubleBlink(cycle: cycle) {
            amount = max(amount, blinkCurve(local - doubleBlinkGap))
        }
        return amount
    }

    static func blinkStart(cycle: Double) -> TimeInterval {
        cycle * blinkPeriod + 0.3 + hash(cycle * 1.91) * (blinkPeriod - 0.9)
    }

    static func hasDoubleBlink(cycle: Double) -> Bool {
        hash(cycle + 0.53) > 0.78
    }

    private static func blinkCurve(_ x: Double) -> Double {
        guard x >= 0, x <= blinkLength else { return 0 }
        if x < 0.06 { return x / 0.06 }
        if x < 0.08 { return 1 }
        return 1 - (x - 0.08) / (blinkLength - 0.08)
    }

    func nextBlinkStart(after t: TimeInterval) -> TimeInterval {
        let cycle = (t / Self.blinkPeriod).rounded(.down)
        var candidates: [TimeInterval] = []
        for c in [cycle, cycle + 1] {
            let start = Self.blinkStart(cycle: c)
            candidates.append(start)
            if Self.hasDoubleBlink(cycle: c) { candidates.append(start + Self.doubleBlinkGap) }
        }
        return candidates.filter { $0 > t }.min() ?? t + Self.blinkPeriod
    }
}

// MARK: - Idle life

extension CharacterAnimator {
    /// Small unprompted behaviours while idle, each on its own deterministic schedule.
    public struct IdleEvent: Sendable, Equatable {
        public enum Kind: CaseIterable, Sendable {
            case glance, earTwitch, wag, pant, curiousTilt
        }

        public var kind: Kind
        public var start: TimeInterval
        public var duration: TimeInterval
        /// 0..<1, picks direction/target so repeats aren't identical.
        public var seed: Double

        var end: TimeInterval { start + duration }

        /// Glances and tilts hold still in the middle; the rest move throughout.
        func isMoving(at t: TimeInterval) -> Bool {
            guard t >= start, t <= end else { return false }
            switch kind {
            case .glance, .curiousTilt:
                let ramp = CharacterAnimator.idleRamp
                return t <= start + ramp || t >= end - ramp
            case .earTwitch, .wag, .pant:
                return true
            }
        }

        func envelope(at t: TimeInterval) -> Double {
            let ramp = CharacterAnimator.idleRamp
            return min(CharacterAnimator.ease((t - start) / ramp), 1 - CharacterAnimator.ease((t - end + ramp) / ramp))
        }
    }

    static let idleRamp: TimeInterval = 0.18

    private static func schedule(_ kind: IdleEvent.Kind) -> (period: Double, chance: Double, duration: ClosedRange<Double>, salt: Double) {
        switch kind {
        case .glance: (7, 0.6, 1.2...2.4, 3.17)
        case .earTwitch: (8, 0.5, 0.45...0.45, 5.3)
        case .wag: (15, 0.4, 1.6...2.4, 7.9)
        case .pant: (30, 0.4, 2.5...3.5, 11.3)
        case .curiousTilt: (19, 0.4, 1.4...2.2, 13.7)
        }
    }

    static func idleEvent(_ kind: IdleEvent.Kind, cycle: Double) -> IdleEvent? {
        let s = schedule(kind)
        guard hash(cycle * 1.37 + s.salt) < s.chance else { return nil }
        let span = s.duration.upperBound - s.duration.lowerBound
        let duration = s.duration.lowerBound + hash(cycle + s.salt + 0.71) * span
        let start = cycle * s.period + 0.5 + hash(cycle + s.salt + 0.37) * max(0, s.period - duration - 1)
        return IdleEvent(kind: kind, start: start, duration: duration, seed: hash(cycle + s.salt + 1.3))
    }

    public static func idleEvents(at t: TimeInterval) -> [IdleEvent] {
        IdleEvent.Kind.allCases.compactMap { kind in
            let cycle = (t / schedule(kind).period).rounded(.down)
            guard let event = idleEvent(kind, cycle: cycle), t >= event.start, t <= event.end else { return nil }
            return event
        }
    }

    static func apply(_ event: IdleEvent, at t: TimeInterval, to p: inout CharacterPose) {
        let dt = t - event.start
        let env = event.envelope(at: t)
        switch event.kind {
        case .glance:
            let target = SIMD2(event.seed * 2 - 1, (hash(event.start) * 2 - 1) * 0.5)
            p.gazeX += target.x * env
            p.gazeY += target.y * env
        case .earTwitch:
            let flick = 0.32 * sin(dt * 28) * exp(-dt * 6)
            if event.seed < 0.5 { p.earLeft += flick } else { p.earRight += flick }
        case .wag:
            // Corgi wag: the tail goes, and the back end wiggles along with it.
            p.tail += 0.45 * sin(dt * 16) * env
            p.tilt += 0.015 * sin(dt * 16) * env
        case .pant:
            p.tongue = max(p.tongue, env)
            p.mouthOpen = max(p.mouthOpen, (0.42 + 0.1 * sin(dt * 14)) * env)
            p.squash += 0.015 * sin(dt * 14) * env
            p.eyeSmile = max(p.eyeSmile, 0.35 * env)
        case .curiousTilt:
            p.headTilt += (event.seed < 0.5 ? -1 : 1) * 0.2 * env
            p.earPerk = min(1, p.earPerk + 0.15 * env)
        }
    }

    func nextIdleEventEdge(after t: TimeInterval) -> TimeInterval {
        guard state == .idle else { return .infinity }
        var next = TimeInterval.infinity
        for kind in IdleEvent.Kind.allCases where !(kind == .glance && hovering) {
            let period = Self.schedule(kind).period
            let cycle = (t / period).rounded(.down)
            for c in [cycle, cycle + 1] {
                guard let event = Self.idleEvent(kind, cycle: c) else { continue }
                let edges = [event.start, event.end - Self.idleRamp]
                if let edge = edges.filter({ $0 > t }).min() { next = min(next, edge) }
            }
        }
        return next
    }

    // MARK: Math

    /// Turns a unit vector toward another the shorter way round; k from 0 to 1.
    static func turn(from a: SIMD2<Double>, to b: SIMD2<Double>, by k: Double) -> SIMD2<Double> {
        let start = atan2(a.y, a.x)
        var delta = atan2(b.y, b.x) - start
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        let angle = start + delta * k
        return SIMD2(cos(angle), sin(angle))
    }

    /// Smoothstep, clamped to 0…1.
    static func ease(_ x: Double) -> Double {
        let k = min(1, max(0, x))
        return k * k * (3 - 2 * k)
    }

    /// Cheap deterministic noise in 0..<1.
    static func hash(_ x: Double) -> Double {
        let v = sin(x * 12.9898 + 78.233) * 43758.5453
        return v - v.rounded(.down)
    }
}
