#if DEBUG
import SwiftUI
import BuddyCore
import BuddyCharacter

// EXPERIMENT — Coco's panel as the reference's plush toy: a soft ice card with a coloured
// header band per section and squishy buttons. Same AppModel as the real panel.

struct PTPanelView: View {
    @Bindable var model: AppModel
    @State var section: EOSection
    @State var expandedEventID: String?
    var onClose: () -> Void = {}
    @State private var cocoCue = EOCoco.Cue()
    @State private var floatUp = false
    @Environment(\.eoStill) private var still

    init(model: AppModel, section: EOSection = .today, expandedEventID: String? = nil, onClose: @escaping () -> Void = {}) {
        self.model = model
        _section = State(initialValue: section)
        _expandedEventID = State(initialValue: expandedEventID)
        self.onClose = onClose
    }

    private var editingTask: BuddyTask? { model.editingTaskID.flatMap { model.tasks.task($0) } }
    private var showsVoiceReview: Bool { !model.taskDrafts.isEmpty && model.draftOrigin == .voice }

    var body: some View {
        let _ = model.dayToken
        ZStack {
            PTRoom()
            card.padding(PT.roomMargin)
        }
        .environment(\.colorScheme, .light)
        .onExitCommand {
            if model.editingTaskID != nil { model.editingTaskID = nil } else { onClose() }
        }
        .onChange(of: model.tasks.today().filter(\.isCompleted).count) { old, new in
            if new > old { cocoCue.send(.celebrate) }
        }
        .onAppear { if !still { withAnimation(PT.Motion.float) { floatUp = true } } }
        .background(shortcuts)
    }

    private var card: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                Group {
                    switch section {
                    case .today: PTTodayView(model: model, expandedEventID: $expandedEventID) { section = $0 }
                    case .focus: PTFocusView(model: model)
                    case .chat: PTChatView(model: model)
                    case .system: PTExtras(model: model)
                    }
                }
                .id(section)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.opacity)
                tabBar
            }

            if let task = editingTask {
                ZStack(alignment: .bottom) {
                    PT.aqua.opacity(0.85).onTapGesture { model.editingTaskID = nil }
                    PTEditorSheet(task: task, model: model).id(task.id).padding(16)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
            } else if showsVoiceReview {
                ZStack {
                    PT.aqua
                    PTVoiceReview(model: model).padding(24)
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .frame(maxWidth: PT.cardSize.width, maxHeight: .infinity)
        .background(PT.ice)
        .clipShape(RoundedRectangle(cornerRadius: PT.cardRadius, style: .continuous))
        // `inset_0_8px_0 white` — the bright top lip — and the 4pt aqua border.
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: PT.cardRadius, style: .continuous)
                .stroke(.white, lineWidth: 8)
                .mask(alignment: .top) { Rectangle().frame(height: 40) }
                .opacity(section == .system ? 1 : 0)
        }
        .overlay(RoundedRectangle(cornerRadius: PT.cardRadius, style: .continuous).strokeBorder(PT.rim, lineWidth: 4))
        .shadow(color: PT.ink.opacity(0.1), radius: 30, y: 30)
        .animation(PT.Motion.slideUp, value: model.editingTaskID)
        .animation(PT.Motion.pop, value: showsVoiceReview)
        .animation(EO.Motion.fadeIn, value: section)
    }

    // MARK: - Header band

    private var bandColor: Color {
        switch section {
        case .today: PT.mint
        case .focus: PT.butter
        case .chat: PT.white
        case .system: PT.ice
        }
    }

    private var bandEdge: Color {
        switch section {
        case .today: PT.mintEdge
        case .focus: PT.butterEdge
        case .chat, .system: PT.aqua
        }
    }

    private var onBand: Color { section == .today ? .white : PT.ink }

    private var title: String {
        switch section {
        case .today: "Tasks"
        case .focus: "Focus"
        case .chat: Buddy.name
        case .system: "Plush Extras"
        }
    }

    /// `p-8 pb-6 rounded-b-[48px] inset_0_-8px_0 edge` — with Coco floating on the right.
    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                PTExperimentTag()
                Spacer()
                Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11, weight: .black)) }
                    .buttonStyle(PTSquish(kind: .pillow, radius: 99, depth: 4, padding: EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8), size: 11))
                    .help("Close (Esc)")
                    .accessibilityLabel("Close the Plush Toybox experiment")
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(PT.font(36)).foregroundStyle(onBand).lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(PT.font(14, .bold)).foregroundStyle(section == .today ? .white.opacity(0.85) : PT.slate)
                }
                Spacer(minLength: 0)
                coco
            }
            if section == .today { progress }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .background {
            UnevenRoundedRectangle(bottomLeadingRadius: PT.Radius.sheet, bottomTrailingRadius: PT.Radius.sheet, style: .continuous)
                .fill(bandColor)
                .overlay(alignment: .bottom) { Rectangle().fill(bandEdge).frame(height: 8) }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: PT.Radius.sheet, bottomTrailingRadius: PT.Radius.sheet, style: .continuous))
                .shadow(color: bandColor == PT.ice ? .clear : bandColor.opacity(0.25), radius: 12, y: 12)
        }
        .zIndex(1)
    }

    private var subtitle: String {
        switch section {
        case .chat: model.assistant.isReady ? (model.assistant.isResponding ? "Thinking… 💭" : "Online & cozy") : "Napping — no API key"
        case .system: "Make \(Buddy.name) even softer."
        default: Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
    }

    /// Coco, floating (`animate-float`), in a soft circle; pat her for a bark.
    private var coco: some View {
        EOCoco(state: cocoState, cue: cocoCue, still: still)
            .frame(width: 150, height: 178)
            .scaleEffect(0.45)
            .frame(width: 68, height: 80)
            .offset(y: floatUp ? -5 : 5)
            .contentShape(Rectangle())
            .onTapGesture { cocoCue.send(.poke); model.bark() }
            .onHover { if $0 { cocoCue.send(.perk) } }
            .help("Pat \(Buddy.name)")
            .accessibilityLabel("\(Buddy.name). Click to pat her.")
            .accessibilityAddTraits(.isButton)
    }

    /// `bg-white/20 rounded-[24px]` row: "Progress" and a white 1/5 chip.
    private var progress: some View {
        let tasks = model.tasks.today()
        let done = tasks.filter(\.isCompleted).count
        return HStack {
            Text("Progress").font(PT.font(17, .bold)).foregroundStyle(.white)
            Spacer()
            Text("\(done)/\(tasks.count)")
                .font(PT.font(15))
                .foregroundStyle(PT.mint)
                .contentTransition(.numericText())
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(Capsule().fill(.white))
                .animation(PT.Motion.pop, value: done)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: PT.Radius.field, style: .continuous).fill(.white.opacity(0.2)))
        .accessibilityElement(children: .combine)
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

    /// A white tray (`rounded-t-[40px]`) of four squishy chips; the current one mint.
    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(EOSection.allCases) { item in
                let selected = item == section
                Button {
                    withAnimation(PT.Motion.pop) { section = item }
                } label: {
                    VStack(spacing: 2) {
                        Text(emoji(item)).font(.system(size: 17))
                        Text(label(item)).font(PT.font(11))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PTSquish(kind: selected ? .mint : .quiet, radius: PT.Radius.chip, depth: 5,
                                      padding: EdgeInsets(top: 7, leading: 2, bottom: 5, trailing: 2), size: 11))
                .accessibilityLabel(label(item))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 40, topTrailingRadius: 40, style: .continuous)
                .fill(.white)
                .shadow(color: PT.ink.opacity(0.05), radius: 10, y: -10)
        }
    }

    private func emoji(_ section: EOSection) -> String {
        switch section {
        case .today: "🧸"
        case .focus: "⏰"
        case .chat: "💬"
        case .system: "✨"
        }
    }

    private func label(_ section: EOSection) -> String {
        switch section {
        case .today: "Tasks"
        case .focus: "Focus"
        case .chat: "Chat"
        case .system: "Extras"
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
#endif
