import Foundation
import Testing
@testable import BuddyCharacter

@Suite struct TreatTests {
    let t0: TimeInterval = 800_000_000
    let home = SIMD2<Double>(1100, 140)
    let reach = 52.0

    func length(_ v: SIMD2<Double>) -> Double { (v.x * v.x + v.y * v.y).squareRoot() }

    func toss(to landing: SIMD2<Double>) -> TreatGame {
        let flight = BallFlight(from: home + SIMD2(-10, 0), height: 60, to: landing, at: t0, material: .treat)
        return TreatGame(home: home, treat: flight, at: t0, reach: reach)
    }

    @Test func aTreatFliesLowerAndQuickerThanABallAndBarelySlides() {
        let landing = SIMD2<Double>(500, 300)
        let ball = BallFlight(from: home, height: 46, to: landing, at: t0)
        let treat = BallFlight(from: home, height: 46, to: landing, at: t0, material: .treat)
        #expect(treat.landTime < ball.landTime)
        let ballPeak = stride(from: t0, to: ball.landTime, by: 0.005).map(ball.height).max()!
        let treatPeak = stride(from: t0, to: treat.landTime, by: 0.005).map(treat.height).max()!
        #expect(treatPeak < ballPeak)
        #expect(length(treat.rest - landing) < length(ball.rest - landing) / 2)
        #expect(treat.restTime - treat.landTime < ball.restTime - ball.landTime)
        // It tumbles in the air, then stops turning once it's down.
        #expect(abs(treat.spin(at: treat.landTime)) > 3)
        #expect(treat.spin(at: treat.restTime) == treat.spin(at: treat.restTime + 1))
        for t in stride(from: t0, through: treat.restTime + 0.2, by: 0.005) { #expect(treat.height(at: t) >= 0) }
    }

    @Test func runsItsBeatsInOrderAndNeverDrifts() {
        let game = toss(to: SIMD2(600, 320))
        var order: [String] = []
        for t in stride(from: t0, through: game.endTime + 0.1, by: 0.01) {
            let name: String
            switch game.phase(at: t) {
            case .notice: name = "notice"
            case .chase: name = "chase"
            case .eat: name = "eat"
            case .celebrate: name = "celebrate"
            case .finished: name = "finished"
            }
            if order.last != name { order.append(name) }
        }
        #expect(order == ["notice", "chase", "eat", "celebrate", "finished"])
        // From the first bite to the end she stays exactly on her spot — the jump is straight up.
        for t in stride(from: game.eatStart, through: game.endTime + 1, by: 0.02) {
            #expect(game.position(at: t) == game.eatSpot)
        }
    }

    @Test func setsOffWhileItsInTheAirAndArrivesAsItSettles() {
        let game = toss(to: SIMD2(520, 260))
        #expect(game.chase.launchTime < game.treat.landTime)
        #expect(game.chase.arrivalTime >= game.treat.restTime)
    }

    @Test func mouthEndsOverTheTreatAndItsGoneAtTheBite() {
        let game = toss(to: SIMD2(700, 420))
        let mouth = game.eatSpot + Fetch.mouthOffset(facing: game.eatFacing, reach: reach)
        #expect(length(mouth - game.treat.rest) < 0.5)
        #expect(game.looseTreat(at: game.biteTime - 0.001) != nil)
        #expect(game.looseTreat(at: game.biteTime) == nil)
        let resting = game.looseTreat(at: game.biteTime - 0.001)!
        #expect(resting.height == 0 && length(resting.ground - game.treat.rest) < 0.5)
    }

    @Test func posesSwapCleanlyHeadIsDownAtTheBiteAndTheJumpPeaksInTheAir() {
        let game = toss(to: SIMD2(650, 300))
        var animator = CharacterAnimator()
        animator.setTreat(game)
        var swaps = 0
        var previous = animator.pose(at: t0).run
        for t in stride(from: t0, through: game.endTime + 0.2, by: 1.0 / 240) {
            let pose = animator.pose(at: t)
            #expect(pose.run == 0 || pose.run == 1)
            if pose.run != previous { swaps += 1 }
            previous = pose.run
        }
        #expect(swaps == 2)
        #expect(animator.pose(at: game.biteTime - 0.001).reach > 0.95)
        let celebrate = { (k: Double) in game.celebrateStart + TreatGame.celebrateDuration * k }
        let peak = animator.pose(at: celebrate((TreatGame.takeoff + TreatGame.landing) / 2))
        #expect(abs(peak.lift - TreatGame.jumpHeight) < 0.5)
        #expect(animator.pose(at: celebrate(TreatGame.takeoff - 0.01)).crouch > 0.6)
        #expect(animator.pose(at: celebrate(TreatGame.landing + 0.01)).crouch > 0.5)
        #expect(peak.sparkles == 1)
    }

    @Test func beggingEasesInHoldsAndSettlesWithoutJumping() {
        var animator = CharacterAnimator()
        animator.setBegging(true, at: t0)
        #expect(animator.pose(at: t0).beg == 0)
        #expect(animator.pose(at: t0 + 0.12).beg > 0 && animator.pose(at: t0 + 0.12).beg < 1)
        #expect(animator.pose(at: t0 + 3).beg == 1)
        #expect(animator.motionFrameInterval(at: t0 + 3) == CharacterAnimator.fastFrameInterval)
        animator.setBegging(false, at: t0 + 3)
        #expect(animator.pose(at: t0 + 3).beg == 1)
        #expect(animator.pose(at: t0 + 3 + CharacterAnimator.begEase).beg == 0)
        // Picking it up again mid-settle carries on from where she was.
        animator.setBegging(true, at: t0 + 3.1)
        let before = animator.pose(at: t0 + 3.1 - 1e-6).beg
        let after = animator.pose(at: t0 + 3.1).beg
        #expect(abs(before - after) < 0.02)
    }
}
