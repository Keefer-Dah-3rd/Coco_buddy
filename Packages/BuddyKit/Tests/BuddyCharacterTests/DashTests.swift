import Foundation
import Testing
@testable import BuddyCharacter

@Suite struct DashTests {
    let t0: TimeInterval = 800_000_000
    let home = SIMD2<Double>(1200, 80)

    @Test func waitsForTheWindUpThenEndsExactlyOnTheSpot() {
        let dash = Dash(from: home, to: SIMD2(300, 600), at: t0)
        #expect(dash.position(at: t0) == home)
        #expect(dash.position(at: dash.launchTime - 0.01) == home)
        #expect(distance(dash.position(at: dash.arrivalTime), SIMD2(300, 600)) < 0.01)
        #expect(distance(dash.position(at: dash.endTime + 5), SIMD2(300, 600)) < 0.01)
        #expect(dash.phase(at: dash.endTime + 0.01) == .finished)
    }

    @Test func easesInAndOutWithoutJolts() {
        let dash = Dash(from: home, to: SIMD2(100, 700), at: t0)
        #expect(dash.speed(at: dash.launchTime) == 0)
        #expect(dash.speed(at: dash.arrivalTime) == 0)
        // Sample at 240 Hz: speed changes smoothly and never exceeds top speed.
        var previous = 0.0
        for t in stride(from: dash.launchTime, through: dash.arrivalTime, by: 1.0 / 240) {
            let v = dash.speed(at: t)
            #expect(v <= Dash.topSpeed + 1e-9)
            #expect(abs(v - previous) < Dash.topSpeed / 30)
            previous = v
        }
    }

    @Test func positionAndSpeedAgree() {
        let dash = Dash(from: home, to: SIMD2(400, 300), at: t0)
        let dt = 1.0 / 1000
        for t in stride(from: dash.launchTime + 0.05, to: dash.arrivalTime - 0.05, by: 0.07) {
            let measured = distance(dash.position(at: t + dt), dash.position(at: t)) / dt
            #expect(abs(measured - dash.speed(at: t)) < 15)
        }
    }

    @Test func longerDashesTakeLongerButNotForever() {
        let short = Dash(from: home, to: home + SIMD2(-150, 0), at: t0)
        let medium = Dash(from: home, to: home + SIMD2(-800, 0), at: t0)
        let long = Dash(from: home, to: home + SIMD2(-2400, 0), at: t0)
        let times = [short, medium, long].map { $0.arrivalTime - $0.launchTime }
        #expect(times[0] < times[1] && times[1] < times[2])
        #expect(times[0] > 0.3 && times[0] < 0.8)
        #expect(times[2] < 2.5)
    }

    @Test func headsStraightForTheSpotFromAStandstill() {
        let dash = Dash(from: home, to: home + SIMD2(-300, 400), at: t0)
        let expected = SIMD2<Double>(-0.6, 0.8)
        for t in [t0, dash.launchTime + 0.2, dash.arrivalTime + 0.1] {
            #expect(distance(dash.direction(at: t), expected) < 1e-6)
        }
    }

    @Test func changingCourseKeepsHerMovingSmoothly() {
        let first = Dash(from: home, to: home + SIMD2(-1200, 0), at: t0)
        let t = first.launchTime + 0.5
        let second = first.redirected(to: home + SIMD2(-600, 500), at: t)
        #expect(distance(second.position(at: t), first.position(at: t)) < 0.01)
        #expect(distance(second.velocity(at: t), first.velocity(at: t)) < 1)
        #expect(abs(second.strides(at: t) - first.strides(at: t)) < 1e-9)
        #expect(distance(second.position(at: second.arrivalTime), home + SIMD2(-600, 500)) < 0.01)
        // The new course bends round rather than snapping to face the new spot.
        let soon = second.direction(at: t + 0.05)
        #expect(soon.x < -0.5)
    }

    @Test func changingCourseDuringTheWindUpJustTurnsHer() {
        let first = Dash(from: home, to: home + SIMD2(-500, 0), at: t0)
        let second = first.redirected(to: home + SIMD2(0, 500), at: t0 + 0.2)
        #expect(second.launchTime == first.launchTime)
        #expect(second.position(at: t0 + 0.3) == home)
        #expect(distance(second.direction(at: t0 + 0.3), SIMD2(0, 1)) < 1e-6)
    }

    @Test func brakesWhenTheNewSpotIsRightThere() {
        let first = Dash(from: home, to: home + SIMD2(-2000, 0), at: t0)
        let t = first.launchTime + 0.8
        let here = first.position(at: t)
        let second = first.redirected(to: here + SIMD2(-15, 0), at: t)
        #expect(second.arrivalTime > t)
        #expect(distance(second.position(at: second.arrivalTime), here + SIMD2(-15, 0)) < 0.01)
    }

    @Test func legsSpeedUpAndSlowDownWithHer() {
        let dash = Dash(from: home, to: home + SIMD2(-1500, 0), at: t0)
        var previous = dash.strides(at: dash.launchTime)
        for t in stride(from: dash.launchTime, through: dash.endTime, by: 0.01) {
            let s = dash.strides(at: t)
            #expect(s >= previous)
            previous = s
        }
        let cruising = dash.launchTime + (dash.arrivalTime - dash.launchTime) / 2
        let rate = (dash.strides(at: cruising + 0.1) - dash.strides(at: cruising)) / 0.1
        #expect(abs(rate - Dash.topCadence) < 0.2)
        #expect(dash.strides(at: dash.endTime) == dash.strides(at: dash.endTime + 3))
    }

    @Test func goingNowhereFinishesWithoutMoving() {
        let dash = Dash(from: home, to: home, at: t0)
        #expect(dash.arrivalTime == dash.launchTime)
        #expect(dash.position(at: dash.endTime) == home)
        #expect(dash.direction(at: t0) == SIMD2(0, -1))
    }

    @Test func animatorDrawsEveryFrameOnlyWhileDashing() {
        var animator = CharacterAnimator()
        animator.setState(.focused, at: t0 - 10)
        let resting = animator
        let dash = Dash(from: home, to: home + SIMD2(-500, 0), at: t0)
        animator.setDash(dash)
        for t in stride(from: t0, to: dash.endTime, by: 0.05) {
            #expect(animator.motionFrameInterval(at: t) == CharacterAnimator.fastFrameInterval)
        }
        #expect(animator.pose(at: dash.launchTime + 0.2).tongue == 1)
        // Once she's sat back down the dash leaves no trace.
        let after = dash.endTime + 0.5
        #expect(animator.pose(at: after) == resting.pose(at: after))
        #expect(animator.motionFrameInterval(at: after) == resting.motionFrameInterval(at: after))
    }

    private func distance(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }
}
