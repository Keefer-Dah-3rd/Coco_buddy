import Foundation
import Testing
@testable import BuddyCharacter

@Suite struct CharacterAnimatorTests {
    let t0: TimeInterval = 800_000_000

    @Test func poseIsAPureFunctionOfTime() {
        let animator = CharacterAnimator()
        #expect(animator.pose(at: t0 + 1.234) == animator.pose(at: t0 + 1.234))
    }

    @Test func blinksHappenRegularlyAndBriefly() {
        // Sample one minute at 100 Hz.
        let samples = stride(from: t0, to: t0 + 60, by: 0.01).map(CharacterAnimator.blinkAmount)
        let closedFraction = Double(samples.filter { $0 > 0.5 }.count) / Double(samples.count)
        #expect(closedFraction > 0.005 && closedFraction < 0.05)
    }

    @Test func stateChangesBlendInsteadOfSnapping() {
        var animator = CharacterAnimator()
        let before = animator.pose(at: t0)
        animator.setState(.sleeping, at: t0)
        let mid = animator.pose(at: t0 + CharacterAnimator.transitionDuration / 2)
        let after = animator.pose(at: t0 + 1)

        #expect(after.sleepZ == 1)
        #expect(mid.sleepZ > 0 && mid.sleepZ < 1)
        #expect(before.earPerk > after.earPerk)
    }

    @Test func restingCharacterSleepsBetweenFrames() {
        var animator = CharacterAnimator()
        animator.setState(.focused, at: t0)
        // Find a quiet moment (no transition, no blink) and check we don't spin at 60 fps.
        let quiet = stride(from: t0 + 1, to: t0 + 10, by: 0.05).first { !animator.isMovingQuickly(at: $0) }!
        #expect(animator.nextFrameTime(after: quiet) - quiet > CharacterAnimator.fastFrameInterval * 2)
    }

    @Test func schedulerWakesUpForTheNextBlink() {
        var animator = CharacterAnimator()
        animator.setState(.focused, at: t0)
        let quiet = t0 + 1
        let blink = animator.nextBlinkStart(after: quiet)
        var t = quiet
        while t < blink { t = animator.nextFrameTime(after: t) }
        // The frame sequence lands on (or within a frame of) the blink, not after it.
        #expect(t - blink < CharacterAnimator.fastFrameInterval + 1e-9)
    }

    @Test func celebratingRunsAtFullFrameRate() {
        var animator = CharacterAnimator()
        animator.setState(.celebrating, at: t0)
        #expect(abs(animator.nextFrameTime(after: t0 + 5) - (t0 + 5) - CharacterAnimator.fastFrameInterval) < 1e-6)
    }

    @Test func reduceMotionKeepsExpressionButDropsBodyMotion() {
        var animator = CharacterAnimator()
        animator.reduceMotion = true
        animator.setState(.celebrating, at: t0)
        let pose = animator.pose(at: t0 + 2.1)
        #expect(pose.lift == 0 && pose.squash == 0)
        #expect(pose.eyeSmile == 1)
    }

    @Test func carryingWakesTheEyes() {
        var animator = CharacterAnimator()
        animator.setState(.sleeping, at: t0)
        animator.setCarried(true, at: t0 + 2)
        #expect(animator.pose(at: t0 + 3).eyeOpen > 0.9)
    }

    @Test func idleLifeIsDeterministicAndOccasional() {
        // Over ten minutes every kind of idle behaviour shows up, but none dominates.
        let samples = stride(from: t0, to: t0 + 600, by: 0.1).map(CharacterAnimator.idleEvents)
        for kind in CharacterAnimator.IdleEvent.Kind.allCases {
            let share = Double(samples.filter { $0.contains { $0.kind == kind } }.count) / Double(samples.count)
            #expect(share > 0.01 && share < 0.4, "\(kind) active \(share)")
        }
        #expect(CharacterAnimator.idleEvents(at: t0 + 123.4) == CharacterAnimator.idleEvents(at: t0 + 123.4))
    }

    @Test func schedulerWakesUpForIdleEvents() {
        let animator = CharacterAnimator()
        // Find the first wag and walk the frame sequence up to it.
        let wag = stride(from: t0, to: t0 + 120, by: 0.05)
            .compactMap { CharacterAnimator.idleEvents(at: $0).first { $0.kind == .wag } }.first!
        var t = wag.start - 3
        while t < wag.start { t = animator.nextFrameTime(after: t) }
        #expect(t - wag.start < CharacterAnimator.fastFrameInterval + 1e-6)
    }

    @Test func listeningPerksEarsAndLightsTheTag() {
        var animator = CharacterAnimator()
        animator.setState(.listening, at: t0)
        let pose = animator.pose(at: t0 + 1)
        #expect(pose.earPerk == 1)
        #expect(pose.headTilt > 0.1)
        #expect(pose.led > 0.1)
    }
}
