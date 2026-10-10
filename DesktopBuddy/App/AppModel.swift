import AppKit
import Observation
import BuddyCore
import BuddyCharacter

enum PanelTab: String, CaseIterable, Identifiable {
    case today, focus
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
    /// Tasks heard by voice, waiting for review. Nothing is added until the user confirms.
    var voiceDrafts: [VoiceDraft] = []

    struct VoiceDraft: Identifiable, Equatable {
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

    /// - Parameter preview: in-memory stores and throwaway defaults, for snapshots.
    init(preview: Bool = false) {
        preferences = preview ? Preferences(defaults: UserDefaults(suiteName: "DesktopBuddy.preview")!) : Preferences()
        notifications = NotificationService()
        tasks = TaskStore(persistent: !preview)
        focus = FocusController(preferences: preferences, notifications: notifications, persistent: !preview)
        sounds = SoundPlayer(preferences: preferences)
        buddyLine = BuddyVoice.greeting()
    }

    func start() {
        tasks.onEvent = { [weak self] in self?.handle($0) }
        focus.onEvent = { [weak self] in self?.handle($0) }
        focus.taskTitle = { [weak self] in self?.tasks.task($0)?.title }
        presence.onChange = { [weak self] away in self?.userAwayChanged(away) }
        voiceIn.onFinish = { [weak self] transcript in self?.handleTranscript(transcript) }
        voiceOut.onSpeakingChanged = { [weak self] speaking in self?.character.setVoiceActive(speaking) }

        track({ [weak self] in self?.characterSync }) { [weak self] sync in
            guard let self, let sync else { return }
            self.apply(sync)
        }
        presence.start()
        focus.restoreAfterLaunch()
        greetOncePerDay()
    }

    // MARK: - Intents (called by views and menus)

    func buddyClicked() {
        character.react(.poke)
        if isUserAway { userAwayChanged(false) }
        setPanelOpen(!isPanelOpen)
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
        voiceDrafts = []
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

    func addVoiceDrafts() {
        let results = voiceDrafts.map {
            QuickAddParser.Result(title: $0.title, priority: $0.priority, estimateMinutes: $0.estimateMinutes)
        }
        voiceDrafts = []
        let added = tasks.add(results)
        if added == 0 { speak("Those are already on your list.", .acknowledge) }
    }

    func discardVoiceDrafts() {
        voiceDrafts = []
    }

    private func handleTranscript(_ transcript: String) {
        character.play(.thinking, for: 0.6)
        switch VoiceCommandParser.parse(transcript) {
        case .nothing:
            speak(BuddyVoice.heardNothing, .acknowledge)
        case .addTasks(let heard):
            panelTab = .today
            voiceDrafts = heard.map(VoiceDraft.init)
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
            sounds.play(.taskDone)
            let remaining = tasks.openToday.count
            if focus.isFocusing, preferences.focusPresentation == .quiet {
                character.react(.nod)
            } else {
                character.play(.celebrating, for: remaining == 0 ? 2.6 : 1.6)
            }
            if completionPrompt == task.id { completionPrompt = nil }
            speak(BuddyVoice.taskCompleted(remaining: remaining), .acknowledge)

        case .reopened:
            character.react(.nod)

        case .removed(let task):
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
            if phase == .focus {
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
            if phase == .focus, let taskID {
                tasks.logFocus(minutes: Int(elapsed / 60), for: taskID)
            }

        case .finished(let phase, let duration, let taskID, let whileAway):
            let minutes = Int((duration / 60).rounded())
            let task = tasks.task(taskID)
            if phase == .focus, let task {
                tasks.logFocus(minutes: minutes, for: task.id)
                if !task.isCompleted { completionPrompt = task.id }
            }
            panelTab = .focus
            if whileAway {
                buddyLine = BuddyVoice.endedWhileAway(phase.label)
                return
            }
            sounds.play(.sessionEnd)
            if phase == .focus {
                character.play(.celebrating, for: 2.6)
                speak(BuddyVoice.focusFinished(minutes: minutes, task: task?.title), .important)
            } else {
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
