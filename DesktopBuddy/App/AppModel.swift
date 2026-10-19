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
    /// Calendar.app's calendars, read-only, through EventKit.
    let appleCalendar: AppleCalendarService
    /// The user's Partiful events (read-only), from their personal calendar link.
    let partiful: PartifulFeedService
    let notion: NotionService
    let assistant: AssistantService
    /// Every connected calendar as one schedule, duplicates merged. The Today card, week
    /// browser, reminders and chat read this; changes go to the Google service itself.
    let agenda: Agenda
    let character = CharacterModel()
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

    /// The day the week browser shows. Kept while you switch tabs or chat.
    private(set) var scheduleDay = Calendar.current.startOfDay(for: .now)
    /// The Today card's calendar is opened out into the week browser.
    var scheduleExpanded = false {
        didSet { if scheduleExpanded { agenda.prefetch(around: scheduleDay) } }
    }
    /// Event changes the assistant proposed — nothing happens to the calendar unless confirmed.
    private(set) var eventRequests: [EventRequest] = []

    struct EventRequest: Identifiable, Equatable {
        enum Kind: Equatable {
            case create(EventDraft)
            case change(CalendarEvent, EventChanges)
            case delete(CalendarEvent)
        }
        enum State: Equatable { case waiting, working, failed(String), done(String) }
        let id = UUID()
        var kind: Kind
        /// Busy events the proposed time would overlap.
        var conflicts: [CalendarEvent]
        var state: State = .waiting

        /// A card, not yet done, adding an event from this invitation.
        func isCreating(from sourceKey: String) -> Bool {
            guard case .create(let draft) = kind, draft.source?.key == sourceKey else { return false }
            switch state {
            case .waiting, .working, .failed: return true
            case .done: return false
            }
        }
    }

    /// What the next meeting reminder depends on.
    private struct ReminderBasis: Equatable, Sendable {
        var schedule: DaySchedule
        var minutes: Int
    }

    /// Working hours for open time and slot finding.
    var workingHours: WorkingHours {
        WorkingHours(startHour: preferences.workdayStartHour, endHour: preferences.workdayEndHour)
    }

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
    @ObservationIgnored private var reminderBasis: ReminderBasis?
    // What she's been up to lately, so her comments fit (and she doesn't ask for attention
    // right after getting some). Kept in memory only.
    @ObservationIgnored private var lastSpokeAt = Date.now
    @ObservationIgnored private var lastTogetherAt = Date.now
    @ObservationIgnored private var recentTreats: [Date] = []
    @ObservationIgnored private var recentFetches: [Date] = []
    @ObservationIgnored private var nextChatterAt = Date.now.addingTimeInterval(AppModel.chatterGap.lowerBound)
    @ObservationIgnored private var chatterTimer: Timer?
    @ObservationIgnored private let eventLinks = EventLinkReader()
    /// How long she stays quiet between unprompted comments.
    static let chatterGap: ClosedRange<TimeInterval> = 25 * 60...45 * 60

    /// - Parameter preview: in-memory stores and throwaway defaults, for snapshots.
    init(preview: Bool = false) {
        preferences = preview ? Preferences(defaults: UserDefaults(suiteName: "DesktopBuddy.preview")!) : Preferences()
        notifications = NotificationService()
        tasks = TaskStore(persistent: !preview)
        focus = FocusController(preferences: preferences, notifications: notifications, persistent: !preview)
        focusLog = FocusLogStore(persistent: !preview)
        calendar = GoogleCalendarService(persistent: !preview)
        partiful = PartifulFeedService(persistent: !preview)
        appleCalendar = preview ? AppleCalendarService(reader: NoAppleCalendar(), defaults: UserDefaults(suiteName: "DesktopBuddy.preview")!)
            : AppleCalendarService()
        agenda = Agenda(sources: [calendar, appleCalendar, partiful])
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
        assistant.viewingDay = { [weak self] in
            guard let self, self.scheduleExpanded else { return nil }
            return self.scheduleDay
        }
        assistant.onChatCleared = { [weak self] in self?.eventRequests = [] }
        assistant.mayShare = { [weak self] in self?.hasAIConsent ?? false }
        assistant.onPhaseChanged = { [weak self] phase in
            switch phase {
            case .idle: self?.character.release()
            case .waiting, .usingTools: self?.character.hold(.thinking)
            case .writing: self?.character.hold(.talking)
            }
        }
        voiceIn.onFinish = { [weak self] transcript in self?.handleTranscript(transcript) }

        track({ [weak self] in self?.characterSync }) { [weak self] sync in
            guard let self, let sync else { return }
            self.apply(sync)
        }
        presence.start()
        focus.restoreAfterLaunch()
        greetOncePerDay()
        startChatter()
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
        partiful.disconnect()
        appleCalendar.eraseAll()
        focus.eraseAll()
        focusLog.eraseAll()
        tasks.eraseAll()
        taskDrafts = []
        pendingCompletions = []
        eventRequests = []
        scheduleExpanded = false
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
        // One reminder timer, set again whenever today's merged schedule or the lead time changes.
        track({ [weak self] in self.map { ReminderBasis(schedule: $0.agenda.schedule, minutes: $0.calendar.reminderMinutes) } }) { [weak self] basis in
            guard let self, let basis, basis != self.reminderBasis else { return }
            self.reminderBasis = basis
            self.scheduleMeetingReminder()
        }
        calendar.startAutoRefresh()
        partiful.start()
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
                // If the week browser was on "today", it moves on with the date.
                if let self, self.scheduleDay < Calendar.current.startOfDay(for: .now) { self.showScheduleDay(.now) }
                self?.refreshConnections()
            }
        }
        refreshConnections()
    }

    /// Calendar, Notion candidates and linked tasks — each only if connected.
    func refreshConnections() {
        Task {
            await agenda.refresh()
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
        guard agenda.isConnected, lead > 0 else { return }
        let now = Date.now
        // Merged events: a meeting in two calendars is reminded once, whichever id it shows under.
        guard let next = agenda.schedule.events.first(where: {
            $0.start > now && remindedEventIDs.isDisjoint(with: $0.allIDs)
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
        remindedEventIDs.formUnion(event.allIDs)
        let minutes = max(0, Int((event.start.timeIntervalSinceNow / 60).rounded()))
        bark()
        // A clear reason to speak up, even during focus.
        speak(BuddyVoice.meetingSoon(event.title, minutes: minutes), .important)
        scheduleMeetingReminder()
    }

    // MARK: - Intents (called by views and menus)

    func buddyClicked() {
        lastTogetherAt = .now
        character.react(.poke)
        if isUserAway { userAwayChanged(false) }
        // A hello when you open her panel — not when closing it, not during focus.
        if !isPanelOpen, !focus.isFocusing { bark(minimumGap: 10) }
        setPanelOpen(!isPanelOpen)
    }

    /// Called over with the call key: she wakes up if she was dozing, and the panel
    /// closes since she's leaving it behind.
    func buddyCalled() {
        lastTogetherAt = .now
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

    // MARK: - Sharing with Anthropic

    /// The user has allowed the chat to send what it needs to Anthropic (see `AIConsent`).
    var hasAIConsent: Bool { preferences.aiConsentVersion >= AIConsent.version }

    func allowAIChat() {
        preferences.aiConsentVersion = AIConsent.version
    }

    /// Turns sharing off: any reply in progress stops and the conversation is forgotten.
    func revokeAIChat() {
        preferences.aiConsentVersion = 0
        assistant.stop()
        assistant.newChat()
    }

    /// She's eaten a treat you tossed and sat back down.
    func treatEaten() {
        let now = Date.now
        recentTreats = recentTreats.filter { now.timeIntervalSince($0) < 10 * 60 } + [now]
        lastTogetherAt = now
        speak(BuddyVoice.line(recentTreats.count > 1 ? .treatAgain : .treatReceived), .acknowledge)
        assistant.note(recentTreats.count > 1
                       ? "The user has tossed \(Buddy.name) \(recentTreats.count) treats in the last few minutes"
                       : "The user just tossed \(Buddy.name) a treat, and she ate it", key: "treat")
    }

    /// She's brought the ball back.
    func fetchFinished() {
        let now = Date.now
        recentFetches = recentFetches.filter { now.timeIntervalSince($0) < 10 * 60 } + [now]
        lastTogetherAt = now
        speak(BuddyVoice.line(recentFetches.count > 1 ? .fetchAgain : .fetchCompleted), .acknowledge)
        assistant.note(recentFetches.count > 1
                       ? "The user and \(Buddy.name) have played \(recentFetches.count) rounds of fetch in the last few minutes"
                       : "The user just played fetch with \(Buddy.name), and she brought the ball back", key: "fetch")
    }

    // MARK: - Chatter

    /// Now and then — every half hour or so, and only when nothing else is going on — she
    /// says something on her mind. Never during focus or a meeting, never while you're away.
    private func startChatter() {
        chatterTimer?.invalidate()
        chatterTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.chatterTick() }
        }
    }

    private func chatterTick() {
        let now = Date.now
        guard now >= nextChatterAt else { return }
        guard preferences.chatterEnabled, preferences.presence == .interactive, preferences.isBuddyVisible,
              !isUserAway, !isPanelOpen, !focus.timer.isActive, !voiceIn.isListening, character.speech == nil,
              !inMeeting(at: now),
              now.timeIntervalSince(lastSpokeAt) >= Self.chatterGap.lowerBound,
              now.timeIntervalSince(lastTogetherAt) >= 10 * 60
        else { return }
        nextChatterAt = now.addingTimeInterval(.random(in: Self.chatterGap))
        let hour = Calendar.current.component(.hour, from: now)
        let moment = LinePicker.Moment(
            now: now, hour: hour,
            recentlyTogether: now.timeIntervalSince(lastTogetherAt) < 30 * 60,
            recentlyPlayed: recentFetches.last.map { now.timeIntervalSince($0) < 30 * 60 } ?? false,
            recentlyFed: recentTreats.last.map { now.timeIntervalSince($0) < 30 * 60 } ?? false,
            working: (preferences.workdayStartHour..<preferences.workdayEndHour).contains(hour))
        speak(BuddyVoice.idleLine(moment), .ambient)
    }

    private func inMeeting(at now: Date) -> Bool {
        agenda.events(on: now)?.contains { !$0.isAllDay && $0.isBusy && $0.start <= now && $0.end > now } ?? false
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
            // A hello when you come to see her, unless she's said something recently.
            if !focus.isFocusing, Date.now.timeIntervalSince(lastSpokeAt) > 3 * 60 {
                speak(BuddyVoice.line(.petted), .acknowledge)
            }
            // Pick up changes made in Google Calendar since the last look (stale weeks only).
            agenda.prefetch(around: .now)
            if scheduleExpanded { agenda.prefetch(around: scheduleDay) }
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
        if panelTab == .chat, assistant.isReady, hasAIConsent, !transcript.isEmpty {
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
            var problems: [String] = []
            var upcoming: [CalendarEvent] = []
            if agenda.isConnected {
                // Today and the week ahead, so "what's next" works after today's last meeting.
                let now = Date.now
                do {
                    problems = try await agenda.load(from: now, to: now.addingTimeInterval(7 * 86_400))
                } catch {
                    problems = [(error as? IntegrationError)?.userMessage ?? error.localizedDescription]
                }
                upcoming = agenda.comingUp(after: now, limit: 3)
            }
            let schedule = agenda.schedule
            let text = AssistantPrompt.today(
                tasks: tasks.today(), focus: .init(focusState), focusedMinutesToday: focusLog.today.minutes,
                calendarConnected: agenda.isConnected,
                events: schedule.events + schedule.allDayEvents, now: .now,
                workdayEndHour: preferences.workdayEndHour,
                sources: agenda.isConnected ? agenda.connectedNames : nil, problems: problems, upcoming: upcoming)
            return .init(result: text, activity: agenda.isConnected ? "Looked at your tasks and calendar" : "Looked at your tasks")

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

        case .getSchedule, .findFreeTime, .findEvents, .proposeEvent, .proposeEventChange, .proposeEventDeletion:
            return await performCalendar(action)

        case .readEventLink(let url):
            switch await eventLinks.read(url) {
            case .success(let event):
                return .init(result: AssistantPrompt.linkedEvent(event, now: .now),
                             activity: "Read the Partiful invite “\(BuddyVoice.short(event.title))”")
            case .failure(let failure):
                // A private or locked invite the user is on: their own Partiful calendar has it.
                if let id = Self.partifulID(in: url), let mine = partiful.event(partifulID: id) {
                    let event = LinkedEvent(id: id, url: Partiful.canonicalURL(id: id), title: mine.title, start: mine.start,
                                            end: mine.endListed ? mine.end : nil, address: mine.location,
                                            description: mine.description.map(Self.withoutPartifulBoilerplate))
                    return .init(result: "The public page couldn't be read, but this event is in the user's own Partiful calendar:\n"
                                 + AssistantPrompt.linkedEvent(event, now: .now),
                                 activity: "Found “\(BuddyVoice.short(mine.title))” in your Partiful calendar")
                }
                return .init(result: failure.explanation, isError: true, activity: "Couldn't read the Partiful link")
            }
        }
    }

    // MARK: - Calendar (chat)

    private func performCalendar(_ action: AssistantAction) async -> AssistantService.ToolOutcome {
        let cal = Calendar.current
        guard agenda.isConnected else {
            return .init(result: "No calendar is connected (Google Calendar or Apple Calendar), so you can't see or change "
                         + "their schedule. They can connect one in Connections.", isError: true)
        }
        // A calendar that couldn't be read is reported, not hidden: the answer may be incomplete.
        var partial = ""
        func load(_ from: Date, _ to: Date) async -> String? {
            do {
                let problems = try await agenda.load(from: from, to: to)
                if !problems.isEmpty {
                    partial = "\n(Incomplete — couldn't read " + problems.joined(separator: "; ") + ". Tell the user.)"
                }
                return nil
            } catch let error as IntegrationError {
                return "Couldn't load the calendar: \(error.userMessage)"
            } catch {
                return "Couldn't load the calendar."
            }
        }
        func days(_ from: Date, _ to: Date) -> [Date] {
            var list: [Date] = []
            var day = from
            while day <= to, list.count < 31 {
                list.append(day)
                guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
            return list
        }
        func events(_ days: [Date]) -> [CalendarEvent] {
            var seen = Set<String>()
            return days.flatMap { agenda.events(on: $0) ?? [] }.filter { seen.insert($0.id).inserted }
        }

        switch action {
        case .getSchedule(let from, let to):
            guard let start = from.date(in: cal), let end = to.date(in: cal) else {
                return .init(result: "Those aren't real dates.", isError: true)
            }
            if let problem = await load(start, end) { return .init(result: problem, isError: true) }
            let range = days(start, end)
            let text = AssistantPrompt.schedule(days: range, events: events(range), hours: workingHours, now: .now, calendar: cal)
            let label = range.count == 1 ? Self.shortDay(start) : "\(Self.shortDay(start))–\(Self.shortDay(end))"
            return .init(result: text + partial, activity: "Looked at your calendar for \(label)")

        case .findFreeTime(let request):
            guard let start = request.from.date(in: cal), let end = request.to.date(in: cal) else {
                return .init(result: "Those aren't real dates.", isError: true)
            }
            if let problem = await load(start, end) { return .init(result: problem, isError: true) }
            let range = days(start, end)
            let hours = WorkingHours(start: request.earliest?.minutes ?? workingHours.start, end: request.latest?.minutes ?? workingHours.end)
            let slots = Availability.slots(duration: TimeInterval(request.durationMinutes * 60), days: range, events: events(range),
                                           hours: hours, notBefore: .now, calendar: cal)
            return .init(result: AssistantPrompt.freeTime(slots: slots, durationMinutes: request.durationMinutes,
                                                          from: start, to: end, hours: hours, calendar: cal) + partial,
                         activity: "Looked for \(request.durationMinutes) free minutes")

        case .findEvents(let query, let daysAhead, let limit):
            let now = Date.now
            let start = cal.startOfDay(for: now)
            guard let end = cal.date(byAdding: .day, value: daysAhead, to: start) else {
                return .init(result: "That range doesn't work.", isError: true)
            }
            if let problem = await load(start, end) { return .init(result: problem, isError: true) }
            let found = events(days(start, end))
                .filter { event in event.end > now && (query.map { CalendarSearch.matches(event, query: $0) } ?? true) }
                .sorted { $0.start < $1.start }
                .prefix(limit)
            return .init(result: AssistantPrompt.foundEvents(Array(found), query: query, through: end, now: now, calendar: cal) + partial,
                         activity: query.map { "Searched your calendar for “\(BuddyVoice.short($0))”" } ?? "Looked at what's coming up")

        case .proposeEvent(let proposal):
            guard calendar.isConnected else {
                return .init(result: "New events can only be added to Google Calendar, which isn't connected. Coco reads "
                             + "\(agenda.connectedNames) but can't add to it — they can add the event in that app.", isError: true)
            }
            guard let day = proposal.date.date(in: cal) else { return .init(result: "That isn't a real date.", isError: true) }
            let draft: EventDraft
            if proposal.allDay {
                draft = EventDraft(title: proposal.title, start: day, end: cal.date(byAdding: .day, value: 1, to: day) ?? day,
                                   isAllDay: true, location: proposal.location, notes: proposal.notes, source: proposal.source)
            } else {
                guard let time = proposal.start, let minutes = proposal.durationMinutes,
                      let start = cal.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) else {
                    return .init(result: "A start time and length are needed.", isError: true)
                }
                draft = EventDraft(title: proposal.title, start: start, end: start.addingTimeInterval(TimeInterval(minutes * 60)),
                                   location: proposal.location, notes: proposal.notes, source: proposal.source)
            }
            if !draft.isAllDay, draft.start < Date.now.addingTimeInterval(-60) {
                return .init(result: "That time has already passed — ask for a later one.", isError: true)
            }
            if let problem = await load(draft.start, draft.end) { return .init(result: problem, isError: true) }
            var nearby = events(days(cal.startOfDay(for: draft.start), draft.end))
            var duplicateNote = ""
            if let source = draft.source {
                // The same invitation, shared again: never a second card or a second event.
                if eventRequests.contains(where: { $0.isCreating(from: source.key) }) {
                    return .init(result: "A card to add this invitation is already waiting for the user to confirm — don't propose it again.",
                                 activity: "Already waiting for you to confirm")
                }
                if let existing = try? await calendar.events(fromSource: source.key).first {
                    return .init(result: "It's already on their calendar: “\(existing.title)” \(Self.describe(existing.start, existing.end, allDay: existing.isAllDay)) "
                                 + "(id \(existing.id)), added from this same link. Nothing new was proposed.",
                                 activity: "“\(BuddyVoice.short(existing.title))” is already on your calendar")
                }
                // The same invitation as Coco already shows it: from the Partiful import, maybe
                // merged with a copy Partiful synced into Google Calendar. Not a conflict with itself.
                let sameInvite = nearby.filter { $0.matchKeys.contains(source.key) || $0.allIDs.contains(source.key) }
                nearby.removeAll { event in sameInvite.contains { $0.id == event.id } }
                if let synced = sameInvite.first(where: { $0.references.contains { $0.provider == .google } }) {
                    return .init(result: "It's already in their Google Calendar: “\(synced.title)” \(Self.describe(synced.start, synced.end, allDay: synced.isAllDay)) "
                                 + "(the same Partiful invitation, synced there). Nothing new was proposed.",
                                 activity: "“\(BuddyVoice.short(synced.title))” is already on your calendar")
                }
                if let lookalike = Self.lookalike(of: draft, in: nearby) {
                    duplicateNote = " It may already be on their calendar as “\(lookalike.title)” "
                        + "\(Self.describe(lookalike.start, lookalike.end, allDay: lookalike.isAllDay)) (same name and time, perhaps added from Partiful) — "
                        + "point that out so they don't add it twice."
                }
                if !sameInvite.isEmpty {
                    duplicateNote += " It already shows in Coco from their Partiful import; adding it puts a copy in Google Calendar too."
                }
            }
            let conflicts = draft.isAllDay ? [] : Availability.conflicts(with: DateInterval(start: draft.start, end: draft.end), in: nearby)
            eventRequests.append(EventRequest(kind: .create(draft), conflicts: conflicts))
            return .init(result: "Showing the user “\(draft.title)” on \(Self.describe(draft.start, draft.end, allDay: draft.isAllDay)) to confirm."
                         + Self.conflictNote(conflicts) + duplicateNote
                         + " It is NOT created unless they confirm; the app will tell you if it was.",
                         activity: "Suggested adding “\(BuddyVoice.short(draft.title))” — confirm below")

        case .proposeEventChange(let change):
            let event: CalendarEvent
            switch changeTarget(change.eventID, verb: "changed") {
            case .success(let found): event = found
            case .failure(let refusal): return refusal.outcome
            }
            guard event.canEdit else {
                return .init(result: "“\(event.title)” is organised by someone else, so it can't be changed from here.", isError: true)
            }
            guard !event.isAllDay || (change.start == nil && change.durationMinutes == nil) else {
                return .init(result: "All-day events can only be renamed, moved to another date or have their location changed here.", isError: true)
            }
            var changes = EventChanges(title: change.title, location: change.location)
            if change.date != nil || change.start != nil || change.durationMinutes != nil {
                let day = change.date?.date(in: cal) ?? cal.startOfDay(for: event.start)
                let length = change.durationMinutes.map { TimeInterval($0 * 60) } ?? event.duration
                if event.isAllDay {
                    changes.start = day
                    changes.end = day.addingTimeInterval(event.duration)
                } else {
                    let clock = change.start.map { ($0.hour, $0.minute) }
                        ?? (cal.component(.hour, from: event.start), cal.component(.minute, from: event.start))
                    guard let start = cal.date(bySettingHour: clock.0, minute: clock.1, second: 0, of: day) else {
                        return .init(result: "That time doesn't exist on that day.", isError: true)
                    }
                    changes.start = start
                    changes.end = start.addingTimeInterval(length)
                }
            }
            var conflicts: [CalendarEvent] = []
            if let start = changes.start, let end = changes.end {
                if let problem = await load(start, end) { return .init(result: problem, isError: true) }
                if !event.isAllDay {
                    conflicts = Availability.conflicts(with: DateInterval(start: start, end: end),
                                                       in: events(days(cal.startOfDay(for: start), end)), ignoring: event.id)
                }
            }
            eventRequests.append(EventRequest(kind: .change(event, changes), conflicts: conflicts))
            var summary = "Showing the user the change to “\(event.title)” to confirm"
            if let start = changes.start, let end = changes.end {
                summary += ": from \(Self.describe(event.start, event.end, allDay: event.isAllDay)) to \(Self.describe(start, end, allDay: event.isAllDay))"
            }
            return .init(result: summary + "." + Self.conflictNote(conflicts) + Self.separateCopiesNote(event)
                         + " Nothing changes unless they confirm.",
                         activity: "Suggested changing “\(BuddyVoice.short(event.title))” — confirm below")

        case .proposeEventDeletion(let id):
            let event: CalendarEvent
            switch changeTarget(id, verb: "deleted") {
            case .success(let found): event = found
            case .failure(let refusal): return refusal.outcome
            }
            guard event.canEdit else {
                return .init(result: "“\(event.title)” is organised by someone else, so it can't be deleted from here.", isError: true)
            }
            eventRequests.append(EventRequest(kind: .delete(event), conflicts: []))
            return .init(result: "Asked the user to confirm deleting “\(event.title)” (\(Self.describe(event.start, event.end, allDay: event.isAllDay))). "
                         + Self.separateCopiesNote(event) + "It is NOT deleted unless they confirm.",
                         activity: "Asked you to confirm deleting “\(BuddyVoice.short(event.title))”")

        default:
            return .init(result: "Not a calendar action.", isError: true)
        }
    }

    private struct Refusal: Error {
        let outcome: AssistantService.ToolOutcome
    }

    /// The Google Calendar record to change for an event the chat named (by the id it was
    /// shown with, or any of its merged copies'). Apple Calendar and Partiful events are
    /// read-only here, so those are refused with where to change them instead.
    private func changeTarget(_ id: String, verb: String) -> Result<CalendarEvent, Refusal> {
        guard let shown = agenda.event(id: id) else {
            return .failure(Refusal(outcome: .init(result: "No event with id \(id) in the loaded calendar. Call get_schedule for that day first.",
                                                   isError: true)))
        }
        guard var record = agenda.googleRecord(for: shown, in: calendar) else {
            return .failure(Refusal(outcome: .init(result: "“\(shown.title)” is in \(shown.sourceLabel), which Coco can only read, so it can't be "
                                                   + "\(verb) from here. They can do it in \(shown.provider == .partiful ? "Partiful" : "the Calendar app").",
                                                   isError: true)))
        }
        // Remember the other copies so the card can say which ones won't change.
        record.alsoIn = shown.references.filter { $0.id != record.id }
        return .success(record)
    }

    /// Separate copies in other calendars (matched by details, not the same synced event)
    /// that a change to the Google event won't touch.
    static func separateCopiesNote(_ event: CalendarEvent) -> String {
        let copies = event.alsoIn.filter { $0.match == .details }
        guard !copies.isEmpty else { return "" }
        return " Only the Google Calendar event is affected — the separate copy in \(copies.map(\.label).joined(separator: " and ")) "
            + "stays as it is; the card tells the user."
    }

    /// Carries out a confirmed event change. The assistant hears what really happened.
    func confirmEventRequest(_ id: EventRequest.ID) {
        guard let index = eventRequests.firstIndex(where: { $0.id == id }), eventRequests[index].state != .working else { return }
        eventRequests[index].state = .working
        let request = eventRequests[index]
        Task {
            do {
                let outcome: String
                let day: Date
                switch request.kind {
                case .create(let draft):
                    // Shared twice and confirmed twice (or added meanwhile): don't make a second copy.
                    if let source = draft.source, let existing = try await calendar.events(fromSource: source.key).first {
                        outcome = "“\(existing.title)” was already on your calendar for \(Self.describe(existing.start, existing.end, allDay: existing.isAllDay)) — not added again"
                        day = existing.start
                    } else {
                        let event = try await calendar.create(draft, presentingFrom: nil)
                        outcome = "Added “\(event.title)” for \(Self.describe(event.start, event.end, allDay: event.isAllDay))"
                        day = event.start
                    }
                case .change(let event, let changes):
                    let updated = try await calendar.update(event, with: changes, presentingFrom: nil)
                    outcome = "Changed “\(updated.title)” to \(Self.describe(updated.start, updated.end, allDay: updated.isAllDay))"
                    day = updated.start
                case .delete(let event):
                    try await calendar.delete(event, presentingFrom: nil)
                    outcome = "Deleted “\(event.title)” (\(Self.describe(event.start, event.end, allDay: event.isAllDay)))"
                    day = event.start
                }
                setEventRequest(id, state: .done(outcome))
                showScheduleDay(day)
                assistant.note("Google Calendar confirmed: \(outcome).")
            } catch {
                let message = (error as? IntegrationError)?.userMessage ?? error.localizedDescription
                setEventRequest(id, state: .failed(message))
                assistant.note("The calendar change failed (\(message)). Nothing was changed.")
            }
        }
    }

    func declineEventRequest(_ id: EventRequest.ID) {
        guard let request = eventRequests.first(where: { $0.id == id }) else { return }
        eventRequests.removeAll { $0.id == id }
        let what: String
        switch request.kind {
        case .create(let draft): what = "adding “\(draft.title)”"
        case .change(let event, _): what = "changing “\(event.title)”"
        case .delete(let event): what = "deleting “\(event.title)”"
        }
        assistant.note("The user said no to \(what). Nothing was changed.")
    }

    func dismissEventRequest(_ id: EventRequest.ID) {
        eventRequests.removeAll { $0.id == id }
    }

    private func setEventRequest(_ id: EventRequest.ID, state: EventRequest.State) {
        guard let index = eventRequests.firstIndex(where: { $0.id == id }) else { return }
        eventRequests[index].state = state
    }

    // MARK: - Week browser

    func showScheduleDay(_ day: Date) {
        scheduleDay = Calendar.current.startOfDay(for: day)
        calendar.browsingWeek = calendar.weekStart(for: scheduleDay)
        agenda.prefetch(around: scheduleDay)
    }

    func moveScheduleDay(by days: Int) {
        guard let day = Calendar.current.date(byAdding: .day, value: days, to: scheduleDay) else { return }
        showScheduleDay(day)
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func describe(_ start: Date, _ end: Date, allDay: Bool) -> String {
        if allDay { return "\(shortDay(start)), all day" }
        let time = { (date: Date) in date.formatted(date: .omitted, time: .shortened) }
        return "\(shortDay(start)) \(time(start))–\(time(end))"
    }

    /// The Partiful event id in a link (or in text containing one); nil for short links.
    static func partifulID(in text: String) -> String? {
        let parsed = Partiful.link(from: text) ?? Partiful.links(in: text).first.flatMap { Partiful.link(from: $0.absoluteString) }
        if case .event(let id)? = parsed?.link { return id }
        return nil
    }

    /// Partiful's calendar descriptions start with "View this event on Partiful at <link>".
    static func withoutPartifulBoilerplate(_ description: String) -> String {
        guard description.hasPrefix("View this event on Partiful at ") else { return description }
        let rest = description.drop { $0 != "\n" }.trimmingCharacters(in: .whitespacesAndNewlines)
        return rest
    }

    /// An event on the calendar that's probably this one: the same name (ignoring case, emoji
    /// and punctuation) starting within half an hour.
    static func lookalike(of draft: EventDraft, in events: [CalendarEvent]) -> CalendarEvent? {
        func key(_ title: String) -> String {
            String(title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
        }
        let name = key(draft.title)
        guard !name.isEmpty else { return nil }
        return events.first { key($0.title) == name && abs($0.start.timeIntervalSince(draft.start)) <= 30 * 60 }
    }

    private static func conflictNote(_ conflicts: [CalendarEvent]) -> String {
        guard !conflicts.isEmpty else { return " No conflicts." }
        return " It overlaps: " + conflicts.map { "“\($0.title)” \(describe($0.start, $0.end, allDay: false))" }.joined(separator: ", ")
            + " — the user sees this on the card."
    }

    #if DEBUG
    /// Snapshot renderer only.
    func loadPreviewEventRequests(_ requests: [EventRequest]) {
        eventRequests = requests
    }

    /// Self-test only: runs an assistant action exactly as the chat would.
    func performForTest(_ action: AssistantAction) async -> AssistantService.ToolOutcome {
        await perform(action)
    }
    #endif

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

    func speak(_ text: String, _ importance: Importance) {
        buddyLine = text
        lastSpokeAt = .now
        if isPanelOpen {
            character.mouthAlong(text)
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
