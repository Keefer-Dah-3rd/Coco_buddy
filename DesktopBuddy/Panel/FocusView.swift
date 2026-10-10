import SwiftUI
import BuddyCore

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
                controls
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(16)
    }

    private var phaseBinding: Binding<FocusPhase> {
        Binding(get: { timer.phase }, set: { focus.prepare($0) })
    }

    // MARK: - Time

    private var timeDisplay: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(AppModel.clock(focus.remaining))
                    .font(.system(size: 62, weight: .light, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(timer.isPaused ? Theme.inkSecondary : Theme.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.25), value: focus.remaining.rounded(.up))
                    .accessibilityLabel("\(Int(focus.remaining.rounded(.up) / 60)) minutes remaining")
                Spacer()
                if !timer.isActive && !timer.isFinished {
                    VStack(spacing: 4) {
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
        HStack(spacing: 10) {
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
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .tint(Theme.ink)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isRunning {
            HStack(spacing: 8) {
                Button { focus.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    .keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }
                    .buttonStyle(KeyButtonStyle(kind: .secondary))
            }
        } else if timer.isPaused {
            HStack(spacing: 8) {
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

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MonoLabel("Until long break")
                Spacer()
                HStack(spacing: 4) {
                    ForEach(0..<model.preferences.focusSettings.sessionsBeforeLongBreak, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(index < timer.focusStreak ? Theme.ink : Theme.hairline)
                            .frame(width: 10, height: 6)
                    }
                }
            }
            HStack(spacing: 8) {
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
                    .font(.system(size: 11))
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

        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(focus.timer.phase == .focus ? "Session complete" : "Break over", color: Theme.accent)

            if let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
                Text("Did “\(task.title)” get done?")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { model.confirmTaskDone(id) } label: { Label("Yes, done", systemImage: "checkmark") }
                        .buttonStyle(KeyButtonStyle(kind: .primary, fillWidth: true))
                    Button("Not yet") { model.dismissCompletionPrompt() }
                        .buttonStyle(KeyButtonStyle(kind: .secondary, fillWidth: true))
                }
            }

            HStack(spacing: 8) {
                Button("\(next == .focus ? "Focus again" : "Take \(next.label.lowercased())") · \(nextMinutes)m") {
                    model.startNextPhase()
                }
                .buttonStyle(KeyButtonStyle(kind: model.completionPrompt == nil ? .primary : .secondary, fillWidth: true))
                Button("Skip") { model.skipNextPhase() }
                    .buttonStyle(KeyButtonStyle(kind: .quiet))
            }
        }
        .padding(12)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.hairline))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
