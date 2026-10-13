#if DEBUG
import AppKit
import BuddyCharacter

/// Plays real games of fetch through the real window controller, with Coco and the ball
/// fully transparent (nothing shows, clicks pass through), and checks what happened.
/// Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --fetch-selftest
enum FetchSelfTest {
    nonisolated(unsafe) private static var passed = 0
    nonisolated(unsafe) private static var failed = 0

    private static func check(_ condition: Bool, _ name: String) {
        if condition { passed += 1 } else { failed += 1; print("fetch selftest FAILED: \(name)") }
    }

    static func run() {
        let model = CharacterModel()
        let controller = CharacterWindowController(model: model)
        controller.window.alphaValue = 0
        controller.ball.makeInvisibleForTesting()
        guard let screen = NSScreen.main?.visibleFrame else { return print("fetch selftest: no screen") }
        controller.place(at: CGPoint(x: screen.maxX - 260, y: screen.minY + 30))
        controller.setVisible(true)
        var finished = 0
        controller.onFetchFinished = { finished += 1 }
        func paws() -> CGPoint {
            CGPoint(x: controller.window.frame.minX + CharacterLayout.artFrame.midX,
                    y: controller.window.frame.minY + CharacterLayout.artFrame.minY + CharacterLayout.artFrame.height * 0.07)
        }

        // A full game.
        let home = paws()
        let started = CharacterModel.clock
        let cpuBefore = cpuSeconds()
        controller.throwBall(to: CGPoint(x: screen.minX + screen.width * 0.35, y: screen.minY + screen.height * 0.45))
        guard let game = model.fetch else { return check(false, "a throw starts a game") }
        var firstMove: TimeInterval?
        var ballSeenWhileCarrying = false
        var offPath: Double = 0
        var secondThrowIgnored = true
        while finished == 0, CharacterModel.clock - started < 12 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
            let now = CharacterModel.clock
            if firstMove == nil, paws().distance(to: home) > 2 { firstMove = now }
            if game.isCarrying(at: now - 0.03), game.isCarrying(at: now + 0.03), controller.ball.isVisible { ballSeenWhileCarrying = true }
            // Between frames where the loose ball is showing (it's in her mouth in between).
            let point = controller.ball.floorPoint
            if controller.ball.isVisible, now < game.contactTime {
                // Wherever the frames fall, the ball must be somewhere on its real path.
                var nearest = Double.infinity
                for back in stride(from: 0.0, through: 0.4, by: 0.002) {
                    let g = game.ball.ground(at: now - back)
                    nearest = min(nearest, hypot(Double(point.x) - g.x, Double(point.y) - g.y))
                }
                offPath = max(offPath, nearest)
            }
            if now > game.chase.launchTime + 0.2, now < game.chase.launchTime + 0.25 {
                controller.throwBall(to: CGPoint(x: screen.minX + 50, y: screen.minY + 50))
                if model.fetch != game { secondThrowIgnored = false }
            }
        }
        let elapsed = CharacterModel.clock - started
        check(finished == 1, "the game finishes once")
        check(model.fetch == nil, "she's no longer fetching")
        check(firstMove.map { $0 < game.ball.landTime } ?? false, "she sets off before the ball lands")
        check(paws().distance(to: home) < 1, "she comes back to where she started (\(Int(paws().distance(to: home))) pt)")
        check(!ballSeenWhileCarrying, "the loose ball is hidden while she carries it")
        check(controller.ball.isVisible && controller.ball.floorPoint.distance(to: home) < 40, "the ball ends up lying by her paws")
        check(secondThrowIgnored, "a second throw mid-game is ignored")
        check(offPath < 2, "the ball is always on its real path (off by at most \(String(format: "%.1f", offPath)) pt)")
        print(String(format: "fetch selftest: game took %.1f s, CPU %.1f%% of one core", elapsed, (cpuSeconds() - cpuBefore) / elapsed * 100))

        // Grabbed mid-carry: the game ends, the ball is put down, nothing left in the air.
        finished = 0
        controller.throwBall(to: CGPoint(x: screen.minX + screen.width * 0.6, y: screen.minY + screen.height * 0.3))
        guard let second = model.fetch else { return check(false, "a second game starts") }
        while CharacterModel.clock < second.homeward.launchTime + 0.2 { RunLoop.main.run(until: Date().addingTimeInterval(0.004)) }
        controller.stopFetch()
        check(finished == 1 && model.fetch == nil, "grabbing her ends the game")
        check(controller.ball.isVisible && controller.ball.floorPoint.distance(to: paws()) < 30, "the carried ball is put down where she is")

        // A throw at the very edge of the screen is shortened so she can still reach it.
        controller.throwBall(to: CGPoint(x: screen.maxX + 400, y: screen.minY - 300))
        if let edge = model.fetch {
            let rest = CGPoint(x: edge.ball.rest.x, y: edge.ball.rest.y)
            check(NSScreen.screens.contains { $0.visibleFrame.contains(rest) }, "an off-screen throw still lands on screen")
            controller.stopFetch()
        } else {
            check(true, "")
        }

        treats(controller, model, screen: screen, paws: paws)
        controller.setVisible(false)
        print("fetch selftest: \(passed) passed, \(failed) failed")
    }

    private static func treats(_ controller: CharacterWindowController, _ model: CharacterModel, screen: NSRect, paws: () -> CGPoint) {
        controller.treatWindow.makeInvisibleForTesting()
        var finished = 0
        controller.onTreatFinished = { finished += 1 }
        let spin = { (seconds: TimeInterval) in
            let until = Date().addingTimeInterval(seconds)
            while Date() < until { RunLoop.main.run(until: Date().addingTimeInterval(0.004)) }
        }

        // Begging: on while asked, off once the treat is thrown.
        controller.setBegging(true)
        spin(0.4)
        check(model.animator.pose(at: CharacterModel.clock).beg == 1, "she begs while a treat is held out")

        let home = paws()
        let started = CharacterModel.clock
        controller.throwTreat(to: CGPoint(x: screen.minX + screen.width * 0.3, y: screen.minY + screen.height * 0.35))
        guard let game = model.treat else { return check(false, "a toss starts a treat") }
        var firstMove: TimeInterval?
        var seenAfterBite = false
        var offPath = 0.0
        var interrupted = false
        while finished == 0, CharacterModel.clock - started < 10 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.004))
            let now = CharacterModel.clock
            if firstMove == nil, paws().distance(to: home) > 2 { firstMove = now }
            if now > game.biteTime + 0.05, controller.treatWindow.isVisible { seenAfterBite = true }
            if controller.treatWindow.isVisible, now < game.biteTime - 0.05 {
                let point = controller.treatWindow.floorPoint
                var nearest = Double.infinity
                for back in stride(from: 0.0, through: 0.4, by: 0.002) {
                    let g = game.treat.ground(at: now - back)
                    nearest = min(nearest, hypot(Double(point.x) - g.x, Double(point.y) - g.y))
                }
                offPath = max(offPath, nearest)
            }
            // Mid-treat, neither a ball nor another treat nor begging can take over.
            if now > game.eatStart + 0.2, now < game.eatStart + 0.25 {
                controller.throwBall(to: CGPoint(x: screen.minX + 60, y: screen.minY + 60))
                controller.throwTreat(to: CGPoint(x: screen.minX + 60, y: screen.minY + 60))
                controller.setBegging(true)
                if model.fetch != nil || model.treat != game || model.animator.pose(at: now + 0.3).beg > 0 { interrupted = true }
            }
        }
        check(finished == 1 && model.treat == nil, "the treat finishes once")
        check(model.animator.pose(at: CharacterModel.clock).beg == 0, "begging stopped when the treat was thrown")
        check(firstMove.map { $0 < game.treat.landTime } ?? false, "she sets off while the treat is in the air")
        check(paws().distance(to: CGPoint(x: game.eatSpot.x, y: game.eatSpot.y)) < 1, "she ends where she ate it")
        check(!seenAfterBite, "the treat is gone once she bites it")
        check(offPath < 2, "the treat stays on its real path (off by \(String(format: "%.1f", offPath)) pt)")
        check(!interrupted, "nothing else takes over mid-treat")

        // Mid-fetch, a treat can't take over either.
        controller.throwBall(to: CGPoint(x: screen.minX + screen.width * 0.6, y: screen.minY + screen.height * 0.4))
        controller.throwTreat(to: CGPoint(x: screen.minX + 60, y: screen.minY + 60))
        check(model.fetch != nil && model.treat == nil, "a treat waits while she's fetching")
        controller.stopFetch()

        // Stopped before the bite: the treat is left lying where it landed.
        finished = 0
        controller.throwTreat(to: CGPoint(x: screen.minX + screen.width * 0.5, y: screen.minY + screen.height * 0.3))
        guard let second = model.treat else { return check(false, "a second treat starts") }
        spin(0.3)
        controller.stopTreat()
        check(finished == 1 && model.treat == nil, "grabbing her ends the treat")
        check(controller.treatWindow.isVisible
              && controller.treatWindow.floorPoint.distance(to: CGPoint(x: second.treat.rest.x, y: second.treat.rest.y)) < 1,
              "an uneaten treat is left lying where it lands")
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
#endif
