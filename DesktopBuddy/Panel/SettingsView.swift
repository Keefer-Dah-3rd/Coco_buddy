import ServiceManagement
import SwiftUI
import BuddyCore

/// Everything adjustable in one place, grouped by what it affects.
struct SettingsView: View {
    @Bindable var model: AppModel
    /// The window's height; snapshots pass a taller one to show every section.
    var height: CGFloat = 680
    @State private var confirmingErase = false
    @State private var erasing = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginNote: String?

    var body: some View {
        @Bindable var preferences = model.preferences
        @Bindable var calendar = model.calendar

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MonoLabel("Settings", color: Theme.ink)

                Section("\(Buddy.name)") {
                    Row("Presence") {
                        KeySegment(selection: $preferences.presence, items: [
                            .init(.interactive, "Interactive"), .init(.compact, "Compact"),
                        ], height: 22).frame(width: 220)
                    }
                    Caption("Interactive: full size, follows your cursor, short acknowledgements. Compact: smaller and only speaks up for important things.")
                    Row("During focus") {
                        KeySegment(selection: $preferences.focusPresentation, items: [
                            .init(.visible, "Full"), .init(.smaller, "Small"), .init(.quiet, "Quiet"),
                        ], height: 22).frame(width: 220)
                    }
                    ToggleRow("Show \(Buddy.name) on the desktop", isOn: $preferences.isBuddyVisible)
                    ToggleRow("Keep \(Buddy.name) above other windows", isOn: $preferences.alwaysOnTop)
                    ToggleRow("Open \(Buddy.name) from any app with \(GlobalShortcut.displayName)", isOn: $preferences.globalShortcutEnabled)
                    if model.shortcutUnavailable {
                        Caption("Another app is already using \(GlobalShortcut.displayName), so it isn't active. Quit that app or change its shortcut, then switch this off and on.")
                    }
                    ToggleRow("Open at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                    if let loginNote { Caption(loginNote) }
                }

                Section("Sound & voice") {
                    ToggleRow("Mute all sounds", isOn: $preferences.soundsMuted)
                    ToggleRow("\(Buddy.name) barks at big moments", isOn: $preferences.barksEnabled)
                        .disabled(preferences.soundsMuted)
                    ToggleRow("\(Buddy.name) speaks her lines aloud", isOn: $preferences.voiceEnabled)
                        .disabled(preferences.soundsMuted)
                    Caption("Voice input asks for microphone and speech-recognition access the first time you press the mic. Recognition runs on this Mac when your language supports it.")
                }

                Section("Focus") {
                    MinutesRow("Focus length", value: focusBinding(.focus))
                    MinutesRow("Short break", value: focusBinding(.shortBreak))
                    MinutesRow("Long break", value: focusBinding(.longBreak))
                    Row("Long break after") {
                        Stepper("\(preferences.focusSettings.sessionsBeforeLongBreak) sessions",
                                value: Binding(get: { preferences.focusSettings.sessionsBeforeLongBreak },
                                               set: { preferences.focusSettings.sessionsBeforeLongBreak = min(8, max(2, $0)) }),
                                in: 2...8)
                        .font(.system(size: 12))
                    }
                }

                Section("Your day") {
                    Row("Workday ends at") {
                        Stepper(hourLabel(preferences.workdayEndHour), value: $preferences.workdayEndHour, in: 12...23)
                            .font(.system(size: 12))
                    }
                    Caption("Used to find free stretches for focused work.")
                    Row("Meeting reminders") {
                        KeySegment(selection: $calendar.reminderMinutes, items: [
                            .init(0, "Off"), .init(5, "5m"), .init(10, "10m"), .init(15, "15m"),
                        ], height: 22).frame(width: 220)
                    }
                    HStack {
                        Spacer()
                        Button("Connections…") { model.openConnections() }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                    }
                }

                Section("Privacy & data") {
                    Caption("Everything \(Buddy.name) keeps stays on this Mac: tasks, focus history and timer in the app's container; sign-ins and keys in your Keychain. Chats live in memory only. Calendar and task details go to Anthropic only when you ask the chat something that needs them.")
                    HStack {
                        Button("Show welcome again") { model.showOnboarding() }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                        Spacer()
                        Button(erasing ? "Deleting…" : "Delete all my data…") { confirmingErase = true }
                            .buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
                            .disabled(erasing)
                    }
                }

                Text("Desktop Buddy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.inkTertiary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 24)
        }
        .frame(width: 540, height: height)
        .background(Theme.paper)
        .alert("Delete all of \(Buddy.name)'s data?", isPresented: $confirmingErase) {
            Button("Delete everything", role: .destructive) {
                erasing = true
                Task {
                    await model.eraseAllData()
                    erasing = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your tasks, focus history, timer, calendar sign-in and cache, Claude key, chat and settings. Google access is revoked. This can't be undone.")
        }
    }

    private func focusBinding(_ phase: FocusPhase) -> Binding<Int> {
        Binding(get: { model.preferences.focusSettings.minutes(for: phase) },
                set: { model.preferences.focusSettings.setMinutes($0, for: phase) })
    }

    private func hourLabel(_ hour: Int) -> String {
        let date = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginNote = SMAppService.mainApp.status == .requiresApproval
                ? "macOS needs your OK: System Settings › General › Login Items." : nil
        } catch {
            loginNote = "Couldn't change the login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Building blocks

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct Row<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack {
            MonoLabel(label).accessibilityHidden(true)
            Spacer()
            content
        }
        .frame(minHeight: 24)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

private struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.ink)
                .accessibilityHidden(true)
            Spacer()
            Toggle(label, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

private struct MinutesRow: View {
    let label: String
    @Binding var value: Int

    init(_ label: String, value: Binding<Int>) {
        self.label = label
        _value = value
    }

    var body: some View {
        Row(label) {
            Stepper("\(value) min", value: $value, in: FocusSettings.minuteRange, step: 5)
                .font(.system(size: 12))
                .accessibilityLabel(label)
                .accessibilityValue("\(value) minutes")
        }
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
