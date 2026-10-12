import AppKit
import Observation
import BuddyCore
import BuddyCharacter
import BuddyIntegrations
import BuddyAssistant

enum PanelTab: String, CaseIterable, Identifiable {
    case today, focus, chat
    var id: Self { self }
}

/// Composition root. Owns the feature models and turns what happens in them
/// (a task completed, a session ended, the user stepping away) into what the
/// buddy does and says. Views call the intent methods; nothing here touches windows
/// directly — those are reached through `windows`.
@Observable
final class AppModel {
    struct WindowCommands {
        var setPanelOpen: (Bool) -> Void
        var resetPosition: () -> Void
        var openConnections: () -> Void
        var openSettings: () -> Void
        var showOnboarding: () -> Void
    }

    /// How much a line is allowed to interrupt.
    enum Importance {
        /// Unprompted chatter: only in interactive presence, never during focus.
        case ambient
        /// Response to something the user just did.
        case acknowledge
        /// Session start/end — shown even in compact presence.
        case important
    }

    let preferences: Preferences
    let notifications: NotificationService
    let tasks: TaskStore
    let focus: FocusController
    let focusLog: FocusLogStore
    let calendar: GoogleCalendarService
    let notion: NotionService
    let assistant: AssistantService
    let character = CharacterModel()
    let voiceOut = VoiceOutput()
    let voiceIn = VoiceInput()

    var panelTab: PanelTab = .today
    private(set) var isPanelOpen = false
    /// Bumped each time the panel opens, so views can restore keyboard focus.
    private(set) var panelOpenCount = 0
    /// The buddy's latest line, shown at the top of the panel.
    private(set) var buddyLine: String
    /// After a focus session on a task ends, the buddy asks — it never assumes — whether it's done.
    private(set) var completionPrompt: BuddyTask.ID?
    private(set) var recentlyRemoved: BuddyTask?
    private(set) var isUserAway = false
    /// Bumped when the calendar day changes, so "today" views recompute.
    private(set) var dayToken = 0
    /// True when the global shortcut is switched on but another app already owns it.
    var shortcutUnavailable = false
    /// Tasks the assistant asked about — not marked done unless the user confirms here.
    private(set) var pendingCompletions: [BuddyTask.ID] = []
    @ObservationIgnored private var focusStartedFromChat = false
    /// A Notion-linked task the user just completed: ask before changing Notion.
    private(set) var pendingNotionCompletion: BuddyTask?
    /// The task whose editor is open in the Today list.
    var editingTaskID: BuddyTask.ID?
    /// Tasks heard by voice, waiting for review. Nothing is added until the user confirms.
    var taskDrafts: [TaskDraft] = []
    /// Where the current drafts came from, for the review card's label.
    private(set) var draftOrigin: DraftOrigin = .voice

    enum DraftOrigin { case voice, chat }

    #if DEBUG
    func setDraftOriginForPreview(_ origin: DraftOrigin) { draftOrigin = origin }
    #endif

    struct TaskDraft: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var priority: TaskPriority
        var estimateMinutes: Int?

        init(_ result: QuickAddParser.Result) {
            title = result.title
            priority = result.priority
            estimateMinutes = result.estimateMinutes
        }
    }

    @ObservationIgnored var windows: WindowCommands?
    @ObservationIgnored private let sounds: SoundPlayer
    @ObservationIgnored private let presence = PresenceMonitor()
    @ObservationIgnored private var undoExpiry: Task<Void, Never>?
    @ObservationIgnored private var lastBarkAt = Date.distantPast
    @ObservationIgnored private var reminderTimer: Timer?
    @ObservationIgnored private var remindedEventIDs: Set<String> = []

    /// - Parameter preview: in-memory stores and throwaway defaults, for snapshots.
    init(preview: Bool = false) {
        preferences = preview ? Preferences(defaults: UserDefaults(suiteName: "DesktopBuddy.preview")!) : Preferences()
        notifications = NotificationService()
        tasks = TaskStore(persistent: !preview)
        focus = FocusController(preferences: preferences, notifications: notifications, persistent: !preview)
        focusLog = FocusLogStore(persistent: !preview)
        calendar = GoogleCalendarService(persistent: !preview)
        notion = NotionService(persistent: !preview)
        assistant = AssistantService(persistent: !preview)
        sounds = SoundPlayer(preferences: preferences)
        buddyLine = BuddyVoice.greeting()
    }

    func start() {
        tasks.onEvent = { [weak self] in self?.handle($0) }
        focus.onEvent = { [weak self] in self?.handle($0) }
        focus.taskTitle = { [weak self] in self?.tasks.task($0)?.title }
        presence.onChange = { [weak self] away in self?.userAwayChanged(away) }
        assistant.performAction = { [weak self] action in
            await self?.perform(action) ?? AssistantService.ToolOutcome(result: "Unavailable.", isError: true)
        }
        assistant.onPhaseChanged = { [weak self] phase in
            switch phase {
            case .idle: self?.character.release()
            case .waiting, .usingTools: self?.character.hold(.thinking)
            case .writing: self?.character.hold(.talking)
            }
        }
        assistant.onReplyFinished = { [weak self] reply in
            guard let self, self.voiceAudible, !reply.isEmpty else { return }
            self.voiceOut.speak(reply)
        }
        voiceIn.onFinish = { [weak self] transcript in self?.handleTranscript(transcript) }
        voiceOut.onSpeakingChanged = { [weak self] speaking in self?.character.setVoiceActive(speaking) }
        track({ [weak self] in self?.preferences.voiceEnabled ?? false }) { [weak self] enabled in
            if enabled { self?.voiceOut.prepare() }
        }

        track({ [weak self] in self?.characterSync }) { [weak self] sync in
            guard let self, let sync else { return }
            self.apply(sync)
        }
        presence.start()
        focus.restoreAfterLaunch()
        greetOncePerDay()
        startConnections()
    }

    // MARK: - Connections

    func openConnections() {
        setPanelOpen(false)
        windows?.openConnections()
    }

    func openSettings() {
        setPanelOpen(false)
        windows?.openSettings()
    }

    func showOnboarding() {
        setPanelOpen(false)
        windows?.showOnboarding()
    }

    /// Wipes everything this app has stored — tasks, focus history, timer, calendar sign-in
    /// and cache, the Claude key and chat, preferences — and starts over from the welcome.
    func eraseAllData() async {
        assistant.disconnect()
        notion.disconnect()
        await calendar.eraseAll()
        focus.eraseAll()
        focusLog.eraseAll()
        tasks.eraseAll()
        taskDrafts = []
        pendingCompletions = []
        recentlyRemoved = nil
        editingTaskID = nil
        completionPrompt = nil
        remindedEventIDs = []
        reminderTimer?.invalidate()
        notifications.cancelAll()
        preferences.reset()
        windows?.resetPosition()
        buddyLine = BuddyVoice.greeting()
        panelTab = .today
        windows?.showOnboarding()
    }

    /// Called when the onboarding finishes.
    func finishOnboarding() {
        preferences.onboardingCompleted = true
        bark()
        speak(BuddyVoice.welcomeDone, .important)
    }

    private func startConnections() {
        calendar.onScheduleChanged = { [weak self] in self?.scheduleMeetingReminder() }
        calendar.startAutoRefresh()
        scheduleMeetingReminder()
        // Never leave the mic open across sleep; what was heard so far is discarded.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.voiceIn.cancel() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dayToken += 1
                self?.refreshConnections()
            }
        }
        // Midnight while the app is open: "today" moves on, and so does the calendar.
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dayToken += 1
                self?.remindedEventIDs = []
                self?.refreshConnections()
            }
        }
        refreshConnections()
    }

    /// Calendar, Notion candidates and linked tasks — each only if connected.
    func refreshConnections() {
        Task {
            await calendar.refresh()
            guard Features.notion else { return }
            await notion.refreshTasks()
            await syncLinkedTasks()
        }
    }

    private func syncLinkedTasks() async {
        let refs = tasks.openLinkedRefs
        guard !refs.isEmpty, notion.isReady else { return }
        tasks.applyExternalUpdates(await notion.currentState(of: refs))
    }

    /// Notion tasks the user picked for today.
    func addFromNotion(_ picked: [NotionTask]) {
        let result = tasks.addLinked(picked.map { $0.makeTask() })
        if result.added + result.linked == 0 {
            speak("Those are already on your list.", .acknowledge)
        }
    }

    /// Notion tasks not yet on the list — what the picker offers.
    var notionCandidates: [NotionTask] {
        let linked = Set(tasks.list.tasks.compactMap { $0.external?.id })
        return notion.openTasks.filter { !linked.contains($0.id) }
    }

    func confirmNotionCompletion() {
        guard let task = pendingNotionCompletion, let ref = task.external else { return }
        pendingNotionCompletion = nil
        Task {
            do {
                try await notion.markDone(ref)
                speak(BuddyVoice.notionUpdated, .acknowledge)
            } catch {
                let reason = (error as? IntegrationError)?.userMessage ?? error.localizedDescription
                speak(BuddyVoice.notionUpdateFailed(reason), .acknowledge)
            }
        }
    }

    func skipNotionCompletion() {
        pendingNotionCompletion = nil
    }

    /// One timer for the next reminder, rather than polling.
    private func scheduleMeetingReminder() {
        reminderTimer?.invalidate()
        notifications.cancel(prefix: "meeting.")
        let lead = TimeInterval(calendar.reminderMinutes * 60)
        guard calendar.isConnected, lead > 0 else { return }
        let now = Date.now
        guard let next = calendar.schedule.events.first(where: {
            $0.start > now && !remindedEventIDs.contains($0.id)
        }) else { return }
        let fireAt = max(now.addingTimeInterval(1), next.start.addingTimeInterval(-lead))
        notifications.schedule(id: "meeting.\(next.id)", title: next.title,
                               body: "Starts at \(next.start.formatted(date: .omitted, time: .shortened)).", at: fireAt)
        reminderTimer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.remind(next) }
        }
        reminderTimer?.tolerance = 2
        RunLoop.main.add(reminderTimer!, forMode: .common)
    }

    private func remind(_ event: CalendarEvent) {
        remindedEventIDs.insert(event.id)
        let minutes = max(0, Int((event.start.timeIntervalSinceNow / 60).rounded()))
        bark()
        // A clear reason to speak up, even during focus.
        speak(BuddyVoice.meetingSoon(event.title, minutes: minutes), .important)
        scheduleMeetingReminder()
    }

    // MARK: - Intents (called by views and menus)

    func buddyClicked() {
        character.react(.poke)
        if isUserAway { userAwayChanged(false) }
        // A hello when you open her panel — not when closing it, not during focus.
        if !isPanelOpen, !focus.isFocusing { bark(minimumGap: 10) }
        setPanelOpen(!isPanelOpen)
    }

    /// Called over with the call key: she wakes up if she was dozing, and the panel
    /// closes since she's leaving it behind.
    func buddyCalled() {
        if isUserAway { userAwayChanged(false) }
        setPanelOpen(false)
    }

    /// One bark, with Coco's mouth in sync. Rate-limited so she's never yappy;
    /// silent when sounds are muted (the mouth still moves).
    func bark(minimumGap: TimeInterval = 1.5) {
        let now = Date.now
        guard now.timeIntervalSince(lastBarkAt) >= minimumGap else { return }
        lastBarkAt = now
        character.react(.bark)
        sounds.play(.bark)
    }

    func setPanelOpen(_ open: Bool) {
        windows?.setPanelOpen(open)
    }

    func openPanel(_ tab: PanelTab? = nil) {
        if let tab { panelTab = tab }
        setPanelOpen(true)
    }

    /// Called by the panel controller after it actually opened or closed.
    func panelDidChange(open: Bool) {
        isPanelOpen = open
        if open {
            panelOpenCount += 1
            character.dismissSpeech()
            character.react(.perk)
        }
    }

    @discardableResult
    func addTask(_ text: String) -> Bool {
        tasks.add(text: text)
    }

    func toggleTask(_ id: BuddyTask.ID) {
        tasks.toggle(id)
    }

    func removeTask(_ id: BuddyTask.ID) {
        tasks.remove(id)
    }

    /// The one task Coco would suggest right now, and why.
    var upNext: (task: BuddyTask, reason: DayPlanner.Reason)? {
        let today = tasks.today()
        guard let pick = DayPlanner.suggestion(from: today, now: .now),
              let task = today.first(where: { $0.id == pick.taskID }) else { return nil }
        return (task, pick.reason)
    }

    func toggleEditing(_ id: BuddyTask.ID) {
        editingTaskID = editingTaskID == id ? nil : id
    }

    func carryOverLeftovers() {
        let count = tasks.leftovers.count
        tasks.carryOverLeftovers()
        character.react(.nod)
        speak(count == 1 ? "Brought it over to today." : "Brought \(count) over to today.", .acknowledge)
    }

    func letGoOfLeftovers() {
        tasks.letGoOfLeftovers()
        speak("Let them go. Fresh start.", .acknowledge)
    }

    func undoRemove() {
        guard let task = recentlyRemoved else { return }
        tasks.restore(task)
        recentlyRemoved = nil
    }

    /// From a task row: focus on this task (or switch the running session to it).
    func focus(on taskID: BuddyTask.ID) {
        if focus.timer.isActive, focus.timer.phase == .focus {
            focus.selectTask(taskID)
            speak("Switched focus to “\(BuddyVoice.short(tasks.task(taskID)?.title ?? ""))”.", .acknowledge)
        } else {
            focus.start(.focus, taskID: taskID)
        }
    }

    /// The Start button on the Focus tab.
    func startSelectedPhase() {
        focus.start(focus.timer.phase, taskID: focus.timer.taskID)
    }

    func startNextPhase() {
        focus.start(focus.suggestedNextPhase, taskID: focus.timer.taskID)
    }

    func skipNextPhase() {
        focus.acknowledge(preparing: .focus)
        completionPrompt = nil
    }

    func confirmTaskDone(_ id: BuddyTask.ID) {
        tasks.setCompleted(id, true)
        completionPrompt = nil
    }

    func dismissCompletionPrompt() {
        completionPrompt = nil
    }

    func resetPosition() {
        windows?.resetPosition()
    }

    /// Plays a state for a few seconds — for the "Animation Preview" menu and demos.
    func preview(_ state: CharacterState) {
        switch state {
        case .talking:
            character.say("Testing, testing. Is this thing on?")
        case .sleeping:
            character.play(.sleeping, for: 6)
        default:
            character.play(state, for: 4)
        }
    }

    // MARK: - Voice input

    /// Mic button / "Talk to Coco": start listening, or stop and use what was heard.
    func toggleListening() {
        if voiceIn.isListening {
            voiceIn.finish()
            return
        }
        // Never let the microphone hear Coco's own voice.
        voiceOut.stop()
        character.dismissSpeech()
        taskDrafts = []
        Task {
            await voiceIn.start()
            switch voiceIn.status {
            case .listening: buddyLine = BuddyVoice.listening
            case .denied, .unavailable: speak(BuddyVoice.micUnavailable, .acknowledge)
            default: break
            }
        }
    }

    func talkToBuddy() {
        openPanel(.today)
        if !voiceIn.isListening { toggleListening() }
    }

    func addTaskDrafts() {
        let results = taskDrafts.map {
            QuickAddParser.Result(title: $0.title, priority: $0.priority, estimateMinutes: $0.estimateMinutes)
        }
        taskDrafts = []
        let added = tasks.add(results)
        if draftOrigin == .chat {
            assistant.note(added == 0 ? "The suggested tasks were already on the list; nothing new was added."
                           : "The user reviewed the suggested tasks and added \(added) to their list.")
        }
        if added == 0 { speak("Those are already on your list.", .acknowledge) }
    }

    func discardTaskDrafts() {
        if draftOrigin == .chat { assistant.note("The user discarded the suggested tasks.") }
        taskDrafts = []
    }

    private func handleTranscript(_ transcript: String) {
        // In the Chat tab, speech is a chat message.
        if panelTab == .chat, assistant.isReady, !transcript.isEmpty {
            assistant.send(transcript)
            return
        }
        character.play(.thinking, for: 0.6)
        switch VoiceCommandParser.parse(transcript) {
        case .nothing:
            speak(BuddyVoice.heardNothing, .acknowledge)
        case .addTasks(let heard):
            panelTab = .today
            draftOrigin = .voice
            taskDrafts = heard.map(TaskDraft.init)
            speak(BuddyVoice.heardTasks(heard.count), .acknowledge)
        case .startFocus(let hint):
            var taskID = focus.timer.taskID
            if let hint {
                taskID = matchTask(hint)
                if taskID == nil { speak(BuddyVoice.noMatchingTask(hint), .acknowledge) }
            }
            if focus.timer.isActive, focus.timer.phase == .focus {
                focus.selectTask(taskID)
            } else {
                focus.start(.focus, taskID: taskID)
            }
        case .startBreak:
            let next = focus.suggestedNextPhase
            focus.start(next == .focus ? .shortBreak : next)
        case .pause:
            if focus.timer.isRunning { focus.pause(); speak(BuddyVoice.paused, .acknowledge) }
            else { speak(BuddyVoice.nothingToControl, .acknowledge) }
        case .resume:
            if focus.timer.isPaused { focus.resume(); speak(BuddyVoice.resumed, .acknowledge) }
            else { speak(BuddyVoice.nothingToControl, .acknowledge) }
        case .whatsNext:
            if let next = upNext {
                speak(BuddyVoice.upNext(next.task.title, reason: next.reason), .acknowledge)
            } else {
                speak(BuddyVoice.nothingNext, .acknowledge)
            }
        case .stop:
            if focus.timer.isActive { focus.stop(); speak(BuddyVoice.stopped, .acknowledge) }
            else { speak(BuddyVoice.nothingToControl, .acknowledge) }
        }
    }

    /// The open task whose title best matches a spoken hint, if any matches well enough.
    private func matchTask(_ hint: String) -> BuddyTask.ID? {
        let ignored: Set<String> = ["the", "a", "an", "my", "on", "for", "to", "of", "and"]
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)).subtracting(ignored)
        }
        let wanted = words(hint)
        guard !wanted.isEmpty else { return nil }
        let scored = tasks.openToday.map { task in
            (task, Double(wanted.intersection(words(task.title)).count) / Double(wanted.count))
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 else { return nil }
        return best.0.id
    }

    // MARK: - Assistant actions

    /// Carries out a validated assistant tool call. Results say exactly what happened,
    /// so the assistant never reports something that didn't.
    private func perform(_ action: AssistantAction) async -> AssistantService.ToolOutcome {
        switch action {
        case .getToday:
            let timer = focus.timer
            let focusState = timer.isActive
                ? "\(timer.phase.label.lowercased()) \(timer.isPaused ? "paused" : "running"), \(Self.clock(focus.remaining)) left"
                    + (tasks.task(timer.taskID).map { " on “\($0.title)”" } ?? "")
                : "not running (default focus length \(preferences.focusSettings.focusMinutes) min)"
            let text = AssistantPrompt.today(
                tasks: tasks.today(), focus: .init(focusState), focusedMinutesToday: focusLog.today.minutes,
                calendarConnected: calendar.isConnected,
                events: calendar.schedule.events + calendar.schedule.allDayEvents, now: .now,
                workdayEndHour: preferences.workdayEndHour)
            return .init(result: text, activity: calendar.isConnected ? "Looked at your tasks and calendar" : "Looked at your tasks")

        case .proposeTasks(let proposals):
            draftOrigin = .chat
            taskDrafts = proposals.map(TaskDraft.init)
            let count = proposals.count
            return .init(result: "Showing \(count) draft task\(count == 1 ? "" : "s") to the user for review. Nothing is added until they confirm.",
                         activity: "Suggested \(count) task\(count == 1 ? "" : "s") — review below")

        case .startFocus(let id, let minutes):
            var taskID: UUID?
            if let id {
                guard let uuid = UUID(uuidString: id), let task = tasks.task(uuid), !task.isCompleted else {
                    return .init(result: "No open task has id \(id). Call get_today for current ids.", isError: true)
                }
                taskID = uuid
            }
            if focus.timer.isActive {
                return .init(result: "Not started: a \(focus.timer.phase.label.lowercased()) session is already running (\(Self.clock(focus.remaining)) left).", isError: true)
            }
            focusStartedFromChat = true
            focus.start(.focus, taskID: taskID, minutes: minutes)
            let length = Int((focus.timer.duration / 60).rounded())
            let on = tasks.task(taskID).map { " on “\($0.title)”" } ?? ""
            return .init(result: "Focus timer started: \(length) minutes\(on).", activity: "Started a \(length)-min focus\(on)")

        case .requestCompletion(let id):
            guard let uuid = UUID(uuidString: id), let task = tasks.task(uuid) else {
                return .init(result: "No task has id \(id). Call get_today for current ids.", isError: true)
            }
            if task.isCompleted { return .init(result: "“\(task.title)” is already marked done.") }
            if !pendingCompletions.contains(uuid) { pendingCompletions.append(uuid) }
            return .init(result: "Asked the user to confirm marking “\(task.title)” done. It is NOT done unless they confirm.",
                         activity: "Asked you to confirm “\(BuddyVoice.short(task.title))”")
        }
    }

    func confirmCompletion(_ id: BuddyTask.ID) {
        pendingCompletions.removeAll { $0 == id }
        guard let task = tasks.task(id) else { return }
        tasks.setCompleted(id, true)
        assistant.note("The user confirmed: “\(task.title)” is now marked done.")
    }

    func declineCompletion(_ id: BuddyTask.ID) {
        pendingCompletions.removeAll { $0 == id }
        if let task = tasks.task(id) { assistant.note("The user said “\(task.title)” isn't done yet.") }
    }

    // MARK: - Speaking

    /// Whether lines are also spoken aloud right now.
    private var voiceAudible: Bool {
        preferences.voiceEnabled && !preferences.soundsMuted && !voiceIn.isListening
    }

    func speak(_ text: String, _ importance: Importance) {
        buddyLine = text
        if isPanelOpen {
            if voiceAudible { voiceOut.speak(text) } else { character.mouthAlong(text) }
            return
        }
        let interactive = preferences.presence == .interactive
        switch importance {
        case .ambient:
            guard interactive, !focus.isFocusing, !isUserAway else { return }
        case .acknowledge:
            guard interactive, !focus.isFocusing else { return }
        case .important:
            break
        }
        guard preferences.isBuddyVisible else { return }
        character.say(text)
        if voiceAudible { voiceOut.speak(text) }
    }

    private func greetOncePerDay() {
        let today = Date().formatted(.iso8601.year().month().day())
        guard preferences.lastGreetingDay != today, !focus.timer.isActive else { return }
        preferences.lastGreetingDay = today
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if preferences.presence == .interactive { bark() }
            speak(BuddyVoice.greeting(), .ambient)
        }
    }

    // MARK: - Event handling

    private func handle(_ event: TaskStore.Event) {
        switch event {
        case .added(let task):
            character.react(.nod)
            speak(BuddyVoice.taskAdded(task.title, openCount: tasks.openToday.count), .acknowledge)

        case .addedBatch(let count):
            character.react(.perk)
            speak(BuddyVoice.addedTasks(count), .acknowledge)

        case .duplicate(let task):
            speak(BuddyVoice.duplicate(task.title), .acknowledge)

        case .completed(let task):
            pendingCompletions.removeAll { $0 == task.id }
            let remaining = tasks.openToday.count
            if focus.isFocusing {
                // Mid-focus: a quiet pop, no barking.
                sounds.play(.taskDone)
                if preferences.focusPresentation == .quiet { character.react(.nod) } else { character.play(.celebrating, for: 1.6) }
            } else {
                character.play(.celebrating, for: remaining == 0 ? 2.6 : 1.6)
                bark()
            }
            if completionPrompt == task.id { completionPrompt = nil }
            if Features.notion, task.external?.source == .notion, let mapping = notion.mapping,
               mapping.writeBackEnabled, mapping.canWriteCompletion, notion.isConnected {
                pendingNotionCompletion = task
                speak(BuddyVoice.askNotionCompletion, .acknowledge)
            } else {
                speak(BuddyVoice.taskCompleted(remaining: remaining), .acknowledge)
            }

        case .reopened(let task):
            character.react(.nod)
            if pendingNotionCompletion?.id == task.id { pendingNotionCompletion = nil }

        case .removed(let task):
            if editingTaskID == task.id { editingTaskID = nil }
            if focus.timer.taskID == task.id { focus.selectTask(nil) }
            if completionPrompt == task.id { completionPrompt = nil }
            recentlyRemoved = task
            undoExpiry?.cancel()
            undoExpiry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.recentlyRemoved = nil
            }
        }
    }

    private func handle(_ event: FocusController.Event) {
        switch event {
        case .started(let phase, let taskID):
            sounds.play(.sessionStart)
            completionPrompt = nil
            let minutes = preferences.focusSettings.minutes(for: phase)
            if phase == .focus, focusStartedFromChat {
                // Started from the chat: the reply acknowledges it, and the panel stays open.
                focusStartedFromChat = false
                character.react(.nod)
            } else if phase == .focus {
                character.react(.nod)
                let line = BuddyVoice.focusStarted(task: tasks.task(taskID)?.title, minutes: minutes)
                // Minimise distractions: tuck the panel away, acknowledge once, then go quiet.
                Task {
                    try? await Task.sleep(for: .seconds(0.35))
                    setPanelOpen(false)
                    speak(line, .important)
                }
            } else {
                speak(BuddyVoice.breakStarted(minutes: minutes), .acknowledge)
            }

        case .paused, .resumed:
            character.react(.nod)

        case .stopped(let phase, let elapsed, let taskID):
            if phase == .focus {
                focusLog.record(taskID: taskID, seconds: elapsed, finished: false)
                if let taskID { tasks.logFocus(minutes: Int(elapsed / 60), for: taskID) }
            }

        case .finished(let phase, let duration, let taskID, let whileAway):
            let minutes = Int((duration / 60).rounded())
            let task = tasks.task(taskID)
            if phase == .focus {
                focusLog.record(taskID: taskID, seconds: duration, finished: true)
            }
            if phase == .focus, let task {
                tasks.logFocus(minutes: minutes, for: task.id)
                if !task.isCompleted { completionPrompt = task.id }
            }
            panelTab = .focus
            if whileAway {
                buddyLine = BuddyVoice.endedWhileAway(phase.label)
                return
            }
            if phase == .focus {
                // Time's up — Coco tells you herself.
                bark()
                character.play(.celebrating, for: 2.6)
                speak(BuddyVoice.focusFinished(minutes: minutes, task: task?.title), .important)
            } else {
                sounds.play(.sessionEnd)
                character.react(.perk)
                speak(BuddyVoice.breakFinished(), .important)
            }
        }
    }

    private func userAwayChanged(_ away: Bool) {
        guard away != isUserAway else { return }
        isUserAway = away
        if !away { character.react(.perk) }
    }

    // MARK: - Character presentation

    struct CharacterSync: Equatable {
        var base: CharacterState
        var scale: CGFloat
        var dimmed: Bool
        var progress: Double?
        var countdown: CharacterModel.Countdown?
        var followsCursor: Bool
    }

    /// Everything about how the buddy should look right now, derived from app state.
    var characterSync: CharacterSync {
        let timer = focus.timer
        let focusing = timer.isActive && timer.phase == .focus
        let base: CharacterState = voiceIn.isListening ? .listening
            : timer.isRunning && timer.phase == .focus ? .focused
            : isUserAway ? .sleeping : .idle
        let compact = preferences.presence == .compact
            || (focusing && preferences.focusPresentation == .smaller)
        let quiet = focusing && preferences.focusPresentation == .quiet
        let countdown = timer.isActive
            ? CharacterModel.Countdown(text: Self.clock(focus.remaining), isBreak: timer.phase.isBreak, isPaused: timer.isPaused)
            : nil
        return CharacterSync(
            base: base,
            scale: compact ? CharacterLayout.compactScale : 1,
            dimmed: quiet,
            progress: focusing ? focus.progress : nil,
            countdown: countdown,
            followsCursor: preferences.presence == .interactive && !quiet
        )
    }

    private func apply(_ sync: CharacterSync) {
        character.setBaseState(sync.base)
        if character.scale != sync.scale { character.scale = sync.scale }
        if character.isDimmed != sync.dimmed { character.isDimmed = sync.dimmed }
        if character.focusProgress != sync.progress { character.focusProgress = sync.progress }
        if character.countdown != sync.countdown { character.countdown = sync.countdown }
    }

    /// "24:59", or "1:04:59" for long sessions. Rounds up so a fresh 25-minute timer reads 25:00.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
