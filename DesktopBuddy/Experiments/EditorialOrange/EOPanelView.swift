#if DEBUG
import SwiftUI
import BuddyCore
import BuddyCharacter

// EXPERIMENT — the Editorial Orange version of Coco's panel. Same AppModel as the real
// panel (tasks, focus, chat, merged calendars), its own look and layout.

enum EOSection: String, CaseIterable, Identifiable {
    case today, focus, chat, system
    var id: Self { self }

    var title: String {
        switch self {
        case .today: "Today"
        case .focus: "Focus"
        case .chat: "Chat"
        case .system: "System"
        }
    }

    /// "Vol. 1 — Tasks": the reference numbers its sections like an issue.
    var kicker: String {
        switch self {
        case .today: "Vol. 1 — Tasks"
        case .focus: "Vol. 2 — Focus"
        case .chat: "Vol. 3 — Dialog"
        case .system: "Vol. 4 — System"
        }
    }
}

/// The whole experimental page: orange top rule, dot grid, masthead with Coco, the current
/// section, and the orange editor / voice-review sheets over it.
struct EOPanelView: View {
    @Bindable var model: AppModel
    @State var section: EOSection
    /// The calendar event opened out in the schedule (snapshots can preset it).
    @State var expandedEventID: String?
    var onClose: () -> Void = {}
    @State private var cocoCue = EOCoco.Cue()
    @Environment(\.eoStill) private var still

    init(model: AppModel, section: EOSection = .today, expandedEventID: String? = nil, onClose: @escaping () -> Void = {}) {
        self.model = model
        _section = State(initialValue: section)
        _expandedEventID = State(initialValue: expandedEventID)
        self.onClose = onClose
    }

    private var editingTask: BuddyTask? {
        model.editingTaskID.flatMap { model.tasks.task($0) }
    }

    private var showsVoiceReview: Bool {
        !model.taskDrafts.isEmpty && model.draftOrigin == .voice
    }

    var body: some View {
        let _ = model.dayToken
        ZStack(alignment: .top) {
            EO.paper
            EODotGrid()
            VStack(spacing: 0) {
                EOTopRule()
                masthead
                Group {
                    switch section {
                    case .today: EOTodayView(model: model, expandedEventID: $expandedEventID, openSection: open)
                    case .focus: EOFocusView(model: model)
                    case .chat: EOChatView(model: model, openSection: open)
                    case .system: EOSystemView(model: model)
                    }
                }
                .id(section)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
            }

            if let task = editingTask {
                EOEditorSheet(task: task, model: model)
                    .id(task.id)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            } else if showsVoiceReview {
                EOVoiceReviewSheet(model: model)
                    .transition(.opacity.combined(with: .offset(y: EO.Motion.slideDistance)))
                    .zIndex(2)
            }
        }
        .frame(width: EO.pageSize.width)
        .frame(maxHeight: .infinity)
        .clipped()
        .environment(\.colorScheme, .light)
        .animation(EO.Motion.slideUp, value: model.editingTaskID)
        .animation(EO.Motion.slideUp, value: showsVoiceReview)
        .animation(EO.Motion.fadeIn, value: section)
        .onExitCommand {
            if model.editingTaskID != nil { model.editingTaskID = nil } else { onClose() }
        }
        .onChange(of: model.tasks.today().filter(\.isCompleted).count) { old, new in
            if new > old { cocoCue.send(.celebrate) }
        }
        .background(shortcuts)
    }

    private func open(_ section: EOSection) {
        self.section = section
    }

    // MARK: - Masthead

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: EO.Space.xs) {
                EOExperimentBadge()
                Spacer()
                Button(action: onClose) {
                    Text("✕").font(EO.font(16, .light)).foregroundStyle(EO.Ink.secondary)
                }
                .buttonStyle(.plain)
                .help("Close the experiment (Esc)")
                .accessibilityLabel("Close the Editorial Orange experiment")
            }
            .padding(.top, 14)

            HStack(alignment: .bottom, spacing: EO.Space.sm) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.focus.timer.isRunning ? EO.orange : EO.Ink.faint)
                            .frame(width: 6, height: 6)
                            .eoPulse(model.focus.timer.isRunning && !still)
                        EOKicker(Buddy.name, color: EO.ink, size: 11)
                        EOKicker("· " + Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                                 color: EO.Ink.secondary, size: 11, weight: .medium)
                    }
                    EONav(selection: $section, badge: navBadge)
                }
                Spacer(minLength: 0)
                EOCoco(state: cocoState, cue: cocoCue, still: still)
                    .frame(width: 150, height: 178)
                    .scaleEffect(0.5, anchor: .bottomTrailing)
                    .frame(width: 75, height: 89, alignment: .bottomTrailing)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        cocoCue.send(.poke)
                        model.bark()
                    }
                    .onHover { if $0 { cocoCue.send(.perk) } }
                    .help("Pat \(Buddy.name)")
                    .accessibilityLabel("\(Buddy.name). Click to pat her.")
                    .accessibilityAddTraits(.isButton)
            }
            .padding(.top, 6)
            EORule()
        }
        .padding(.horizontal, EO.Space.page)
    }

    /// A footnote-style figure beside a section name: tasks done, time left in a session.
    private func navBadge(_ section: EOSection) -> String? {
        switch section {
        case .today:
            let tasks = model.tasks.today()
            return tasks.isEmpty ? nil : "\(tasks.filter(\.isCompleted).count)/\(tasks.count)"
        case .focus:
            return model.focus.timer.isActive ? AppModel.clock(model.focus.remaining) : nil
        default:
            return nil
        }
    }

    /// What Coco is doing in the real app, read from app state (not the desktop Coco's
    /// animator, which changes every frame).
    private var cocoState: CharacterState {
        if model.voiceIn.isListening { return .listening }
        switch model.assistant.phase {
        case .writing: return .talking
        case .waiting, .usingTools: return .thinking
        case .idle: break
        }
        if model.focus.timer.isRunning && model.focus.timer.phase == .focus { return .focused }
        if model.isUserAway { return .sleeping }
        return .idle
    }

    /// ⌘1–⌘4 switch sections, like the real panel's tabs.
    private var shortcuts: some View {
        ZStack {
            ForEach(Array(EOSection.allCases.enumerated()), id: \.offset) { index, section in
                Button("") { self.section = section }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

// MARK: - Nav

/// The section switcher, set like a contents line: the current section in medium italic over
/// a 2pt rule that slides between them, figures raised like footnotes.
private struct EONav: View {
    @Binding var selection: EOSection
    let badge: (EOSection) -> String?
    @Namespace private var rule

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 22) {
            ForEach(EOSection.allCases) { section in
                Item(section: section, badge: badge(section), selected: section == selection, rule: rule) {
                    withAnimation(EO.Motion.slideUp) { selection = section }
                }
            }
        }
    }

    private struct Item: View {
        let section: EOSection
        let badge: String?
        let selected: Bool
        let rule: Namespace.ID
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(section.title)
                        .font(EO.font(17, selected ? .medium : .light, italic: selected))
                        .foregroundStyle(selected || hovering ? EO.ink : EO.Ink.secondary)
                    if let badge {
                        Text(badge)
                            .font(EO.font(9, .bold))
                            .monospacedDigit()
                            .foregroundStyle(EO.orange)
                            .baselineOffset(7)
                            .contentTransition(.numericText())
                    }
                }
                .fixedSize()
                .padding(.bottom, 8)
                .overlay(alignment: .bottom) {
                    if selected {
                        Rectangle().fill(EO.ink).frame(height: 2).matchedGeometryEffect(id: "rule", in: rule)
                    } else if hovering {
                        Rectangle().fill(EO.Ink.rule).frame(height: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(EO.Motion.quick, value: hovering)
            .accessibilityLabel(badge.map { "\(section.title), \($0)" } ?? section.title)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
    }
}

// MARK: - Coco

/// Coco's real art (CocoLayerView + the shared animator), in the experiment's masthead.
/// It has its own CharacterModel so it never moves the desktop Coco; pats and wins are
/// sent in as cues.
struct EOCoco: NSViewRepresentable {
    enum Reaction { case poke, perk, celebrate }

    /// A one-off reaction, counted so repeats register.
    struct Cue: Equatable {
        var count = 0
        var reaction: Reaction = .poke

        mutating func send(_ reaction: Reaction) {
            self.reaction = reaction
            count += 1
        }
    }

    let state: CharacterState
    var cue = Cue()
    var still = false

    final class Coordinator {
        let model = CharacterModel()
        var loop: CharacterRenderLoop?
        var lastCue = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CocoLayerView {
        let view = CocoLayerView(frame: NSRect(x: 0, y: 0, width: 150, height: 178))
        context.coordinator.lastCue = cue.count
        if still {
            view.render(LiveCoco.stillPose(state), focusProgress: nil)
            return view
        }
        let loop = CharacterRenderLoop(model: context.coordinator.model, view: view)
        context.coordinator.loop = loop
        context.coordinator.model.setBaseState(state)
        DispatchQueue.main.async { loop.setNeedsFrame() }
        return view
    }

    func updateNSView(_ view: CocoLayerView, context: Context) {
        if still {
            view.render(LiveCoco.stillPose(state), focusProgress: nil)
            return
        }
        let coordinator = context.coordinator
        coordinator.model.setBaseState(state)
        if cue.count != coordinator.lastCue {
            coordinator.lastCue = cue.count
            switch cue.reaction {
            case .poke: coordinator.model.react(.poke)
            case .perk: coordinator.model.react(.perk)
            case .celebrate: coordinator.model.play(.celebrating, for: 1.6)
            }
        }
        coordinator.loop?.setNeedsFrame()
    }

    static func dismantleNSView(_ view: CocoLayerView, coordinator: Coordinator) {
        coordinator.loop?.isPaused = true
    }
}

/// Coco's latest line as a pull quote, with the reference's oversized faint “ behind it.
struct EOPullQuote: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
                Text(text)
                    .font(EO.font(EO.Size.lead, .light, italic: true))
                    .foregroundStyle(EO.ink)
                    .lineSpacing(4)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(text)
                    .transition(.opacity.combined(with: .offset(y: 6)))
                EOKicker("— \(Buddy.name)", size: EO.Size.micro)
        }
        .padding(.leading, 22)
        // The oversized “ sits behind the text without taking up room.
        .background(alignment: .topLeading) {
            Text("\u{201C}")
                .font(.system(size: 150, weight: .regular, design: .serif))
                .foregroundStyle(EO.orange.opacity(0.1))
                .fixedSize()
                .frame(width: 1, height: 1, alignment: .topLeading)
                .offset(x: -14, y: -28)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(EO.Motion.fadeIn, value: text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Buddy.name) says: \(text)")
    }
}
#endif
