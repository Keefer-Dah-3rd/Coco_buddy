import SwiftUI
import BuddyCharacter

/// First launch: who Coco is, a first task, the optional extras (each explained before
/// any permission prompt), and a few shortcuts. Every step can be skipped.
struct OnboardingView: View {
    let model: AppModel
    let finish: () -> Void
    @State var step = 0
    /// Snapshots pass false for a still Coco, so renders are identical run to run.
    var animated = true
    @State private var firstTask = ""
    @FocusState private var taskFocused: Bool

    private let steps = 4

    var body: some View {
        VStack(spacing: 0) {
            LiveCoco(state: [.idle, .listening, .thinking, .celebrating][step], animated: animated)
                .frame(width: 150, height: 178)
                .padding(.top, 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Space.lg) {
                switch step {
                case 0: meet
                case 1: plan
                case 2: extras
                default: shortcuts
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, Space.xxxl)
            .padding(.top, Space.sm)

            HStack {
                HStack(spacing: Space.xs) {
                    ForEach(0..<steps, id: \.self) { index in
                        Circle().fill(index == step ? Theme.accent : Theme.hairline).frame(width: 6, height: 6)
                    }
                }
                .accessibilityLabel("Step \(step + 1) of \(steps)")
                Spacer()
                if step > 0 {
                    Button("Back") { withAnimation(.snappy) { step -= 1 } }
                        .buttonStyle(KeyButtonStyle(kind: .quiet))
                }
                Button(step == steps - 1 ? "Start" : "Next") { next() }
                    .buttonStyle(KeyButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, Space.xxxl)
            .padding(.top, Space.xl)
            .padding(.bottom, Space.xxl)
        }
        .frame(width: 460, height: 610)
        .background(Theme.paper)
    }

    // MARK: - Steps

    private var meet: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepTitle("Meet \(Buddy.name).")
            StepText("She lives on your desktop and keeps you company while you work. Drag her anywhere — she'll remember the spot. Click her for your day, the focus timer and a chat.")
            StepText("She stays quiet while you focus, and naps when you step away.")
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepTitle("What's one thing for today?")
            StepText("Add it now, or skip — you can always add tasks from her panel.")
            HStack(spacing: Space.sm) {
                Text("+").font(Theme.mono(15, .semibold)).foregroundStyle(Theme.accent)
                TextField("First task", text: $firstTask, prompt: Text("e.g. Draft the homepage ~45m !!").foregroundStyle(Theme.inkTertiary))
                    .textFieldStyle(.plain)
                    .font(.style(.body))
                    .focused($taskFocused)
                    .onSubmit(addTask)
            }
            .padding(.horizontal, Space.md)
            .frame(height: 34)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            ForEach(model.tasks.openToday.prefix(3)) { task in
                HStack(spacing: Space.xs) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 11))
                    Text(task.title).font(.system(size: 12)).foregroundStyle(Theme.ink)
                }
            }
            StepText("Tip: ~30m adds an estimate, ! to !!! sets priority, @today makes it a one-day item.")
        }
        .onAppear { taskFocused = true }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepTitle("Optional extras")
            StepText("All off until you choose them. Everything else works without.")
            Extra(symbol: "waveform", title: "Voice",
                  detail: "Switch on and she reads her lines aloud. To talk to her, press the mic (⌘L) in her panel — macOS asks for microphone access the first time.") {
                Toggle("Speak aloud", isOn: Binding(get: { model.preferences.voiceEnabled }, set: { model.preferences.voiceEnabled = $0 }))
                    .toggleStyle(.switch).controlSize(.small).labelsHidden()
                    .help("\(Buddy.name) speaks her lines aloud")
            }
            Extra(symbol: "calendar", title: "Google Calendar",
                  detail: "Your week, open time and meeting reminders. Events change only when you confirm.") {
                Button("Set up…") { model.openConnections() }.buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            }
            Extra(symbol: "bubble.left", title: "Chat with Claude",
                  detail: "Bring your own Anthropic API key. Your day is shared only when you ask about it.") {
                Button("Add key…") { model.openConnections() }.buttonStyle(KeyButtonStyle(kind: .secondary, compact: true))
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            StepTitle("You're set.")
            ShortcutRow(keys: GlobalShortcut.displayName, text: "Open \(Buddy.name) from any app")
            ShortcutRow(keys: "Click", text: "Open her panel · drag to move her")
            ShortcutRow(keys: "Right-click", text: "Presence, sounds, voice, hide")
            ShortcutRow(keys: "⌘1 ⌘2 ⌘3", text: "Today · Focus · Chat")
            ShortcutRow(keys: "↓ Space ↩", text: "Move through tasks · tick · edit")
            StepText("Her home is the corgi in your menu bar — Settings, Connections and Quit live there.")
        }
    }

    private func addTask() {
        if model.addTask(firstTask) { firstTask = "" }
    }

    private func next() {
        if step == 1, !firstTask.trimmingCharacters(in: .whitespaces).isEmpty { addTask() }
        if step < steps - 1 {
            withAnimation(.snappy) { step += 1 }
        } else {
            finish()
        }
    }
}

// MARK: - Pieces

private struct StepTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.style(.titleLarge)).foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct StepText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.style(.body)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Extra<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 13)).foregroundStyle(Theme.accent).frame(width: 18)
            VStack(alignment: .leading, spacing: Space.xxxs) {
                Text(title).font(.style(.bodyEmphasis)).foregroundStyle(Theme.ink)
                Text(detail).font(.style(.caption)).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            accessory
        }
        .padding(Space.md)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }
}

private struct ShortcutRow: View {
    let keys: String
    let text: String
    var body: some View {
        HStack(spacing: Space.lg) {
            Text(keys)
                .font(.style(.monoKey))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 7)
                .frame(minWidth: 96, minHeight: 22)
                .overlay(RoundedRectangle(cornerRadius: Radius.keycap, style: .continuous).strokeBorder(Theme.hairline))
            Text(text).font(.style(.bodySmall)).foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text): \(spoken)")
    }

    /// Key symbols spelled out for VoiceOver.
    private var spoken: String {
        keys.replacingOccurrences(of: "⌃", with: "Control ")
            .replacingOccurrences(of: "⌥", with: "Option ")
            .replacingOccurrences(of: "⌘", with: "Command ")
            .replacingOccurrences(of: "↓", with: "Down arrow,")
            .replacingOccurrences(of: "↩", with: ", Return")
    }
}

/// A live, animated Coco for windows other than the desktop one.
struct LiveCoco: NSViewRepresentable {
    let state: CharacterState
    var animated = true

    final class Coordinator {
        let model = CharacterModel()
        var loop: CharacterRenderLoop?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CocoLayerView {
        let view = CocoLayerView(frame: NSRect(x: 0, y: 0, width: 150, height: 178))
        guard animated else {
            view.render(Self.stillPose(state), focusProgress: nil)
            return view
        }
        let loop = CharacterRenderLoop(model: context.coordinator.model, view: view)
        context.coordinator.loop = loop
        context.coordinator.model.setBaseState(state)
        DispatchQueue.main.async { loop.setNeedsFrame() }
        return view
    }

    func updateNSView(_ view: CocoLayerView, context: Context) {
        guard animated else {
            view.render(Self.stillPose(state), focusProgress: nil)
            return
        }
        context.coordinator.model.setBaseState(state)
        context.coordinator.loop?.setNeedsFrame()
    }

    /// A settled pose for `state`, clear of blinks and idle fidgets.
    static func stillPose(_ state: CharacterState) -> CharacterPose {
        var animator = CharacterAnimator()
        animator.setState(state, at: 0)
        var t: TimeInterval = 10
        while CharacterAnimator.blinkAmount(at: t) > 0 || !CharacterAnimator.idleEvents(at: t).isEmpty { t += 0.2 }
        return animator.pose(at: t)
    }

    static func dismantleNSView(_ view: CocoLayerView, coordinator: Coordinator) {
        coordinator.loop?.isPaused = true
    }
}
