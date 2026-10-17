#if DEBUG
import SwiftUI
import BuddyCore
import BuddyCharacter
import BuddyIntegrations

// EXPERIMENT — Coco's panel as the reference's soft toy card. Same AppModel as the real
// panel; tasks, focus, chat and the merged calendars are all real.

struct TOPanelView: View {
    @Bindable var model: AppModel
    @State var section: EOSection
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

    private var editingTask: BuddyTask? { model.editingTaskID.flatMap { model.tasks.task($0) } }
    private var showsVoiceReview: Bool { !model.taskDrafts.isEmpty && model.draftOrigin == .voice }
    private var sheetOpen: Bool { editingTask != nil || showsVoiceReview }

    var body: some View {
        let _ = model.dayToken
        ZStack {
            TODesk()
            card
                .padding(.horizontal, TO.deskMargin)
                .padding(.top, TO.deskMargin)
                .padding(.bottom, TO.deskMargin + TO.cardDrop)
        }
        .environment(\.colorScheme, .light)
        .onExitCommand {
            if model.editingTaskID != nil { model.editingTaskID = nil } else { onClose() }
        }
        .onChange(of: model.tasks.today().filter(\.isCompleted).count) { old, new in
            if new > old { cocoCue.send(.celebrate) }
        }
        .background(shortcuts)
    }

    // MARK: - Card

    private var card: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                Group {
                    switch section {
                    case .today: TOTodayView(model: model, expandedEventID: $expandedEventID) { section = $0 }
                    case .focus: TOFocusView(model: model)
                    case .chat: TOChatView(model: model)
                    case .system: TOPowerUps(model: model)
                    }
                }
                .id(section)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
                tabBar
            }
            .blur(radius: sheetOpen ? 2 : 0)
            .opacity(sheetOpen ? 0.4 : 1)
            .allowsHitTesting(!sheetOpen)

            if let task = editingTask {
                TOEditorSheet(task: task, model: model)
                    .id(task.id)
                    .padding(.horizontal, 16)
                    .padding(.top, 88)
                    .padding(.bottom, 16)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .zIndex(2)
            } else if showsVoiceReview {
                TOVoiceReview(model: model)
                    .padding(.horizontal, 24)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(maxWidth: TO.cardSize.width, maxHeight: .infinity)
        .background(TO.card)
        .clipShape(RoundedRectangle(cornerRadius: TO.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TO.cardRadius, style: .continuous).strokeBorder(.white, lineWidth: TO.rim))
        .background {
            RoundedRectangle(cornerRadius: TO.cardRadius, style: .continuous)
                .fill(TO.drop)
                .offset(y: TO.cardDrop)
        }
        .animation(TO.Motion.pop, value: model.editingTaskID)
        .animation(TO.Motion.pop, value: showsVoiceReview)
        .animation(EO.Motion.fadeIn, value: section)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            // Coco in the reference's white disc with a sunken bottom edge.
            ZStack {
                Circle().fill(.white)
                Circle().strokeBorder(TO.edge, lineWidth: 3)
                EOCoco(state: cocoState, cue: cocoCue, still: still)
                    .frame(width: 150, height: 178)
                    .scaleEffect(0.42)
                    .frame(width: 63, height: 75)
                    .offset(y: -6)
            }
            .frame(width: 68, height: 68)
            .clipShape(Circle())
            .contentShape(Circle())
            .onTapGesture { cocoCue.send(.poke); model.bark() }
            .onHover { if $0 { cocoCue.send(.perk) } }
            .help("Pat \(Buddy.name)")
            .accessibilityLabel("\(Buddy.name). Click to pat her.")
            .accessibilityAddTraits(.isButton)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(TO.font(34))
                    .tracking(0.8)
                    .foregroundStyle(TO.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(TO.font(13, .medium))
                    .foregroundStyle(TO.inkSecondary)
            }
            Spacer(minLength: 0)
            if let tile = countTile {
                tile
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 50)
        .padding(.bottom, 14)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                TOExperimentTag()
                Button(action: onClose) { Text("✕").font(TO.font(13)) }
                    .buttonStyle(TOKey(kind: .white, radius: 99, depth: 3, padding: EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9), size: 13))
                    .foregroundStyle(TO.inkSecondary)
                    .help("Close (Esc)")
                    .accessibilityLabel("Close the Tactile Orange experiment")
            }
            .padding(.top, 14)
            .padding(.trailing, 22)
        }
    }

    private var title: String {
        switch section {
        case .today: "Tasks"
        case .focus: "Focus"
        case .chat: "Chat"
        case .system: "Power Ups"
        }
    }

    /// The reference's white 64pt tile: "1/5" on Tasks, the countdown in Focus.
    private var countTile: AnyView? {
        let tile: (Text) -> AnyView = { text in
            AnyView(text
                .frame(minWidth: 64, minHeight: 60)
                .padding(.horizontal, 4)
                .toFace(.white, edge: TO.edge, radius: 20, depth: 4)
                .contentTransition(.numericText()))
        }
        switch section {
        case .today:
            let tasks = model.tasks.today()
            guard !tasks.isEmpty else { return nil }
            return tile(Text("\(tasks.filter(\.isCompleted).count)").font(TO.font(22)).foregroundColor(TO.orange)
                        + Text("/\(tasks.count)").font(TO.font(14)).foregroundColor(TO.inkMuted))
        case .focus where model.focus.timer.isActive:
            return tile(Text(AppModel.clock(model.focus.remaining)).font(TO.font(17)).foregroundColor(TO.orange))
        default:
            return nil
        }
    }

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

    // MARK: - Tab bar

    /// Four chunky keys along the bottom of the card, the current one orange.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(EOSection.allCases) { item in
                let selected = item == section
                Button {
                    withAnimation(TO.Motion.pop) { section = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: symbol(item)).font(.system(size: 15, weight: .bold))
                        Text(item == .system ? "Power" : item == .today ? "Tasks" : item.title).font(TO.font(11))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(TOKey(kind: selected ? .orange : .white, radius: 18, depth: 4,
                                   padding: EdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4), size: 11))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }

    private func symbol(_ section: EOSection) -> String {
        switch section {
        case .today: "checklist"
        case .focus: "timer"
        case .chat: "bubble.left.fill"
        case .system: "bolt.fill"
        }
    }

    private var shortcuts: some View {
        ZStack {
            ForEach(Array(EOSection.allCases.enumerated()), id: \.offset) { index, item in
                Button("") { section = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Coco's latest line in a small white speech bubble.
struct TOSpeech: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("🐾").font(.system(size: 13))
            Text(text)
                .font(TO.font(15, .medium))
                .foregroundStyle(TO.ink)
                .fixedSize(horizontal: false, vertical: true)
                .id(text)
                .transition(.opacity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toFace(.white, edge: TO.edge, radius: 20, depth: 4)
        .animation(EO.Motion.fadeIn, value: text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(Buddy.name) says: \(text)")
    }
}
#endif
