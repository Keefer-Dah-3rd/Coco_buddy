import SwiftUI
import BuddyCharacter

/// First launch: who Coco is, a first task, the optional extras (each explained before
/// any permission prompt), and a few shortcuts. Every step can be skipped.
/// Figma: Screen / Sky Welcome 1–4 — paper inside a 2 pt navy rim, like the panel.
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
            hero

            VStack(alignment: .leading, spacing: Sky.Space.stack) {
                switch step {
                case 0: meet
                case 1: plan
                case 2: extras
                default: shortcuts
                }
            }
            .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 32)
            .padding(.top, Sky.Space.row)
            .clipped()

            footer
                .padding(.horizontal, 32)
                .padding(.top, 16)
                .padding(.bottom, 24)
        }
        .padding(2)
        .frame(width: 460, height: 624)
        .background(Sky.paper)
        .clipShape(RoundedRectangle(cornerRadius: Sky.Radius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Sky.Radius.panel, style: .continuous).strokeBorder(Sky.navy, lineWidth: 2))
        // The Sky colours are light-only, like the panel's.
        .environment(\.colorScheme, .light)
        // Fills the whole window; the traffic lights sit over the hero.
        .ignoresSafeArea()
    }

    /// Coco on a soft accent-pale halo. Figma: Welcome/Sky/Hero.
    private var hero: some View {
        ZStack(alignment: .top) {
            Circle()
                .fill(Sky.accentPale)
                .frame(width: 148, height: 148)
                .padding(.top, 40)
            LiveCoco(state: [.idle, .listening, .thinking, .celebrating][step], animated: animated)
                .frame(width: 132, height: 157)
                .padding(.top, 28)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 186, alignment: .top)
        .accessibilityHidden(true)
    }

    private var footer: some View {
        HStack(spacing: Sky.Space.row) {
            StepDots(step: step, count: steps)
            Spacer(minLength: 0)
            if step > 0 {
                Button { withAnimation(.snappy) { step -= 1 } } label: {
                    Text("Back").skyType(.labelPriority)
                }
                .buttonStyle(SkyButtonStyle(kind: .quiet))
            }
            Button(step == steps - 1 ? "Start" : "Next") { next() }
                .buttonStyle(SkyButtonStyle(kind: .accent))
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Steps

    private var meet: some View {
        VStack(alignment: .leading, spacing: Sky.Space.stack) {
            StepTitle("Meet \(Buddy.name).")
            StepText("She lives on your desktop and keeps you company while you work. Drag her anywhere — she'll remember the spot. Click her for your day, the focus timer and a chat.")
            StepText("She stays quiet while you focus, and naps when you step away.")
        }
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: Sky.Space.stack) {
            StepTitle("What's one thing for today?")
            StepText("Add it now, or skip — you can always add tasks from her panel.")
            HStack(spacing: 10) {
                Text("+").skyType(.titleEmphasis).foregroundStyle(Sky.accent)
                TextField("First task", text: $firstTask, prompt: Text("e.g. Draft the homepage ~45m !!").foregroundStyle(Sky.faint))
                    .textFieldStyle(.plain)
                    .skyType(.bodyDefault)
                    // The field's style also colours the prompt, so it's faint until there's text.
                    .foregroundStyle(firstTask.isEmpty ? Sky.faint : Sky.ink)
                    .focused($taskFocused)
                    .onSubmit(addTask)
            }
            .frame(minHeight: 20)
            .padding(.horizontal, 1)
            .skyField(rim: nil)
            // Figma: Welcome/Sky/TaskField — no rim at rest, an accent-soft ring while focused.
            .overlay {
                if taskFocused {
                    RoundedRectangle(cornerRadius: Sky.Radius.field, style: .continuous)
                        .strokeBorder(Sky.accentSoft, lineWidth: 1.5)
                }
            }
            let added = model.tasks.openToday.prefix(3)
            if !added.isEmpty {
                VStack(alignment: .leading, spacing: Sky.Space.row) {
                    ForEach(added) { task in
                        HStack(spacing: Sky.Space.row) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(Sky.accent)
                                .frame(width: 13, height: 13)
                            Text(task.title).skyType(.bodySmall).foregroundStyle(Sky.ink)
                        }
                    }
                }
            }
            StepText("Tip: ~30m adds an estimate, ! to !!! sets priority, @today makes it a one-day item.")
        }
        .onAppear { taskFocused = true }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: Sky.Space.stack) {
            StepTitle("Optional extras")
            StepText("All off until you choose them. Everything else works without.")
            VStack(spacing: 6) {
                Extra(symbol: "waveform", title: "Voice",
                      detail: "To talk to her, press the mic (⌘L) in her panel — macOS asks for microphone access the first time. She answers with a bark and a speech bubble.") {
                    Keycap(keys: "⌘L")
                }
                Extra(symbol: "calendar", title: "Calendar",
                      detail: "Apple Calendar, Google Calendar or both — shown as one schedule, with open time and meeting reminders. Events change only when you confirm.") {
                    Button("Set up…") { model.openConnections() }.buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                }
                Extra(symbol: "bubble.left", title: "Chat with Claude",
                      detail: "Bring your own Anthropic API key. Your day is shared only when you ask about it.") {
                    Button("Add key…") { model.openConnections() }.buttonStyle(SkyButtonStyle(kind: .outline, compact: true))
                }
            }
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: Sky.Space.stack) {
            StepTitle("You're set.")
            VStack(alignment: .leading, spacing: 10) {
                ShortcutRow(keys: GlobalShortcut.displayName, text: "Open \(Buddy.name) from any app")
                ShortcutRow(keys: "Click", text: "Open her panel · drag to move her")
                ShortcutRow(keys: "Right-click", text: "Presence, sounds, voice, hide")
                ShortcutRow(keys: "⌘1 ⌘2 ⌘3", text: "Today · Focus · Chat")
                ShortcutRow(keys: "↓ Space ↩", text: "Move through tasks · tick · edit")
            }
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
        Text(text).skyType(.displayHeading).foregroundStyle(Sky.ink)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct StepText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).skyType(.bodyDefault).foregroundStyle(Sky.muted).fixedSize(horizontal: false, vertical: true)
    }
}

/// The current step is a green pill, the rest ring dots. Figma: Welcome/Sky/StepDots.
private struct StepDots: View {
    let step: Int
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? Sky.confirm : Sky.ring)
                    .frame(width: index == step ? 18 : 6, height: 6)
            }
        }
        .accessibilityLabel("Step \(step + 1) of \(count)")
    }
}

/// A key or gesture on a white pill. `minWidth` 96 lines up a column of shortcuts (Wide);
/// without it the cap hugs its label (Fit). Figma: Welcome/Sky/Keycap.
private struct Keycap: View {
    let keys: String
    var minWidth: CGFloat?

    var body: some View {
        Text(keys)
            .skyType(.labelButtonCompact)
            .foregroundStyle(Sky.ink)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minWidth: minWidth, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous).fill(Sky.paper))
            .overlay(RoundedRectangle(cornerRadius: Sky.Radius.key, style: .continuous).strokeBorder(Sky.ring))
    }
}

/// Figma: Welcome/Sky/ExtraCard.
private struct Extra<Accessory: View>: View {
    let symbol: String
    let title: String
    let detail: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: Sky.Space.stack) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Sky.accent)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Sky.accentPale))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).skyType(.titleEmphasis).foregroundStyle(Sky.ink)
                Text(detail).skyType(.bodyCaption).foregroundStyle(Sky.muted).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            accessory
        }
        .padding(13)
        .skyCard()
    }
}

/// Figma: Welcome/Sky/ShortcutRow.
private struct ShortcutRow: View {
    let keys: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Keycap(keys: keys, minWidth: 96)
            Text(text).skyType(.bodySmall).foregroundStyle(Sky.ink)
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
