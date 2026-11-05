import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Focus timer: pick a length and task, start, and see the countdown. While nothing is running,
/// the quick picks, the clock (click it and type) and the slider all set the focus length.
/// Breaks come from the end-of-session card, voice and chat.
struct FocusView: View {
    @Bindable var model: AppModel

    /// Quick lengths for a focus session; anything else can be typed on the clock.
    static let quickLengths = [15, 25, 45, 60, 90]

    @State private var typingLength = false
    @State private var lengthDraft = ""
    @State private var refusedTries = 0
    @State private var hoveringClock = false
    @State private var iBeamPushed = false
    @FocusState private var lengthFieldFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }

    var body: some View {
        // Scrolls when the footer doesn't fit, so the header and tabs stay where they are.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SkySegment(selection: quickLengthBinding,
                           items: Self.quickLengths.map { .init($0, DurationText.short($0)) },
                           height: 30)
                .disabled(timer.isActive)
                .opacity(timer.isActive ? 0.5 : 1)

                timeDisplay

                if !timer.isActive && !timer.isFinished {
                    lengthSlider
                }

                if timer.phase == .focus && !timer.isFinished {
                    taskPicker
                }

                if timer.isFinished {
                    CompletionCard(model: model)
                } else {
                    MeetingHeadsUp(model: model)
                    controls
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
        .onChange(of: canTypeLength) { _, can in
            if !can { endTypingLength() }  // a session started some other way (voice, chat)
        }
        .onChange(of: lengthFieldFocused) { _, focused in
            if focused {
                beginTypingLength()  // tabbed onto the clock
            } else {
                finishTypingLength(fromReturn: false)  // Tab or a click elsewhere keeps what was typed
            }
        }
        .onDisappear { finishTypingLength(fromReturn: false) }
    }

    /// The pick that matches the current focus session's length; none for a typed length or a break.
    private var quickLengthBinding: Binding<Int> {
        Binding(
            get: { timer.phase == .focus ? Int((timer.duration / 60).rounded()) : -1 },
            set: { minutes in
                endTypingLength()
                focus.setFocusLength(minutes)
            }
        )
    }

    // MARK: - Time

    /// The clock can be clicked and typed into while no session is running or waiting.
    private var canTypeLength: Bool { !timer.isActive && !timer.isFinished }

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The field is always there, hidden under the clock until it's clicked, so focus
            // never waits for it to be made.
            ZStack(alignment: .leading) {
                lengthField
                if !typingLength { clock }
            }
            if typingLength {
                // Takes the empty bar's place, so the card doesn't change height.
                Text(lengthHint)
                    .font(Sky.text(11, .medium))
                    .foregroundStyle(lengthHintIsWarning ? Sky.accent : Color.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: 5, alignment: .leading)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Sky.accent)
                            .frame(width: proxy.size.width * focus.progress)
                    }
                }
                .frame(height: 5)
                .animation(.linear(duration: 0.3), value: focus.progress)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .skyCard(fill: Sky.navy, rim: Sky.ink, style: .continuous)
    }

    private var clock: some View {
        Text(DurationText.clock(focus.remaining))
            .skyType(.displayCountdown)
            .monospacedDigit()
            .foregroundStyle(timer.isPaused ? Color.white.opacity(0.6) : Color.white)
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy(duration: 0.25), value: focus.remaining.rounded(.up))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { lengthFieldShape(lit: hoveringClock && canTypeLength, outlined: false) }
            .contentShape(Rectangle())
            .onTapGesture { beginTypingLength() }
            .onHover { inside in
                hoveringClock = inside
                if inside, canTypeLength, !iBeamPushed {
                    NSCursor.iBeam.push()
                    iBeamPushed = true
                } else if !inside, iBeamPushed {
                    NSCursor.pop()
                    iBeamPushed = false
                }
            }
            .help(canTypeLength ? "Click to type a length, like 45 or 1h 30m" : "")
            .accessibilityLabel("\(Int(focus.remaining.rounded(.up) / 60)) minutes remaining")
            .accessibilityAddTraits(canTypeLength ? .isButton : [])
            .accessibilityHint(canTypeLength ? "Type a length" : "")
            .accessibilityAction { beginTypingLength() }
    }

    /// The clock as a text field: same type and place, with the time selected so typing replaces it.
    private var lengthField: some View {
        // Hidden, it holds the clock's time, so Tab onto it selects the right text.
        TextField("Length", text: Binding(get: { typingLength ? lengthDraft : DurationText.clock(focus.remaining) },
                                          set: { lengthDraft = $0 }),
                  prompt: Text("45"))
            .textFieldStyle(.plain)
            .skyType(.displayCountdown)
            .monospacedDigit()
            .foregroundStyle(Color.white)
            .environment(\.colorScheme, .dark)  // a white caret and a selection that reads on navy
            .focused($lengthFieldFocused)
            .onSubmit { finishTypingLength(fromReturn: true) }
            .onExitCommand { cancelTypingLength() }
            .onKeyPress(.escape) {
                cancelTypingLength()
                return .handled
            }
            .modifier(Shake(tries: CGFloat(refusedTries)))
            .background { lengthFieldShape(lit: true, outlined: true) }
            .opacity(typingLength ? 1 : 0)
            .allowsHitTesting(typingLength)
            .disabled(!canTypeLength)
            .accessibilityHidden(!typingLength)
            .accessibilityLabel("Length")
            .accessibilityHint("Type minutes, like 45, or 1h 30m, then press Return")
    }

    /// Behind the clock: lit on hover, and an outlined field while typing. Drawn outside the
    /// clock's frame so nothing moves.
    private func lengthFieldShape(lit: Bool, outlined: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(lit ? (outlined ? 0.1 : 0.06) : 0))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Sky.accent.opacity(outlined ? 1 : 0), lineWidth: 1.5))
            .padding(.horizontal, -8)
            .padding(.vertical, -3)
            .animation(Sky.Motion.quick, value: lit)
    }

    private var typedMinutes: Int? { TypedLength.minutes(from: lengthDraft) }

    private var lengthHint: String {
        guard let minutes = typedMinutes else { return "Type minutes, like 45 or 1h 30m" }
        let range = FocusSettings.minuteRange
        let length = DurationText.short(min(max(minutes, range.lowerBound), range.upperBound))
        let note = minutes > range.upperBound ? ", the longest" : ""
        return "Return sets \(length)\(note) · Esc cancels"
    }

    private var lengthHintIsWarning: Bool { refusedTries > 0 && typedMinutes == nil }

    private func beginTypingLength() {
        guard canTypeLength, !typingLength else { return }
        lengthDraft = DurationText.clock(focus.remaining)
        refusedTries = 0
        typingLength = true
        // AppKit selects the field's text as it takes focus, so typing replaces the time.
        lengthFieldFocused = true
    }

    /// Hides the field and lets go of the keyboard, so Space starts the session again.
    private func endTypingLength() {
        typingLength = false
        lengthFieldFocused = false
    }

    /// Return keeps the field open on something that isn't a length (with a shake); leaving the
    /// field any other way drops it.
    private func finishTypingLength(fromReturn: Bool) {
        guard typingLength else { return }
        if let minutes = typedMinutes {
            endTypingLength()
            focus.setFocusLength(minutes)
        } else if fromReturn {
            if reduceMotion {
                refusedTries += 1
            } else {
                withAnimation(.linear(duration: 0.32)) { refusedTries += 1 }
            }
        } else {
            endTypingLength()
        }
    }

    private func cancelTypingLength() {
        endTypingLength()
    }

    /// The focus length in minutes, moved in 5-minute steps. Moving it saves the length.
    private var lengthSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            SkyKicker("Length")
            SkyTimeSlider(title: "Length", minutes: lengthBinding, range: 5...180, step: 5, majorEvery: 4)
        }
    }

    private var lengthBinding: Binding<Int> {
        Binding(
            get: { model.preferences.focusSettings.minutes(for: .focus) },
            set: { minutes in
                endTypingLength()
                focus.setFocusLength(minutes)
            }
        )
    }

    private var taskPicker: some View {
        HStack(spacing: 10) {
            SkyKicker("On")
            Menu {
                Button("No task — just focus") { focus.selectTask(nil) }
                let open = model.tasks.openToday
                if !open.isEmpty { Divider() }
                ForEach(open) { task in
                    Button(task.title) { focus.selectTask(task.id) }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(model.tasks.task(timer.taskID)?.title ?? "No task — just focus")
                        .font(Sky.text(13, .medium))
                        .foregroundStyle(Sky.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(Sky.ink)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            Spacer(minLength: 0)
        }
        .skyField(rim: nil)
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isRunning {
            HStack(spacing: 8) {
                Button("Pause") { focus.pause() }
                    .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(SkyButtonStyle(kind: .outline))
            }
        } else if timer.isPaused {
            HStack(spacing: 8) {
                Button("Resume") { focus.resume() }
                    .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(SkyButtonStyle(kind: .outline))
            }
        } else {
            Button(timer.phase == .focus ? "Start focus" : "Start break") {
                finishTypingLength(fromReturn: false)  // starts with what was typed, if it's a length
                model.startSelectedPhase()
            }
            .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
            // Not while typing, where Space belongs to the field ("1h 30m").
            .keyboardShortcut(typingLength ? nil : KeyboardShortcut(.space, modifiers: []))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SkyKicker("During focus")
                Spacer()
                @Bindable var preferences = model.preferences
                SkySegment(selection: $preferences.focusPresentation, items: [
                    .init(.visible, "Full"),
                    .init(.smaller, "Small"),
                    .init(.quiet, "Quiet"),
                ], height: 26)
                .frame(width: 180)
                .help("How \(Buddy.name) looks while you focus: full size, smaller, or dimmed and still")
            }
            if model.notifications.authorization == .denied {
                Text("Notifications are off for Coco in System Settings — she'll still let you know.")
                    .font(Sky.text(11))
                    .foregroundStyle(Sky.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Shown when a session ends: ask about the task, then offer the next phase.
private struct CompletionCard: View {
    let model: AppModel

    var body: some View {
        let focus = model.focus
        let next = focus.suggestedNextPhase
        let nextMinutes = model.preferences.focusSettings.minutes(for: next)

        VStack(alignment: .leading, spacing: 12) {
            SkyKicker(focus.timer.phase == .focus ? "Session complete" : "Break over", tone: .ink)

            if let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
                Text("Did “\(task.title)” get done?")
                    .skyType(.titleEmphasis)
                    .foregroundStyle(Sky.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { model.confirmTaskDone(id) } label: { Label("Yes, done", systemImage: "checkmark") }
                        .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
                    Button("Not yet") { model.dismissCompletionPrompt() }
                        .buttonStyle(SkyButtonStyle(kind: .outline, fillWidth: true))
                }
            }

            HStack(spacing: 8) {
                Button("\(next == .focus ? "Focus again" : "Take \(next.label.lowercased())") · \(nextMinutes)m") {
                    model.startNextPhase()
                }
                .buttonStyle(SkyButtonStyle(kind: model.completionPrompt == nil ? .accent : .outline, fillWidth: true))
                Button("Skip") { model.skipNextPhase() }
                    .buttonStyle(SkyButtonStyle(kind: .quiet))
            }
        }
        .padding(16)
        .skyCard(rim: Sky.accentSoft, style: .continuous)
    }
}

/// A quick side-to-side shake each time `tries` goes up: "that isn't a length".
private struct Shake: GeometryEffect {
    var tries: CGFloat
    var animatableData: CGFloat {
        get { tries }
        set { tries = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 6 * sin(tries * .pi * 4), y: 0))
    }
}
