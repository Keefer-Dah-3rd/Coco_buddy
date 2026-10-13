import Foundation
import Testing
@testable import BuddyCharacter

@Suite struct BallFlightTests {
    let t0: TimeInterval = 800_000_000
    let from = SIMD2<Double>(1000, 100)

    func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    @Test func arcsUpUnderGravityAndLandsWhereAimed() {
        let ball = BallFlight(from: from, height: 30, to: SIMD2(500, 160), at: t0)
        #expect(ball.height(at: t0) == 30)
        #expect(length(ball.ground(at: ball.landTime) - SIMD2(500, 160)) < 0.5)
        #expect(ball.height(at: ball.landTime - 1e-6) < 1)
        // Up, then down: a real arc, peaking well above the launch.
        let samples = stride(from: t0, to: ball.landTime, by: 0.01).map(ball.height)
        let peak = samples.max()!
        #expect(peak > 100)
        let peakIndex = samples.firstIndex(of: peak)!
        #expect(peakIndex > 5 && peakIndex < samples.count - 5)
    }

    @Test func bouncesLowerEachTimeThenRollsToAStop() {
        let ball = BallFlight(from: from, height: 30, to: SIMD2(400, 100), at: t0)
        let impacts = ball.impacts
        #expect(impacts.count >= 3)
        // Peak height between consecutive impacts shrinks every time.
        var peaks: [Double] = []
        for (a, b) in zip(impacts, impacts.dropFirst()) {
            peaks.append(stride(from: a, to: b, by: 0.002).map(ball.height).max()!)
        }
        for (a, b) in zip(peaks, peaks.dropFirst()) { #expect(b < a) }
        #expect(peaks.first! > 20)
        // It keeps going the same way, slower, and ends at rest beyond where it first landed.
        #expect(ball.rest.x < 400)
        #expect(ball.restTime > impacts.last!)
        #expect(ball.ground(at: ball.restTime + 5) == ball.rest)
        #expect(ball.height(at: ball.restTime + 5) == 0)
    }

    @Test func neverGoesBelowTheFloorOrJumps() {
        let ball = BallFlight(from: from, height: 40, to: SIMD2(300, 400), at: t0)
        var previous = ball.ground(at: t0)
        for t in stride(from: t0, through: ball.restTime + 0.5, by: 1.0 / 120) {
            #expect(ball.height(at: t) >= 0)
            let now = ball.ground(at: t)
            #expect(length(now - previous) < 25)
            previous = now
        }
    }

    @Test func spinsWithItsTravelAndStopsWhenItStops() {
        let left = BallFlight(from: from, height: 30, to: SIMD2(500, 100), at: t0)
        let right = BallFlight(from: from, height: 30, to: SIMD2(1500, 100), at: t0)
        #expect(left.spin(at: left.landTime) < 0)
        #expect(right.spin(at: right.landTime) > 0)
        let settled = left.spin(at: left.restTime)
        #expect(abs(left.spin(at: left.restTime + 2) - settled) < 1e-9)
        // Spin never reverses mid-flight.
        var last = 0.0
        for t in stride(from: t0, through: left.restTime, by: 0.01) {
            let s = left.spin(at: t)
            #expect(s <= last + 1e-9)
            last = s
        }
    }

    @Test func aGentleDropBarelyBounces() {
        let drop = BallFlight(from: from, height: 10, to: from + SIMD2(0, -4), at: t0, flightTime: 0.1, bounciness: 0.5)
        #expect(drop.restTime - t0 < 0.6)
        #expect(length(drop.rest - from) < 30)
    }
}

@Suite struct FetchTests {
    let t0: TimeInterval = 800_000_000
    let home = SIMD2<Double>(1200, 120)
    let reach = 52.0

    func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    func fetch(to landing: SIMD2<Double>) -> Fetch {
        let ball = BallFlight(from: home + SIMD2(-20, 0), height: 40, to: landing, at: t0)
        return Fetch(home: home, ball: ball, at: t0, reach: reach, mouthHeight: 9)
    }

    @Test func runsPhasesInOrderAndEndsHome() {
        let game = fetch(to: SIMD2(600, 300))
        var order: [String] = []
        for t in stride(from: t0, through: game.endTime + 0.1, by: 0.01) {
            let name: String
            switch game.phase(at: t) {
            case .notice: name = "notice"
            case .chase: name = "chase"
            case .pickup: name = "pickup"
            case .homeward: name = "homeward"
            case .drop: name = "drop"
            case .finished: name = "finished"
            }
            if order.last != name { order.append(name) }
        }
        #expect(order == ["notice", "chase", "pickup", "homeward", "drop", "finished"])
        #expect(game.position(at: game.endTime + 1) == home)
    }

    @Test func setsOffBeforeTheBallLandsAndArrivesAsItSettles() {
        let game = fetch(to: SIMD2(500, 260))
        #expect(game.chase.launchTime < game.ball.landTime)
        #expect(game.chase.arrivalTime >= game.ball.restTime)
        #expect(game.chase.arrivalTime - game.ball.restTime < 0.6)
    }

    @Test func mouthEndsOverTheBall() {
        for landing in [SIMD2<Double>(600, 300), SIMD2(1250, 600), SIMD2(1500, 40), SIMD2(900, 120)] {
            let game = fetch(to: landing)
            let mouth = game.pickupSpot + Fetch.mouthOffset(facing: game.pickupFacing, reach: reach)
            #expect(length(mouth - game.ball.rest) < 0.5)
            // She faces the ball, not away from it.
            let towardBall = game.ball.rest - game.pickupSpot
            let facingOnScreen = SIMD2(game.pickupFacing.x, game.pickupFacing.y * sin(Dash.viewElevation))
            #expect(towardBall.x * facingOnScreen.x + towardBall.y * facingOnScreen.y > 0)
        }
    }

    @Test func carriesOnlyBetweenPickupAndDrop() {
        let game = fetch(to: SIMD2(700, 200))
        #expect(game.looseBall(at: game.contactTime - 0.01) != nil)
        #expect(game.looseBall(at: game.contactTime + 0.01) == nil)
        #expect(game.isCarrying(at: game.homeward.launchTime + 0.2))
        #expect(game.looseBall(at: game.releaseTime + 0.01) != nil)
        // At pickup the loose ball is resting right where she reaches.
        let resting = game.looseBall(at: game.contactTime - 0.01)!
        #expect(resting.height == 0 && length(resting.ground - game.ball.rest) < 0.5)
        // It ends at rest by her paws.
        let final = game.looseBall(at: game.endTime + 1)!
        #expect(final.height == 0 && length(final.ground - game.home) < 40)
    }

    @Test func posesSwapCleanlyAndCarryMatchesThePlan() {
        let game = fetch(to: SIMD2(650, 280))
        var animator = CharacterAnimator()
        animator.setFetch(game)
        var swaps = 0
        var previous = animator.pose(at: t0).run
        for t in stride(from: t0, through: game.endTime + 0.2, by: 1.0 / 240) {
            let pose = animator.pose(at: t)
            #expect(pose.run == 0 || pose.run == 1)
            if pose.run != previous { swaps += 1 }
            previous = pose.run
            #expect((pose.carry == 1) == game.isCarrying(at: t))
            #expect(animator.motionFrameInterval(at: t) == CharacterAnimator.fastFrameInterval || t >= game.endTime)
        }
        // Sitting → running when the chase starts, running → sitting after the drop.
        #expect(swaps == 2)
        // Her head is all the way down at the moment the ball is picked up.
        #expect(animator.pose(at: game.contactTime - 0.001).reach > 0.95)
    }

    @Test func aBallLandingRightBesideHerIsStillFetched() {
        let game = fetch(to: home + SIMD2(-30, -10))
        #expect(game.endTime > game.startTime)
        let mouth = game.pickupSpot + Fetch.mouthOffset(facing: game.pickupFacing, reach: reach)
        #expect(length(mouth - game.ball.rest) < 0.5)
    }
}
