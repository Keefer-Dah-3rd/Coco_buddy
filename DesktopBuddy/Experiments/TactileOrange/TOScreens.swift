#if DEBUG
import SwiftUI
import BuddyCore
import BuddyIntegrations

// EXPERIMENT — Tactile Orange: editor sheet, voice review, Focus, Chat and Power Ups.
// Same AppModel intents as the real panel; nothing changes without the same confirmations.

// MARK: - Editor ("Embossed Modal")

struct TOEditorSheet: View {
    let task: BuddyTask
    let model: AppModel
    @State private var draft: BuddyTask
    @FocusState private var field: Field?

    private enum Field { case title, notes }

    init(task: BuddyTask, model: AppModel) {
        self.task = task
        self.model = model
        _draft = State(initialValue: task)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("EDIT MODE").font(TO.font(13)).tracking(1.4).foregroundStyle(TO.inkMuted)
                Spacer()
                Button { close() } label: { Text("✕").font(TO.font(14)) }
                    .buttonStyle(TOKey(kind: .white, radius: 99, depth: 4, padding: EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)))
                    .foregroundStyle(TO.inkSecondary)
                    .help("Close (Esc)")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TOField(focused: field == .title, radius: TO.Radius.field) {
                        TextField("Title", text: $draft.title, axis: .vertical)
                            .textFieldStyle(.plain).font(TO.font(22)).foregroundStyle(TO.ink)
                            .lineLimit(1...3).focused($field, equals: .title).onSubmit(close)
                    }
                    TOField(focused: field == .notes, radius: TO.Radius.field) {
                        TextField("Notes", text: $draft.notes, prompt: Text("Notes, links, the first step…").foregroundStyle(TO.inkMuted), axis: .vertical)
                            .textFieldStyle(.plain).font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary)
                            .lineLimit(2...4).focused($field, equals: .notes)
                    }
                    group("Priority") {
                        HStack(spacing: 8) {
                            ForEach([(TaskPriority.none, "–"), (.low, "L"), (.medium, "M"), (.high, "H")], id: \.0) { value, label in
                                Button(label) { draft.priority = value }
                                    .buttonStyle(TOKey(kind: draft.priority == value ? .orange : .white, radius: 12, depth: 4, fill: true,
                                                       padding: EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0), size: 16))
                                    .help(value.label)
                            }
                        }
                    }
                    HStack(alignment: .top, spacing: 12) {
                        group("Estimate") {
                            HStack(spacing: 8) {
                                step("−") { stepEstimate(-15) }.disabled(draft.estimateMinutes == nil)
                                Text(draft.estimateMinutes.map(TodayView.duration) ?? "—")
                                    .font(TO.font(17)).foregroundStyle(TO.ink).frame(minWidth: 52)
                                    .contentTransition(.numericText())
                                step("+") { stepEstimate(15) }
                            }
                        }
                        group("Keep") {
                            HStack(spacing: 6) {
                                key("List", draft.scope == .personal) { setScope(.personal) }
                                key("Today", draft.scope == .today) { setScope(.today) }
                            }
                        }
                    }
                    group("Due") {
                        let today = Calendar.current.startOfDay(for: .now)
                        let days = draft.deadline.flatMap { Calendar.current.dateComponents([.day], from: today, to: $0).day }
                        HStack(spacing: 6) {
                            key("None", draft.deadline == nil) { draft.deadline = nil }
                            key("Today", days == 0) { draft.deadline = today }
                            key("Tmrw", days == 1) { draft.deadline = Calendar.current.date(byAdding: .day, value: 1, to: today) }
                            key("+1 wk", days == 7) { draft.deadline = Calendar.current.date(byAdding: .day, value: 7, to: today) }
                            if let deadline = draft.deadline, let days, ![0, 1, 7].contains(days) {
                                key(deadline.formatted(.dateTime.weekday(.abbreviated).day()), true) {}
                            }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            Button("Save") { close() }
                .buttonStyle(TOKey(kind: .ink, fill: true, size: 20))
                .keyboardShortcut(.return, modifiers: .command)
            Button("Remove task") { model.removeTask(task.id) }
                .buttonStyle(.plain)
                .font(TO.font(13))
                .foregroundStyle(TO.inkMuted)
                .frame(maxWidth: .infinity)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TO.paper, in: RoundedRectangle(cornerRadius: TO.Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: TO.Radius.sheet, style: .continuous).strokeBorder(.white, lineWidth: 6))
        .shadow(color: .black.opacity(0.15), radius: 20, y: 20)
        .toPop()
        .onAppear { field = .title }
        .onChange(of: draft) { _, new in save(new) }
    }

    private func group<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(TO.font(13)).foregroundStyle(TO.inkSecondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .toFace(TO.card, edge: TO.edge, radius: TO.Radius.key, depth: 4)
    }

    private func key(_ title: String, _ on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(TOKey(kind: on ? .orange : .white, radius: 12, depth: 4, padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10), size: 13))
    }

    private func step(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(glyph, action: action)
            .buttonStyle(TOKey(kind: .white, radius: 12, depth: 4, padding: EdgeInsets(top: 4, leading: 11, bottom: 4, trailing: 11), size: 18))
    }

    private func setScope(_ scope: TaskScope) {
        draft.scope = scope
        draft.plannedDay = scope == .today ? Calendar.current.startOfDay(for: .now) : nil
    }

    private func stepEstimate(_ minutes: Int) {
        let next = (draft.estimateMinutes ?? 0) + minutes
        draft.estimateMinutes = next <= 0 ? nil : min(next, 12 * 60)
    }

    private func close() { model.editingTaskID = nil }

    private func save(_ edited: BuddyTask) {
        model.tasks.update(task.id) { stored in
            stored.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
            stored.notes = edited.notes
            stored.priority = edited.priority
            stored.estimateMinutes = edited.estimateMinutes
            stored.deadline = edited.deadline
            stored.scope = edited.scope
            stored.plannedDay = edited.plannedDay
        }
    }
}

// MARK: - Voice review

/// "I heard 3 things. Add them?" — a white bubble card, Coco bouncing in an orange badge on
/// top. Nothing is added until Add.
struct TOVoiceReview: View {
    @Bindable var model: AppModel
    @State private var up = false
    @Environment(\.eoStill) private var still

    var body: some View {
        let count = model.taskDrafts.count
        VStack(spacing: 0) {
            Text(count == 1 ? "I heard 1 thing.\nAdd it?" : "I heard \(count) things.\nAdd them?")
                .font(TO.font(24))
                .multilineTextAlignment(.center)
                .foregroundStyle(TO.ink)
                .padding(.top, 52)
                .padding(.bottom, 22)
            VStack(spacing: 10) {
                ForEach($model.taskDrafts) { $draft in
                    HStack(spacing: 8) {
                        TextField("Task", text: $draft.title).textFieldStyle(.plain).font(TO.font(15)).foregroundStyle(TO.ink.opacity(0.8))
                        if let minutes = draft.estimateMinutes { TOPill(TodayView.duration(minutes), face: .white, color: TO.inkSecondary) }
                        Button { model.taskDrafts.removeAll { $0.id == draft.id } } label: {
                            Text("✕").font(.system(size: 10, weight: .bold)).foregroundStyle(TO.inkSecondary)
                                .frame(width: 24, height: 24).background(Circle().fill(.white)).shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        }
                        .buttonStyle(.plain)
                        .help("Leave this one out")
                    }
                    .padding(12)
                    .toFace(TO.card, edge: TO.edge, radius: TO.Radius.field, depth: 4)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.bottom, 26)
            VStack(spacing: 14) {
                Button(count == 1 ? "Add Task" : "Add Tasks") { model.addTaskDrafts() }
                    .buttonStyle(TOKey(kind: .ink, fill: true, size: 20))
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Discard") { model.discardTaskDrafts() }
                    .buttonStyle(TOKey(kind: .well, fill: true, size: 20))
            }
        }
        .padding(28)
        .background(.white, in: RoundedRectangle(cornerRadius: TO.Radius.bubble, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: TO.Radius.bubble, style: .continuous).fill(TO.edge).offset(y: 20)
        }
        .overlay(alignment: .top) {
            ZStack {
                Circle().fill(TO.orangeEdge).offset(y: 8)
                Circle().fill(TO.orange)
                Circle().strokeBorder(.white, lineWidth: 4)
                EOCoco(state: .listening, still: still)
                    .frame(width: 150, height: 178).scaleEffect(0.4).frame(width: 60, height: 71).offset(y: 2)
                    .clipShape(Circle())
            }
            .frame(width: 96, height: 96)
            .offset(y: -48 + (up ? -12 : 0))
            .onAppear { if !still { withAnimation(TO.Motion.bounce) { up = true } } }
        }
        .toPop()
        .animation(TO.Motion.pop, value: model.taskDrafts.map(\.id))
    }
}

// MARK: - Focus

struct TOFocusView: View {
    @Bindable var model: AppModel
    private var focus: FocusController { model.focus }
    private var timer: FocusTimer { focus.timer }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    ForEach([(FocusPhase.focus, "Focus"), (.shortBreak, "Short"), (.longBreak, "Long")], id: \.0) { phase, title in
                        Button(title) { focus.prepare(phase) }
                            .buttonStyle(TOKey(kind: timer.phase == phase ? .orange : .white, radius: 16, depth: 4, fill: true,
                                               padding: EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0), size: 14))
                    }
                }
                .disabled(timer.isActive)
                .eoEntrance(0)

                // The time on a big white tile with a progress track sunk into it.
                VStack(spacing: 12) {
                    HStack {
                        Text(AppModel.clock(focus.remaining))
                            .font(TO.font(72))
                            .monospacedDigit()
                            .foregroundStyle(timer.isPaused ? TO.inkMuted : TO.ink)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(TO.Motion.press, value: focus.remaining.rounded(.up))
                        if !timer.isActive && !timer.isFinished {
                            VStack(spacing: 8) {
                                small("+") { focus.adjustLength(by: 5) }.help("5 minutes longer")
                                small("−") { focus.adjustLength(by: -5) }.help("5 minutes shorter")
                            }
                        }
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(TO.card)
                            Capsule().fill(timer.phase == .focus ? TO.orange : TO.ink)
                                .frame(width: max(14, proxy.size.width * focus.progress))
                                .opacity(focus.progress > 0 ? 1 : 0)
                        }
                    }
                    .frame(height: 14)
                    .animation(.linear(duration: 0.3), value: focus.progress)
                }
                .padding(20)
                .toFace(.white, edge: TO.edge, radius: TO.Radius.sheet, depth: 6)
                .eoEntrance(1)

                if timer.isFinished {
                    completion.eoEntrance(2)
                } else {
                    if timer.phase == .focus {
                        Menu {
                            Button("No task — just focus") { focus.selectTask(nil) }
                            let open = model.tasks.openToday
                            if !open.isEmpty { Divider() }
                            ForEach(open) { task in Button(task.title) { focus.selectTask(task.id) } }
                        } label: {
                            Text("🎯 " + (model.tasks.task(timer.taskID)?.title ?? "No task — just focus")).font(TO.font(16)).lineLimit(1)
                        }
                        .menuStyle(.borderlessButton)
                        .tint(TO.ink)
                        .disabled(timer.isActive)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .toFace(TO.card, edge: TO.edge, radius: TO.Radius.key, depth: 4)
                        .overlay(RoundedRectangle(cornerRadius: TO.Radius.key, style: .continuous).strokeBorder(.white, lineWidth: 3).padding(.bottom, 4))
                        .eoEntrance(2)
                    }
                    if model.agenda.isConnected, !timer.isActive, let next = model.agenda.schedule.next(after: .now),
                       next.start.timeIntervalSinceNow < focus.remaining {
                        Text("📅 “\(BuddyVoice.short(next.title))” starts in \(max(1, Int(next.start.timeIntervalSinceNow / 60)))m — before this session ends.")
                            .font(TO.font(13, .medium)).foregroundStyle(TO.orangeEdge)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    controls.eoEntrance(3)
                }

                TOSpeech(text: model.buddyLine).eoEntrance(4)

                HStack {
                    Text("Until long break").font(TO.font(13)).foregroundStyle(TO.inkSecondary)
                    Spacer()
                    ForEach(0..<model.preferences.focusSettings.sessionsBeforeLongBreak, id: \.self) { index in
                        Text(index < timer.focusStreak ? "🦴" : "○").font(.system(size: 14)).foregroundStyle(TO.edge)
                    }
                }
                .eoEntrance(5)
                HStack(spacing: 6) {
                    Text("While focusing").font(TO.font(13)).foregroundStyle(TO.inkSecondary)
                    Spacer()
                    ForEach([(Preferences.FocusPresentation.visible, "Full"), (.smaller, "Small"), (.quiet, "Quiet")], id: \.0) { value, title in
                        Button(title) { model.preferences.focusPresentation = value }
                            .buttonStyle(TOKey(kind: model.preferences.focusPresentation == value ? .ink : .white, radius: 12, depth: 3,
                                               padding: EdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10), size: 12))
                    }
                }
                .eoEntrance(6)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
    }

    @ViewBuilder
    private var controls: some View {
        if timer.isRunning {
            HStack(spacing: 10) {
                Button { focus.pause() } label: { Label("Pause", systemImage: "pause.fill") }
                    .buttonStyle(TOKey(kind: .orange, fill: true, size: 22)).keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }.buttonStyle(TOKey(kind: .white, size: 18))
            }
        } else if timer.isPaused {
            HStack(spacing: 10) {
                Button { focus.resume() } label: { Label("Resume", systemImage: "play.fill") }
                    .buttonStyle(TOKey(kind: .orange, fill: true, size: 22)).keyboardShortcut(.space, modifiers: [])
                Button("Stop") { focus.stop() }.buttonStyle(TOKey(kind: .white, size: 18))
            }
        } else {
            Button { model.startSelectedPhase() } label: { Label(timer.phase == .focus ? "Start" : "Start break", systemImage: "play.fill") }
                .buttonStyle(TOKey(kind: .orange, fill: true, size: 24))
                .shadow(color: TO.orange.opacity(0.3), radius: 12, y: 8)
                .keyboardShortcut(.space, modifiers: [])
        }
    }

    private var completion: some View {
        let next = focus.suggestedNextPhase
        return VStack(spacing: 12) {
            Text(timer.phase == .focus ? "Session done! 🎉" : "Break's over!").font(TO.font(22)).foregroundStyle(TO.ink)
            if let id = model.completionPrompt, let task = model.tasks.task(id), !task.isCompleted {
                Text("Did “\(task.title)” get done?").font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    Button("Yes, done!") { model.confirmTaskDone(id) }.buttonStyle(TOKey(kind: .orange, fill: true, size: 16))
                    Button("Not yet") { model.dismissCompletionPrompt() }.buttonStyle(TOKey(kind: .white, fill: true, size: 16))
                }
            }
            Button("\(next == .focus ? "Focus again" : "Take a \(next.label.lowercased())") · \(model.preferences.focusSettings.minutes(for: next))m") {
                model.startNextPhase()
            }
            .buttonStyle(TOKey(kind: .ink, fill: true, size: 16))
            Button("Skip") { model.skipNextPhase() }.buttonStyle(.plain).font(TO.font(13)).foregroundStyle(TO.inkMuted)
        }
        .padding(18)
        .toFace(.white, edge: TO.edge, radius: TO.Radius.sheet, depth: 6)
        .toPop()
    }

    private func small(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(glyph, action: action)
            .buttonStyle(TOKey(kind: .well, radius: 12, depth: 4, padding: EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10), size: 18))
    }
}

// MARK: - Chat

struct TOChatView: View {
    @Bindable var model: AppModel
    @State private var draft = ""
    @FocusState private var focused: Bool
    private var assistant: AssistantService { model.assistant }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("C").font(TO.font(18)).foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .toFace(TO.orange, edge: TO.orangeEdge, radius: TO.Radius.tile, depth: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Buddy.name) AI").font(TO.font(17)).foregroundStyle(TO.ink)
                    Text(status).font(TO.font(11)).foregroundStyle(assistant.isReady ? TO.orange : TO.inkMuted).eoPulse(assistant.isResponding)
                }
                Spacer()
                Button("New") { model.assistant.newChat() }
                    .buttonStyle(TOKey(kind: .well, radius: 12, depth: 3, padding: EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10), size: 12))
                    .disabled(assistant.turns.isEmpty)
                    .keyboardShortcut("n", modifiers: .command)
            }
            .padding(.horizontal, 22).padding(.vertical, 14)
            .background(.white)
            .overlay(alignment: .bottom) { Rectangle().fill(TO.edge).frame(height: 4) }

            if assistant.isReady {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if assistant.turns.isEmpty { starters }
                            ForEach(assistant.turns) { turn in bubble(turn).eoEntrance(0) }
                            ForEach(model.pendingCompletions, id: \.self) { id in
                                if let task = model.tasks.task(id) {
                                    confirm("Mark “\(BuddyVoice.short(task.title, limit: 36))” done?") {
                                        Button("Mark done") { model.confirmCompletion(task.id) }.buttonStyle(TOKey(kind: .orange, fill: true, size: 15))
                                        Button("Not yet") { model.declineCompletion(task.id) }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
                                    }
                                }
                            }
                            if !model.taskDrafts.isEmpty, model.draftOrigin == .chat { drafts }
                            ForEach(model.eventRequests) { eventRequest($0) }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(22)
                    }
                    .scrollIndicators(.never)
                    .background(TO.paper)
                    .onChange(of: assistant.turns.last?.text) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: assistant.turns.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                    .onChange(of: model.eventRequests.count) { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                composer
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Text("🔑").font(.system(size: 40))
                    Text("Chat needs a Claude API key").font(TO.font(20)).foregroundStyle(TO.ink)
                    Text("Add it in Connections. Everything else works without it.").font(TO.font(14, .medium))
                        .foregroundStyle(TO.inkSecondary).multilineTextAlignment(.center)
                    Button("Open Connections") { model.openConnections() }.buttonStyle(TOKey(kind: .orange, size: 17))
                    Spacer()
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .background(TO.paper)
            }
        }
        .onAppear { focused = true }
    }

    private var status: String {
        guard assistant.isReady else { return "OFFLINE" }
        switch assistant.phase {
        case .idle: return "ONLINE"
        case .waiting, .usingTools: return "THINKING…"
        case .writing: return "TYPING…"
        }
    }

    @ViewBuilder
    private func bubble(_ turn: AssistantService.Turn) -> some View {
        switch turn.role {
        case .user:
            HStack {
                Spacer(minLength: 50)
                Text(turn.text).font(TO.font(15)).foregroundStyle(TO.ink).textSelection(.enabled)
                    .padding(14)
                    .toFace(.white, edge: TO.edge, radius: TO.Radius.key, depth: 4)
            }
        case .coco:
            HStack(alignment: .top, spacing: 10) {
                Text("🐶").font(.system(size: 15)).frame(width: 38, height: 38)
                    .toFace(TO.orange, edge: TO.orangeEdge, radius: TO.Radius.tile, depth: 4)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(turn.activities, id: \.self) { TOPill($0, face: TO.card, color: TO.inkSecondary) }
                    if turn.text.isEmpty && turn.isStreaming {
                        Text("•••").font(TO.font(18)).foregroundStyle(.white).padding(14)
                            .toFace(TO.ink, edge: .black, radius: TO.Radius.key, depth: 4).eoPulse()
                    } else if !turn.text.isEmpty {
                        Text(turn.text).font(TO.font(15)).lineSpacing(4).foregroundStyle(.white).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .toFace(TO.ink, edge: .black, radius: TO.Radius.key, depth: 4)
                    }
                    if let failure = turn.failure {
                        Text(failure).font(TO.font(13, .medium)).foregroundStyle(TO.orangeEdge).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 20)
            }
        }
    }

    private var starters: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask about your day, think something through, or get a plan.").font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary)
            ForEach(["What should I work on next?", "Plan the rest of my day", "What's on my calendar today?", "Break my top task into steps"], id: \.self) { prompt in
                Button(prompt) { model.assistant.send(prompt) }
                    .buttonStyle(TOKey(kind: .white, radius: 18, depth: 4, padding: EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14), size: 15))
            }
        }
    }

    private var drafts: some View {
        confirm("\(Buddy.name) suggests — review before adding") {
            EmptyView()
        } list: {
            ForEach($model.taskDrafts) { $draft in
                HStack {
                    TextField("Task", text: $draft.title).textFieldStyle(.plain).font(TO.font(14)).foregroundStyle(TO.ink)
                    if let minutes = draft.estimateMinutes { TOPill(TodayView.duration(minutes), face: .white, color: TO.inkSecondary) }
                    Button { model.taskDrafts.removeAll { $0.id == draft.id } } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                        .buttonStyle(.plain).foregroundStyle(TO.inkMuted)
                }
                .padding(10)
                .background(TO.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 10) {
                Button(model.taskDrafts.count == 1 ? "Add task" : "Add \(model.taskDrafts.count)") { model.addTaskDrafts() }
                    .buttonStyle(TOKey(kind: .orange, fill: true, size: 15))
                Button("Discard") { model.discardTaskDrafts() }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
            }
        }
    }

    @ViewBuilder
    private func eventRequest(_ request: AppModel.EventRequest) -> some View {
        let (heading, title, when): (String, String, String) = {
            switch request.kind {
            case .create(let d): ("Add to Google Calendar", d.title, AppModel.describe(d.start, d.end, allDay: d.isAllDay))
            case .change(let e, let c): ("Change event", c.title ?? e.title,
                                         c.start.flatMap { s in c.end.map { AppModel.describe(s, $0, allDay: e.isAllDay) } } ?? AppModel.describe(e.start, e.end, allDay: e.isAllDay))
            case .delete(let e): ("Delete event", e.title, AppModel.describe(e.start, e.end, allDay: e.isAllDay))
            }
        }()
        confirm(heading) {
            switch request.state {
            case .waiting:
                Button(heading.hasPrefix("Add") ? "Add" : heading.hasPrefix("Change") ? "Change" : "Delete") { model.confirmEventRequest(request.id) }
                    .buttonStyle(TOKey(kind: .orange, fill: true, size: 15))
                Button("Not now") { model.declineEventRequest(request.id) }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
            case .working:
                Text("Saving…").font(TO.font(14)).foregroundStyle(TO.inkSecondary).eoPulse()
            case .failed:
                Button("Try again") { model.confirmEventRequest(request.id) }.buttonStyle(TOKey(kind: .orange, fill: true, size: 15))
                Button("Dismiss") { model.dismissEventRequest(request.id) }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
            case .done:
                Button("Done ✓") { model.dismissEventRequest(request.id) }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
            }
        } list: {
            Text(title).font(TO.font(17)).foregroundStyle(TO.ink)
            Text(when).font(TO.font(13, .medium)).foregroundStyle(TO.inkSecondary)
            ForEach(request.conflicts) { event in
                TOPill("Overlaps \(BuddyVoice.short(event.title, limit: 24))", face: TO.orange.opacity(0.12), color: TO.orangeEdge)
            }
            if case .failed(let message) = request.state {
                Text("Nothing changed: \(message)").font(TO.font(12, .medium)).foregroundStyle(TO.orangeEdge)
            }
            if case .done(let outcome) = request.state {
                Text(outcome).font(TO.font(13, .medium)).foregroundStyle(TO.ink)
            }
            if case .waiting = request.state, !model.calendar.canChangeEvents {
                Text("The first time, Google asks you to let \(Buddy.name) change events.").font(TO.font(12, .medium)).foregroundStyle(TO.inkSecondary)
            }
        }
    }

    private func confirm<Buttons: View, List: View>(_ heading: String, @ViewBuilder buttons: () -> Buttons,
                                                    @ViewBuilder list: () -> List = { EmptyView() }) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TOPill(heading, face: TO.orange, color: .white)
            list()
            HStack(spacing: 10) { buttons() }
        }
        .padding(16)
        .toFace(.white, edge: TO.edge, radius: TO.Radius.key, depth: 6)
        .toPop()
    }

    private var composer: some View {
        let empty = draft.trimmingCharacters(in: .whitespaces).isEmpty
        return TOField(focused: focused, face: TO.card) {
            HStack(spacing: 8) {
                if model.voiceIn.isListening {
                    Text(model.voiceIn.transcript.isEmpty ? "Listening…" : model.voiceIn.transcript)
                        .font(TO.font(15)).foregroundStyle(TO.ink).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("Message", text: $draft, prompt: Text("Message…").foregroundStyle(TO.inkMuted), axis: .vertical)
                        .textFieldStyle(.plain).font(TO.font(15)).foregroundStyle(TO.ink).lineLimit(1...4)
                        .focused($focused).onSubmit(send)
                }
                Button { model.toggleListening() } label: { Image(systemName: model.voiceIn.isListening ? "stop.fill" : "mic.fill").font(.system(size: 13, weight: .bold)) }
                    .buttonStyle(TOKey(kind: model.voiceIn.isListening ? .orange : .white, radius: TO.Radius.tile, depth: 4,
                                       padding: EdgeInsets(top: 10, leading: 11, bottom: 10, trailing: 11)))
                    .keyboardShortcut("l", modifiers: .command)
                if assistant.isResponding {
                    Button { assistant.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 14, weight: .bold)) }
                        .buttonStyle(TOKey(kind: .ink, radius: TO.Radius.tile, depth: 4, padding: EdgeInsets(top: 10, leading: 13, bottom: 10, trailing: 13)))
                        .keyboardShortcut(".", modifiers: .command)
                } else {
                    Button(action: send) { Text("↑").font(TO.font(20)) }
                        .buttonStyle(TOKey(kind: .orange, radius: TO.Radius.tile, depth: 4, padding: EdgeInsets(top: 6, leading: 14, bottom: 6, trailing: 14)))
                        .disabled(empty)
                        .help("Send (Return)")
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(TO.edge).frame(height: 4) }
    }

    private func send() {
        let text = draft
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !assistant.isResponding else { return }
        draft = ""
        model.assistant.send(text)
    }
}

// MARK: - Power Ups

/// The reference's "Power Ups": every connection and setting is a big key with an icon tile
/// and a switch; on means orange. Live states; connecting opens the real Connections window.
struct TOPowerUps: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("Tap to toggle features").font(TO.font(15, .medium)).foregroundStyle(TO.inkSecondary).eoEntrance(0)
                Text("Connections").font(TO.font(13)).foregroundStyle(TO.inkMuted).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(connections.enumerated()), id: \.offset) { index, row in
                    power(row.icon, row.title, row.detail, on: row.on) { model.openConnections() }.eoEntrance(1 + index)
                }
                Text("\(Buddy.name)").font(TO.font(13)).foregroundStyle(TO.inkMuted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                power("🐕", "Barks", "A woof now and then", on: model.preferences.barksEnabled) { model.preferences.barksEnabled.toggle() }.eoEntrance(5)
                power("💬", "Chats now and then", "Never during focus", on: model.preferences.chatterEnabled) { model.preferences.chatterEnabled.toggle() }.eoEntrance(6)
                power("🔔", "Sounds", "Chimes and barks", on: !model.preferences.soundsMuted) { model.preferences.soundsMuted.toggle() }.eoEntrance(7)
                power("📌", "Always on top", "Above other windows", on: model.preferences.alwaysOnTop) { model.preferences.alwaysOnTop.toggle() }.eoEntrance(8)
                HStack(spacing: 10) {
                    Button("All settings") { model.openSettings() }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
                    Button("Connections") { model.openConnections() }.buttonStyle(TOKey(kind: .white, fill: true, size: 15))
                }
                .eoEntrance(9)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.never)
    }

    private var connections: [(icon: String, title: String, detail: String, on: Bool)] {
        let apple = model.appleCalendar
        let claude: String = switch model.assistant.keyStatus {
        case .ready: "Key saved"
        case .verifying: "Checking key…"
        case .invalid: "Key rejected — replace it"
        case .missing: "Needs an API key"
        }
        let google: String = switch model.calendar.status {
        case .connected: "Read-only until you confirm"
        case .connecting: "Signing in…"
        case .needsReconnect: "Needs reconnecting"
        case .disconnected, .needsClientID: "Not connected"
        }
        let appleText: String = switch apple.access {
        case .granted: apple.isEnabled ? "From Calendar.app" : "Allowed, switched off"
        case .denied, .restricted: "No access — check Privacy settings"
        case .writeOnly: "Needs full access"
        case .notDetermined: "Not connected"
        }
        return [
            ("🤖", "Claude chat", claude, model.assistant.isReady),
            ("📅", "Google Calendar", google, model.calendar.status == .connected),
            ("🍎", "Apple Calendar", appleText, apple.isActive),
            ("🎉", "Partiful", model.partiful.isConnected ? "Your events, in \(Buddy.name) only" : "Not connected", model.partiful.isConnected),
        ]
    }

    private func power(_ icon: String, _ title: String, _ detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(icon).font(.system(size: 22))
                    .frame(width: 48, height: 44)
                    .toFace(on ? TO.orangeEdge : TO.card, edge: on ? TO.orangeDeep : TO.edge, radius: TO.Radius.field, depth: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(TO.font(18))
                    Text(detail).font(TO.font(12, .medium)).opacity(0.7).lineLimit(1)
                }
                Spacer(minLength: 4)
                TOToggle(isOn: on)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(TOKey(kind: on ? .orange : .white, radius: TO.Radius.sheet, padding: EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18)))
        .accessibilityLabel("\(title): \(on ? "on" : "off"). \(detail)")
    }
}
#endif
