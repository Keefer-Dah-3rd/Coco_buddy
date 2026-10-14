import Foundation
import Observation
import BuddyCharacter

/// The live character: owns the animator, decides which state is showing, and
/// holds what the buddy is saying. Everything visual reads from here.
///
/// States come in two layers: a *base* state that reflects the situation
/// (idle, focused, sleeping) and an optional *transient* state played for a few
/// seconds on top (celebrating, talking) before falling back to the base.
@Observable
final class CharacterModel {
    struct Speech: Equatable, Identifiable {
        let id = UUID()
        let text: String
        let duration: TimeInterval
    }

    struct Countdown: Equatable {
        var text: String
        var isBreak: Bool
        var isPaused: Bool
    }

    private(set) var animator = CharacterAnimator()
    private(set) var speech: Speech?

    /// Rendering stops entirely while hidden, fully covered, or displays are asleep.
    var isRenderingPaused = false
    /// Caps the frame rate (Low Power Mode).
    var isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    var scale: CGFloat = 1
    var isDimmed = false
    var focusProgress: Double?
    var countdown: Countdown?

    @ObservationIgnored private var baseState: CharacterState = .idle
    @ObservationIgnored private var transient: CharacterState?
    @ObservationIgnored private var transientTask: Task<Void, Never>?
    @ObservationIgnored private var speechTask: Task<Void, Never>?

    var state: CharacterState { animator.state }

    static var clock: TimeInterval { Date().timeIntervalSinceReferenceDate }

    func setBaseState(_ state: CharacterState) {
        guard state != baseState else { return }
        baseState = state
        apply()
    }

    /// Shows a state for a while, then returns to the base state.
    func play(_ state: CharacterState, for duration: TimeInterval) {
        transient = state
        apply()
        transientTask?.cancel()
        transientTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.transient = nil
            self.apply()
        }
    }

    func react(_ reaction: CharacterReaction) {
        animator.react(reaction, at: Self.clock)
    }

    func look(at target: SIMD2<Double>?) {
        animator.look(at: target, at: Self.clock)
    }

    func setCarried(_ carried: Bool) {
        animator.setCarried(carried, at: Self.clock)
    }

    func setReduceMotion(_ reduce: Bool) {
        animator.reduceMotion = reduce
    }

    /// Running somewhere she was called to; the window follows `dash.position(at:)`.
    var dash: Dash? { animator.dash }

    func setDash(_ dash: Dash?) {
        animator.setDash(dash)
    }

    /// Playing fetch; the window and the ball follow it.
    var fetch: Fetch? { animator.fetch }

    func setFetch(_ game: Fetch?) {
        animator.setFetch(game)
    }

    /// Chasing and eating a treat; the window and the treat follow it.
    var treat: TreatGame? { animator.treat }

    func setTreat(_ game: TreatGame?) {
        animator.setTreat(game)
    }

    /// Sitting up begging (while a treat is being held out).
    func setBegging(_ begging: Bool) {
        animator.setBegging(begging, at: Self.clock)
    }

    /// Shows a speech bubble. The mouth moves for the start of the line, as if spoken.
    func say(_ text: String) {
        let duration = min(7, max(2.8, 1.8 + Double(text.count) * 0.05))
        speech = Speech(text: text, duration: duration)
        if transient == nil || transient == .talking {
            play(.talking, for: min(1.8, 0.5 + Double(text.count) * 0.03))
        }
        speechTask?.cancel()
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.speech = nil
        }
    }

    /// Holds a state with no time limit (e.g. thinking while the assistant works) until released.
    func hold(_ state: CharacterState) {
        guard transient == nil || transient == .thinking || transient == .talking else { return }
        transientTask?.cancel()
        transient = state
        apply()
    }

    func release() {
        guard transient == .thinking || transient == .talking else { return }
        transientTask?.cancel()
        transient = nil
        apply()
    }

    /// Mouth movement without a bubble — used when the line appears in the open panel.
    func mouthAlong(_ text: String) {
        guard transient == nil || transient == .talking else { return }
        play(.talking, for: min(1.4, 0.4 + Double(text.count) * 0.025))
    }

    func dismissSpeech() {
        speechTask?.cancel()
        speech = nil
    }

    private func apply() {
        animator.setState(transient ?? baseState, at: Self.clock)
    }
}
