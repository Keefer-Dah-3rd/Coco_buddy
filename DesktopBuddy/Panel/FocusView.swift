import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Focus timer: pick a phase and task, start, and see the countdown. While nothing is running,
/// the slider sets the chosen phase's length.
struct FocusView: View {
    @Bindable var model: AppModel

    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }

    var body: some View {
        // Scrolls when the footer doesn't fit, so the header and tabs stay where they are.
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SkySegment(selection: phaseBinding, items: [
                    .init(.focus, "Focus"),
                    .init(.shortBreak, "Short"),
                    .init(.longBreak, "Long"),
                ], height: 30)
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
                    meetingHeadsUp
                    controls
                }

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
        }
        .scrollIndicators(.never)
    }

    private var phaseBinding: Binding<FocusPhase> {
        Binding(get: { timer.phase }, set: { focus.prepare($0) })
    }

    // MARK: - Time

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppModel.clock(focus.remaining))
                .font(Sky.display(46))
                .tracking(-1.2)
                .monospacedDigit()
                .foregroundStyle(timer.isPaused ? Color.white.opacity(0.6) : Color.white)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy(duration: 0.25), value: focus.remaining.rounded(.up))
                .accessibilityLabel("\(Int(focus.remaining.rounded(.up) / 60)) minutes remaining")
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Sky.Radius.card, style: .continuous).fill(Sky.dusk))
    }

    /// The chosen phase's length in minutes, moved in 5-minute steps. Moving it saves the length.
    private var lengthSlider: some View {
        VStack(alignment: .leading, spacing: 2) {
            SkyKicker("Length")
            SkyTimeSlider(title: "Length", minutes: lengthBinding, range: 5...180, step: 5, majorEvery: 4)
        }
    }

    private var lengthBinding: Binding<Int> {
        Binding(
            get: { model.preferences.focusSettings.minutes(for: timer.phase) },
            set: { minutes in
                focus.adjustLength(by: minutes - model.preferences.focusSettings.minutes(for: timer.phase))
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
                Text(model.tasks.task(timer.taskID)?.title ?? "No task — just focus")
                    .font(Sky.text(13, .medium))
                    .foregroundStyle(Sky.ink)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .tint(Sky.ink)
            Spacer(minLength: 0)
        }
        .skyField()
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isRunning {
            HStack(spacing: 8) {
                Button { focus.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(SkyButtonStyle(kind: .outline))
            }
        } else if timer.isPaused {
            HStack(spacing: 8) {
                Button { focus.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(SkyButtonStyle(kind: .outline))
            }
        } else {
            Button { model.startSelectedPhase() } label: {
                Label(timer.phase == .focus ? "Start focus" : "Start break", systemImage: "play.fill")
            }
            .buttonStyle(SkyButtonStyle(kind: .accent, fillWidth: true))
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    /// If a meeting would interrupt the session, say so before it starts.
    @ViewBuilder
    private var meetingHeadsUp: some View {
        if model.agenda.isConnected, !timer.isActive,
           let next = model.agenda.schedule.next(after: .now),
           next.start.timeIntervalSinceNow < focus.remaining {
            let minutes = max(1, Int(next.start.timeIntervalSinceNow / 60))
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Sky.accentText)
                Text("“\(BuddyVoice.short(next.title))” starts in \(minutes)m — before this session would end.")
                    .font(Sky.text(11))
                    .foregroundStyle(Sky.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                SkyKicker("Until long break")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<model.preferences.focusSettings.sessionsBeforeLongBreak, id: \.self) { index in
                        Capsule()
                            .fill(index < timer.focusStreak ? Sky.accent : Sky.line)
                            .frame(width: 12, height: 6)
                    }
                }
            }
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
                Text("Notifications are off for Desktop Buddy in System Settings — \(Buddy.name) will still let you know.")
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
            SkyKicker(focus.timer.phase == .focus ? "Session complete" : "Break over", color: Sky.accentText)

            if let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
                Text("Did “\(task.title)” get done?")
                    .font(Sky.text(14, .semibold))
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
        .skyCard(radius: Sky.Radius.card)
    }
}
