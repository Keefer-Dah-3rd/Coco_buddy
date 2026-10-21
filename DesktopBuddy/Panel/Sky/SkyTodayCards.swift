import SwiftUI
import BuddyCore
import BuddyIntegrations

// MARK: - Little wins (Coco Nook)

/// Nook's "1/3 little wins" card in Blue Skies' look: the done count, a thin orange meter and a
/// short note. It leads Today's count line.
struct SkyWinsCard: View {
    let done: Int
    let total: Int

    var body: some View {
        let share: CGFloat = total == 0 ? 0 : CGFloat(done) / CGFloat(total)
        HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(done)")
                    .font(Sky.display(28))
                    .foregroundStyle(Sky.ink)
                    .contentTransition(.numericText())
                Text("/\(total)")
                    .font(Sky.text(14))
                    .foregroundStyle(Sky.muted)
                    .contentTransition(.numericText())
            }
            .monospacedDigit()
            Text("little wins")
                .font(Sky.text(10.5))
                .foregroundStyle(Sky.muted)
                .fixedSize()
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Sky.line)
                    Capsule().fill(Sky.accent)
                        .frame(width: max(share > 0 ? 6 : 0, proxy.size.width * share))
                }
                .frame(height: 6)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 20)
            Text(note)
                .font(Sky.text(10.5))
                .foregroundStyle(Sky.muted)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .skyCard(radius: Sky.Radius.card)
        .animation(Sky.Motion.enter, value: done)
        .animation(Sky.Motion.enter, value: total)
    }

    private var note: String {
        if total == 0 { return "Room for anything." }
        if done == 0 { return "A gentle start." }
        if done == total { return "All done. Lovely." }
        return done * 2 < total ? "Growing nicely." : "Look at you go."
    }
}

// MARK: - Focus banner (Sunny Side)

/// Sunny Side's focus banner at the top of Today: the countdown in big figures and the one
/// button the timer needs. It drives the same FocusController as the Focus tab.
struct SkyFocusBanner: View {
    @Bindable var model: AppModel
    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }
    /// The lighter brown of the banner's icon disc.
    private static let disc = Color(hex: 0x4D3C37)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            headsUp
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: timer.phase == .focus ? "sun.max" : "cup.and.saucer")
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Self.disc))
                VStack(alignment: .leading, spacing: 3) {
                    (Text(lead).foregroundColor(Sky.accent) + Text(tail).foregroundColor(.white))
                        .font(Sky.text(17, .medium))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.linear(duration: 0.2), value: focus.remaining.rounded(.up))
                    Text(subtitle)
                        .font(Sky.text(10.5))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                // No space-bar shortcut here: Today's add field needs the space key.
                Button(action: primary) { Text(primaryTitle) }
                    .buttonStyle(SkyButtonStyle(kind: .accent))
                    .help(primaryHelp)
            }
            if timer.isActive {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.14))
                        Capsule().fill(Sky.accent).frame(width: proxy.size.width * focus.progress)
                    }
                }
                .frame(height: 3)
                .animation(.linear(duration: 0.3), value: focus.progress)
                HStack {
                    if let task = model.tasks.task(timer.taskID) {
                        Text("On “\(BuddyVoice.short(task.title, limit: 26))”")
                            .font(Sky.text(10.5))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button("Stop") { focus.stop() }
                        .buttonStyle(.plain)
                        .font(Sky.text(10.5, .medium))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.dusk))
        .animation(Sky.Motion.enter, value: timer.isActive)
        .animation(Sky.Motion.enter, value: timer.isFinished)
    }

    // MARK: Words

    private var minutesSetting: Int { model.preferences.focusSettings.minutes(for: timer.phase) }

    private var lead: String {
        if timer.isActive || timer.isFinished { return AppModel.clock(focus.remaining) }
        return "\(minutesSetting) min"
    }

    private var tail: String {
        timer.phase == .focus ? " of calm" : " of rest"
    }

    private var subtitle: String {
        if timer.isFinished { return timer.phase == .focus ? "A little win. Take a breather." : "Break's over — ready when you are." }
        if timer.isPaused { return "Paused. Pick it back up whenever." }
        if timer.isRunning { return timer.phase == .focus ? "One thing at a time. You've got this." : "A proper little break." }
        if let task = model.tasks.task(timer.taskID) { return "On “\(BuddyVoice.short(task.title, limit: 24))”" }
        return "A little space for your best work."
    }

    private var primaryTitle: String {
        if timer.isFinished { return focus.suggestedNextPhase == .focus ? "Again" : "Break" }
        if timer.isRunning { return "Pause" }
        if timer.isPaused { return "Resume" }
        return "Let's go"
    }

    private var primaryHelp: String {
        timer.isFinished ? "Start the next session" : timer.isRunning ? "Pause" : "Start focus"
    }

    private func primary() {
        if timer.isFinished { model.startNextPhase() }
        else if timer.isRunning { focus.pause() }
        else if timer.isPaused { focus.resume() }
        else { model.startSelectedPhase() }
    }

    // MARK: Under the banner: session over (ask, never assume), or a meeting heads-up

    @ViewBuilder
    private var headsUp: some View {
        if timer.isFinished, let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
            HStack(spacing: 8) {
                Text("Did “\(BuddyVoice.short(task.title, limit: 22))” get done?")
                    .font(Sky.text(12))
                    .foregroundStyle(Sky.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Button("Yes, done") { model.confirmTaskDone(id) }
                    .buttonStyle(SkyButtonStyle(kind: .accent, compact: true))
                Button("Not yet") { model.dismissCompletionPrompt() }
                    .buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
            }
            .padding(.top, 10)
            .transition(.opacity)
        } else if model.agenda.isConnected, !timer.isActive, let next = model.agenda.schedule.next(after: .now),
                  next.start.timeIntervalSinceNow < focus.remaining {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10))
                    .foregroundStyle(Sky.accentText)
                Text("“\(BuddyVoice.short(next.title))” starts in \(max(1, Int(next.start.timeIntervalSinceNow / 60)))m — before this session would end.")
                    .font(Sky.text(10.5))
                    .foregroundStyle(Sky.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Quick actions (Kindred)

/// Kindred's "How can I help?" in Blue Skies' look: a soft panel of quick actions.
struct SkyHelpRows: View {
    let model: AppModel
    var makePlan: () -> Void
    var openChat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How can I help?")
                .font(Sky.display(16))
                .tracking(-0.4)
                .foregroundStyle(Sky.ink)
                .padding(.horizontal, 6)
                .padding(.top, 4)
                .padding(.bottom, 4)
            SkyActionRow(title: "Make a little plan", help: "Jump to the add field", action: makePlan)
            SkyActionRow(title: "Let a thought out", help: "Say what's on your mind — Coco lists it for you") {
                model.toggleListening()
            }
            SkyActionRow(title: "Talk it through", help: "Open the chat", action: openChat)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.well))
    }
}

/// A white pill row with an orange arrow: the quick actions in Today and the chat's starters.
struct SkyActionRow: View {
    let title: String
    var symbol = "arrow.right"
    var help: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Sky.text(12.5))
                    .foregroundStyle(Sky.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Sky.ink)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Sky.accentPale))
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Capsule().fill(Sky.paper))
            .contentShape(Capsule())
        }
        .buttonStyle(SkyPressStyle())
        .help(help ?? "")
    }
}

/// A small squish when a row is pressed.
struct SkyPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Sky.Motion.quick, value: configuration.isPressed)
    }
}
