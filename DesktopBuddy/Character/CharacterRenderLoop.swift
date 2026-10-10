import AppKit
import QuartzCore
import os

/// Decides when the character gets redrawn.
///
/// While something is visibly moving (a hop, a blink, a glance, being carried) frames
/// come from a display link, in step with the screen. The rest of the time the loop
/// asks the animator when the next thing will happen and sleeps until then with a
/// single timer — a resting buddy wakes ~10 times a second, a sleeping one ~6.
final class CharacterRenderLoop: NSObject {
    private let model: CharacterModel
    private weak var view: CocoLayerView?
    private var displayLink: CADisplayLink?
    private var restTimer: Timer?

    /// Nothing is drawn while paused (hidden, fully covered, displays asleep).
    var isPaused = false {
        didSet { if isPaused != oldValue { reschedule() } }
    }

    private var lowPower = false

    init(model: CharacterModel, view: CocoLayerView) {
        self.model = model
        self.view = view
        super.init()
    }

    /// Call whenever the animator or presentation changed: draws now and re-plans.
    func setNeedsFrame() {
        renderNow()
        reschedule()
    }

    func applyPowerMode(lowPower: Bool) {
        self.lowPower = lowPower
        displayLink?.preferredFrameRateRange = lowPower
            ? CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            : .default
    }

    /// A view's display link only ticks once the view is on a screen, so it's
    /// created on first use rather than up front.
    private func activeDisplayLink() -> CADisplayLink? {
        if let displayLink { return displayLink }
        guard let view, view.window != nil else { return nil }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        applyPowerMode(lowPower: lowPower)
        return link
    }

    @objc private func step(_ link: CADisplayLink) {
        renderNow()
        if !model.animator.isMovingQuickly(at: CharacterModel.clock) {
            reschedule()
        }
    }

    private func renderNow() {
        guard !isPaused, let view else { return }
        view.render(model.animator.pose(at: CharacterModel.clock), focusProgress: model.focusProgress)
        #if DEBUG
        FrameStats.shared.count()
        #endif
    }

    private func reschedule() {
        restTimer?.invalidate()
        restTimer = nil
        guard !isPaused else {
            displayLink?.isPaused = true
            return
        }
        let now = CharacterModel.clock
        var next = model.animator.nextFrameTime(after: now)
        if next - now < 1.0 / 40 {
            if let link = activeDisplayLink() {
                link.isPaused = false
                return
            }
            next = now + 1.0 / 60  // Not on screen yet: fall back to a timer.
        }
        displayLink?.isPaused = true
        let timer = Timer(fire: Date(timeIntervalSinceReferenceDate: next), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.renderNow()
                self?.reschedule()
            }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        restTimer = timer
    }
}

#if DEBUG
/// Logs frames-per-second every 10 s in Debug builds, to keep an eye on the energy budget.
/// `log stream --predicate 'subsystem == "com.keefer.DesktopBuddy"'`
private final class FrameStats {
    static let shared = FrameStats()
    private var frames = 0
    private var windowStart = Date()
    private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "render")

    func count() {
        frames += 1
        let elapsed = Date().timeIntervalSince(windowStart)
        guard elapsed >= 10 else { return }
        log.notice("render: \(Double(self.frames) / elapsed, format: .fixed(precision: 1), privacy: .public) fps")
        frames = 0
        windowStart = Date()
    }
}
#endif
