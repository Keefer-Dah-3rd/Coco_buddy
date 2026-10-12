import SwiftUI
import BuddyCore
import BuddyIntegrations

/// Focus timer: pick a phase and task, start, and see the countdown.
struct FocusView: View {
    @Bindable var model: AppModel

    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            KeySegment(selection: phaseBinding, items: [
                .init(.focus, "Focus"),
                .init(.shortBreak, "Short"),
                .init(.longBreak, "Long"),
            ], height: 26)
            .disabled(timer.isActive)
            .opacity(timer.isActive ? 0.5 : 1)

            timeDisplay

            if timer.phase == .focus && !timer.isFinished {
                taskPicker
            }

            if timer.isFinished {
                CompletionCard(model: model)
            } else {
                meetingHeadsUp
                controls
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(Space.xl)
    }

    private var phaseBinding: Binding<FocusPhase> {
        Binding(get: { timer.phase }, set: { focus.prepare($0) })
    }

    // MARK: - Time

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(alignment: .center) {
                Text(AppModel.clock(focus.remaining))
                    .font(.style(.displayCountdown))
                    .monospacedDigit()
                    .foregroundStyle(timer.isPaused ? Theme.inkSecondary : Theme.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.25), value: focus.remaining.rounded(.up))
                    .accessibilityLabel("\(Int(focus.remaining.rounded(.up) / 60)) minutes remaining")
                Spacer()
                if !timer.isActive && !timer.isFinished {
                    VStack(spacing: Space.xxs) {
                        LengthButton(symbol: "plus", help: "5 minutes longer") { focus.adjustLength(by: 5) }
                        LengthButton(symbol: "minus", help: "5 minutes shorter") { focus.adjustLength(by: -5) }
                    }
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.hairline)
                    Rectangle()
                        .fill(timer.phase == .focus ? Theme.accent : Theme.ink)
                        .frame(width: proxy.size.width * focus.progress)
                }
            }
            .frame(height: 3)
            .animation(.linear(duration: 0.3), value: focus.progress)
        }
    }

    private var taskPicker: some View {
        HStack(spacing: Space.md) {
            MonoLabel("On")
            Menu {
                Button("No task — just focus") { focus.selectTask(nil) }
                let open = model.tasks.openToday
                if !open.isEmpty { Divider() }
                ForEach(open) { task in
                    Button(task.title) { focus.selectTask(task.id) }
                }
            } label: {
                Text(model.tasks.task(timer.taskID)?.title ?? "No task — just focus")
                    .font(.style(.body))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .tint(Theme.ink)
        }
        .padding(.horizontal, Space.md)
        .frame(height: 32)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isRunning {
            HStack(spacing: Space.sm) {
                Button { focus.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary))
            }
        } else if timer.isPaused {
            HStack(spacing: Space.sm) {
                Button { focus.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary))
            }
        } else {
            Button { model.startSelectedPhase() } label: {
                Label(timer.phase == .focus ? "Start focus" : "Start break", systemImage: "play.fill")
            }
            .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
            .keyboardShortcut(.space, modifiers: [])
        }
    }

    /// If a meeting would interrupt the session, say so before it starts.
    @ViewBuilder
    private var meetingHeadsUp: some View {
        if model.calendar.isConnected, !timer.isActive,
           let next = model.calendar.schedule.next(after: .now),
           next.start.timeIntervalSinceNow < focus.remaining {
            let minutes = max(1, Int(next.start.timeIntervalSinceNow / 60))
            HStack(spacing: Space.xs) {
                Image(systemName: "calendar").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                Text("“\(BuddyVoice.short(next.title))” starts in \(minutes)m — before this session would end.")
                    .font(.style(.caption))
                    .foregroundStyle(Theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.sm) {
                MonoLabel("Until long break")
                Spacer()
                HStack(spacing: Space.xxs) {
                    ForEach(0..<model.preferences.focusSettings.sessionsBeforeLongBreak, id: \.self) { index in
                        RoundedRectangle(cornerRadius: Radius.bar)
                            .fill(index < timer.focusStreak ? Theme.ink : Theme.hairline)
                            .frame(width: 10, height: 6)
                    }
                }
            }
            HStack(spacing: Space.sm) {
                MonoLabel("During focus")
                Spacer()
                @Bindable var preferences = model.preferences
                KeySegment(selection: $preferences.focusPresentation, items: [
                    .init(.visible, "Full"),
                    .init(.smaller, "Small"),
                    .init(.quiet, "Quiet"),
                ], height: 22)
                .frame(width: 180)
                .help("How \(Buddy.name) looks while you focus: full size, smaller, or dimmed and still")
            }
            if model.notifications.authorization == .denied {
                Text("Notifications are off for Desktop Buddy in System Settings — \(Buddy.name) will still let you know.")
                    .font(.style(.caption))
                    .foregroundStyle(Theme.inkSecondary)
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

        VStack(alignment: .leading, spacing: Space.lg) {
            MonoLabel(focus.timer.phase == .focus ? "Session complete" : "Break over", color: Theme.accent)

            if let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
                Text("Did “\(task.title)” get done?")
                    .font(.style(.bodyEmphasis))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.sm) {
                    Button { model.confirmTaskDone(id) } label: { Label("Yes, done", systemImage: "checkmark") }
                        .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    Button("Not yet") { model.dismissCompletionPrompt() }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, fillWidth: true))
                }
            }

            HStack(spacing: Space.sm) {
                Button("\(next == .focus ? "Focus again" : "Take \(next.label.lowercased())") · \(nextMinutes)m") {
                    model.startNextPhase()
                }
                .buttonStyle(KeyButtonStyle(kind: model.completionPrompt == nil ? .primary : .secondary, fillWidth: true))
                Button("Skip") { model.skipNextPhase() }
                    .buttonStyle(KeyButtonStyle(kind: .quiet))
            }
        }
        .padding(Space.lg)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private struct LengthButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.ink)
                .frame(width: 26, height: 22)
                .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).strokeBorder(Theme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
