#if DEBUG
import SwiftUI
import BuddyCore
import BuddyIntegrations

// EXPERIMENT — the focus timer as an editorial page: the countdown set like a display
// numeral, choices as underlined words, the welcome screen's circle key to start.
// Same FocusController as the real Focus tab.

struct EOFocusView: View {
    @Bindable var model: AppModel

    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                EOKicker(EOSection.focus.kicker)
                    .padding(.bottom, EO.Space.sm)
                    .eoEntrance(0)

                EOTextTabs(selection: phaseBinding, options: [(.focus, "Focus"), (.shortBreak, "Short break"), (.longBreak, "Long break")],
                           size: 17, spacing: 18)
                    .disabled(timer.isActive)
                    .opacity(timer.isActive ? 0.4 : 1)
                    .eoEntrance(1)

                countdown
                    .padding(.top, EO.Space.md)
                    .eoEntrance(2)

                if timer.isFinished {
                    EOFocusComplete(model: model)
                        .padding(.top, EO.Space.lg)
                        .eoEntrance(3)
                } else {
                    if timer.phase == .focus { taskPicker.padding(.top, EO.Space.lg).eoEntrance(3) }
                    meetingHeadsUp.padding(.top, EO.Space.sm)
                    controls.padding(.top, EO.Space.lg).eoEntrance(4)
                }

                EOPullQuote(text: model.buddyLine)
                    .padding(.top, EO.Space.xl)
                    .eoEntrance(5)

                footer
                    .padding(.top, EO.Space.xl)
                    .eoEntrance(6)
            }
            .padding(.horizontal, EO.Space.page)
            .padding(.vertical, EO.Space.lg)
        }
        .scrollIndicators(.never)
    }

    private var phaseBinding: Binding<FocusPhase> {
        Binding(get: { timer.phase }, set: { focus.prepare($0) })
    }

    // MARK: - Countdown

    private var countdown: some View {
        VStack(alignment: .leading, spacing: EO.Space.sm) {
            HStack(alignment: .lastTextBaseline) {
                Text(AppModel.clock(focus.remaining))
                    .font(EO.font(112, .light))
                    .tracking(EO.Tracking.tighter(112))
                    .monospacedDigit()
                    .foregroundStyle(timer.isPaused ? EO.Ink.secondary : EO.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(EO.Motion.quick, value: focus.remaining.rounded(.up))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("\(Int(focus.remaining.rounded(.up) / 60)) minutes remaining")
                Spacer(minLength: 0)
                if !timer.isActive && !timer.isFinished {
                    VStack(spacing: 2) {
                        lengthKey("+", help: "5 minutes longer") { focus.adjustLength(by: 5) }
                        lengthKey("−", help: "5 minutes shorter") { focus.adjustLength(by: -5) }
                    }
                }
            }
            // The progress rule: hairline track, orange for focus, ink for breaks.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(EO.Ink.rule).frame(height: 1)
                    Rectangle()
                        .fill(timer.phase == .focus ? EO.orange : EO.ink)
                        .frame(width: proxy.size.width * focus.progress, height: 3)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 3)
            .animation(.linear(duration: 0.3), value: focus.progress)
            HStack {
                EOKicker(timer.isRunning ? (timer.phase == .focus ? "In session" : "On a break")
                         : timer.isPaused ? "Paused" : timer.isFinished ? "Finished" : "Ready",
                         color: timer.isRunning ? EO.orange : EO.Ink.secondary, size: 10)
                    .eoPulse(timer.isRunning)
                Spacer()
                EOKicker("\(model.preferences.focusSettings.minutes(for: timer.phase))m \(timer.phase.label)",
                         color: EO.Ink.secondary, size: 10, weight: .medium)
            }
        }
    }

    private func lengthKey(_ glyph: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(glyph).font(EO.font(EO.Size.title, .light)).frame(width: 30, height: 30) }
            .buttonStyle(.plain)
            .foregroundStyle(EO.Ink.secondary)
            .help(help)
            .accessibilityLabel(help)
    }

    // MARK: - Task and controls

    private var taskPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            EOKicker("On", color: EO.Ink.secondary, size: 10)
            Menu {
                Button("No task — just focus") { focus.selectTask(nil) }
                let open = model.tasks.openToday
                if !open.isEmpty { Divider() }
                ForEach(open) { task in
                    Button(task.title) { focus.selectTask(task.id) }
                }
            } label: {
                Text(model.tasks.task(timer.taskID)?.title ?? "No task — just focus")
                    .font(EO.font(EO.Size.item, .medium, italic: timer.taskID == nil))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .tint(EO.ink)
            .disabled(timer.isActive)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { EORule() }
        }
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: EO.Space.md) {
            if timer.isRunning {
                Button { focus.pause() } label: { Image(systemName: "pause").font(.system(size: 18, weight: .light)) }
                    .buttonStyle(EOCircleButtonStyle(filled: true))
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel("Pause")
                Button("Stop") { focus.stop() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet))
            } else if timer.isPaused {
                Button { focus.resume() } label: { Image(systemName: "play").font(.system(size: 18, weight: .light)) }
                    .buttonStyle(EOCircleButtonStyle())
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel("Resume")
                Button("Stop") { focus.stop() }
                    .buttonStyle(EOUnderlineButtonStyle(kind: .quiet))
            } else {
                Button { model.startSelectedPhase() } label: { Text("→") }
                    .buttonStyle(EOCircleButtonStyle())
                    .keyboardShortcut(.space, modifiers: [])
                    .accessibilityLabel(timer.phase == .focus ? "Start focus" : "Start break")
                VStack(alignment: .leading, spacing: 4) {
                    Text(timer.phase == .focus ? "Start focus" : "Start break")
                        .font(EO.font(EO.Size.lead, .medium))
                        .foregroundStyle(EO.ink)
                    EOKicker("Space", color: EO.Ink.muted, size: 9)
                }
            }
        }
        .animation(EO.Motion.hover, value: timer.isRunning)
        .animation(EO.Motion.hover, value: timer.isPaused)
    }

    /// If a meeting would interrupt the session, say so before it starts (merged calendars).
    @ViewBuilder
    private var meetingHeadsUp: some View {
        if model.agenda.isConnected, !timer.isActive,
           let next = model.agenda.schedule.next(after: .now),
           next.start.timeIntervalSinceNow < focus.remaining {
            let minutes = max(1, Int(next.start.timeIntervalSinceNow / 60))
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                EOKicker("Heads up", size: 9)
                Text("“\(BuddyVoice.short(next.title))” starts in \(minutes)m — before this session would end.")
                    .font(EO.font(14, .light, italic: true))
                    .foregroundStyle(EO.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: EO.Space.md) {
            EORule()
            HStack {
                EOKicker("Until long break", color: EO.Ink.secondary, size: 10)
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<model.preferences.focusSettings.sessionsBeforeLongBreak, id: \.self) { index in
                        Circle()
                            .fill(index < timer.focusStreak ? EO.orange : Color.clear)
                            .overlay(Circle().strokeBorder(index < timer.focusStreak ? EO.orange : EO.ink, lineWidth: 1))
                            .frame(width: 10, height: 10)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                EOKicker("While you focus, \(Buddy.name)…", color: EO.Ink.secondary, size: 10)
                EOTextTabs(selection: Binding(get: { model.preferences.focusPresentation },
                                              set: { model.preferences.focusPresentation = $0 }),
                           options: [(.visible, "Stays"), (.smaller, "Shrinks"), (.quiet, "Dims")], size: 16, spacing: 16)
                    .help("How \(Buddy.name) looks while you focus: full size, smaller, or dimmed and still")
            }
            if model.notifications.authorization == .denied {
                Text("Notifications are off for Desktop Buddy in System Settings — \(Buddy.name) will still let you know.")
                    .font(EO.font(12, .light, italic: true))
                    .foregroundStyle(EO.Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Session over: ask about the task (never assume), then offer the next phase.
private struct EOFocusComplete: View {
    let model: AppModel

    var body: some View {
        let focus = model.focus
        let next = focus.suggestedNextPhase
        let nextMinutes = model.preferences.focusSettings.minutes(for: next)
        VStack(alignment: .leading, spacing: EO.Space.md) {
            EOKicker(focus.timer.phase == .focus ? "Session complete" : "Break over")
            if let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
                EODisplay([.plain("Did it"), .accent("get done?")], size: EO.Size.headline)
                Text("“\(task.title)”")
                    .font(EO.font(EO.Size.lead, .light, italic: true))
                    .foregroundStyle(EO.ink)
                HStack(spacing: EO.Space.md) {
                    Button("Yes, done") { model.confirmTaskDone(id) }
                        .buttonStyle(EOUnderlineButtonStyle(kind: .accent))
                    Button("Not yet") { model.dismissCompletionPrompt() }
                        .buttonStyle(EOUnderlineButtonStyle(kind: .quiet))
                }
            }
            Button("\(next == .focus ? "Focus again" : "Take a \(next.label.lowercased())") · \(nextMinutes)m") {
                model.startNextPhase()
            }
            .buttonStyle(EOOutlineButtonStyle())
            Button("Skip") { model.skipNextPhase() }
                .buttonStyle(EOLinkButtonStyle(color: EO.Ink.secondary, arrow: ""))
        }
    }
}
#endif
