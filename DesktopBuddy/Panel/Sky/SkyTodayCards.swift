import SwiftUI
import BuddyCore
import BuddyIntegrations

// MARK: - Focus banner (Sunny Side)

/// Sunny Side's focus banner at the top of Today: the countdown in big figures and the one
/// button the timer needs, on navy. It drives the same FocusController as the Focus tab.
struct SkyFocusBanner: View {
    @Bindable var model: AppModel
    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            banner
            headsUp
        }
    }

    private var banner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    (Text(lead).foregroundColor(Sky.accent) + Text(tail).foregroundColor(.white))
                        .font(Sky.text(17, .medium))
                        .tracking(-0.4)
                        .monospacedDigit()
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.linear(duration: 0.2), value: focus.remaining.rounded(.up))
                    Text(subtitle)
                        .skyType(.bodySmall)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                            .skyType(.bodySmall)
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Stop") { focus.stop() }
                        .buttonStyle(.plain)
                        .skyType(.labelButtonCompact)
                        .foregroundStyle(Sky.accentText.opacity(0.8))
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.navy))
        .overlay(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).strokeBorder(Sky.ink, lineWidth: 1))
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
                    .skyType(.bodySmall)
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
    var openChat: () -> Void

    var body: some View {
        let voice = model.voiceIn
        VStack(alignment: .leading, spacing: 6) {
            Text("How can I help?")
                .font(Sky.text(16, .medium))
                .tracking(-0.4)
                .foregroundStyle(Sky.ink)
            SkyActionRow(title: "Make a little plan",
                         help: model.assistant.isReady
                            ? "\(Buddy.name) plans the rest of your day with you in Chat"
                            : "Add a task with the full form (set up Chat for \(Buddy.name) to plan with you)") {
                model.makeLittlePlan()
            }
            // While the mic is open this row says so, and shows what's been heard, right where
            // it was clicked; clicking again stops and hands the words to the review card.
            SkyActionRow(title: voice.isListening
                            ? (voice.transcript.isEmpty ? "Listening… click when you're done" : voice.transcript)
                            : "Let a thought out",
                         symbol: voice.isListening ? "stop.fill" : "arrow.right",
                         help: voice.isListening ? "Stop listening" : "Say what's on your mind — \(Buddy.name) lists it for you",
                         isActive: voice.isListening) {
                model.toggleListening()
            }
            SkyActionRow(title: "Talk it through", help: "Open the chat", action: openChat)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.well))
    }
}

/// A black-rimmed white pill row with an arrow on an indigo disc: the quick actions in Today and
/// the chat's starters. Figma: UI/ActionRow.
struct SkyActionRow: View {
    let title: String
    var symbol = "arrow.right"
    var help: String?
    /// Something this row started is under way (the mic is open): the disc turns the accent
    /// colour, like the add field's mic button, and the title keeps to two lines.
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(Sky.text(12.5))
                    .foregroundStyle(Sky.ink)
                    .multilineTextAlignment(.leading)
                    .lineLimit(isActive ? 2 : nil)
                    .truncationMode(.head)
                Spacer(minLength: 6)
                Image(systemName: symbol)
                    .font(.system(size: isActive ? 10 : 12, weight: .medium))
                    .foregroundStyle(isActive ? Sky.ink : Sky.line)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(isActive ? Sky.accent : Sky.indigo))
            }
            .padding(.leading, 16)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(Capsule(style: .circular).fill(Sky.paper))
            .overlay(Capsule(style: .circular).strokeBorder(.black, lineWidth: 1))
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
