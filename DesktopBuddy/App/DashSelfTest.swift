#if DEBUG
import AppKit
import BuddyCharacter

/// Runs real dashes through the real window controller with Coco's window fully
/// transparent (nothing shows, clicks pass through) and reports what happened.
/// Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --dash-selftest
enum DashSelfTest {
    static func run() {
        let model = CharacterModel()
        let controller = CharacterWindowController(model: model)
        controller.window.alphaValue = 0
        guard let screen = NSScreen.main?.visibleFrame else { return print("dash selftest: no screen") }
        controller.place(at: CGPoint(x: screen.maxX - 220, y: screen.minY + 20))
        controller.setVisible(true)

        var moves: [(t: TimeInterval, origin: NSPoint)] = []
        let observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: controller.window, queue: nil) { _ in
            MainActor.assumeIsolated { moves.append((CharacterModel.clock, controller.window.frame.origin)) }
        }
        var finished = 0
        controller.onDashFinished = { finished += 1 }
        let cpuBefore = cpuSeconds()
        let started = CharacterModel.clock

        // Call her across the screen, then change course partway through the run.
        let first = CGPoint(x: screen.minX + screen.width * 0.25, y: screen.midY)
        let second = CGPoint(x: screen.midX, y: screen.minY + screen.height * 0.7)
        controller.call(to: first)
        spin(until: { model.dash.map { CharacterModel.clock > $0.launchTime + 0.45 } ?? true }, limit: 3)
        controller.call(to: second)
        let lastDash = model.dash
        spin(until: { finished > 0 }, limit: 6)

        let elapsed = CharacterModel.clock - started
        let cpu = cpuSeconds() - cpuBefore
        NotificationCenter.default.removeObserver(observer)
        let expected = controller.destination(forClickAt: second)
        let paws = CGPoint(x: controller.window.frame.minX + CharacterLayout.artFrame.midX,
                           y: controller.window.frame.minY + CharacterLayout.artFrame.minY + CharacterLayout.artFrame.height * 0.07)
        let gaps = zip(moves.dropFirst(), moves).map { $0.t - $1.t }
        if let worst = gaps.indices.max(by: { gaps[$0] < gaps[$1] }), let dash = model.dash ?? lastDash {
            print(String(format: "dash selftest: longest gap ends %.3f s after launch (arrival at %.3f s)",
                         moves[worst + 1].t - dash.launchTime, dash.arrivalTime - dash.launchTime))
        }
        let jumps = zip(moves.dropFirst(), moves).map { hypot($0.origin.x - $1.origin.x, $0.origin.y - $1.origin.y) }
        print(String(format: "dash selftest: finished=%d, landed %.1f pt from the click target, %d moves in %.2f s",
                     finished, hypot(paws.x - expected.x, paws.y - expected.y), moves.count, elapsed))
        print(String(format: "dash selftest: longest gap between moves %.1f ms, biggest step %.1f pt, CPU %.1f%% of one core",
                     (gaps.max() ?? 0) * 1000, jumps.max() ?? 0, cpu / elapsed * 100))
        controller.setVisible(false)
    }

    private static func spin(until done: () -> Bool, limit: TimeInterval) {
        let deadline = Date().addingTimeInterval(limit)
        while !done(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}
#endif
