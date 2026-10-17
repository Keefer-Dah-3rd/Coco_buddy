import AppKit
import SwiftUI

/// Creates the windows and connects them to the model. The only place that knows
/// about both AppKit window controllers and app state.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // Snapshot runs (Debug only) use in-memory stores so they never touch real data.
    let model = AppModel(preview: CommandLine.arguments.contains("--snapshots") || AppDelegate.isExperimentSnapshotRun)

    private var character: CharacterWindowController!
    private var bubble: BubbleWindowController!
    private var panel: PanelWindowController!
    private var connections: ConnectionsWindowController!
    private var settings: HostedWindowController!
    private var onboarding: HostedWindowController!
    private let shortcut = GlobalShortcut()
    private let callKey = CallKeyMonitor(key: .rightOption)
    private let throwKey = CallKeyMonitor(key: .rightCommand)
    private let treatKey = CallKeyMonitor(key: .rightShift)
    private let callOverlay = CallOverlayController()
    private var isOccluded = false
    #if DEBUG
    /// Design experiment, only with `--editorial-orange` (see DesktopBuddy/Experiments).
    private var editorialOrange: EditorialOrangeWindowController?
    private var tactileOrange: TactileOrangeWindowController?
    private static let isExperimentSnapshotRun = CommandLine.arguments.contains("--editorial-orange-snapshots")
        || CommandLine.arguments.contains("--tactile-orange-snapshots")
    #else
    private static let isExperimentSnapshotRun = false
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if CommandLine.arguments.contains("--keychain-selftest") {
            let saved = Keychain.set(Data("selftest".utf8), for: "selftest")
            let read = Keychain.string(for: "selftest")
            Keychain.remove("selftest")
            print("keychain selftest: saved=\(saved) readBack=\(read == "selftest") status=\(Keychain.lastStatus)")
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--run-preview"), index + 1 < CommandLine.arguments.count {
            RunPreview.run(into: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if CommandLine.arguments.contains("--fetch-selftest") {
            FetchSelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--partiful-selftest") {
            PartifulSelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--calendar-selftest") {
            CalendarSelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--apple-calendar-selftest") {
            AppleCalendarSelfTest.run()
            exit(0)
        }
        if CommandLine.arguments.contains("--dash-selftest") {
            DashSelfTest.run()
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--snapshots"), index + 1 < CommandLine.arguments.count {
            SnapshotRenderer.run(into: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--editorial-orange-snapshots"), index + 1 < CommandLine.arguments.count {
            EditorialOrangeSnapshots.run(into: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--tactile-orange-snapshots"), index + 1 < CommandLine.arguments.count {
            TactileOrangeSnapshots.run(into: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        }
        #endif
        character = CharacterWindowController(model: model.character)
        bubble = BubbleWindowController(parent: character.window)
        panel = PanelWindowController(model: model)
        connections = ConnectionsWindowController(model: model)
        let model = model
        settings = HostedWindowController(title: "Settings", size: NSSize(width: 540, height: 680)) {
            AnyView(SettingsView(model: model))
        }
        onboarding = HostedWindowController(title: "Welcome", size: NSSize(width: 460, height: 610)) { [weak self] in
            AnyView(OnboardingView(model: model) {
                self?.onboarding.close()
                model.finishOnboarding()
            })
        }
        // Closing the welcome early counts as done — it never nags; Settings can show it again.
        onboarding.onUserClose = { model.preferences.onboardingCompleted = true }
        shortcut.onPress = { [weak self] in
            guard let self else { return }
            if !self.model.preferences.isBuddyVisible { self.model.preferences.isBuddyVisible = true }
            self.model.setPanelOpen(!self.model.isPanelOpen)
        }

        connectCharacterWindow()
        connectPanel()
        connectCalling()
        observeSystemSettings()

        model.start()
        character.place(at: model.preferences.buddyOrigin)
        observeModel()
        #if DEBUG
        if CommandLine.arguments.contains("--editorial-orange") {
            editorialOrange = EditorialOrangeWindowController(model: model)
            editorialOrange?.show()
        }
        if CommandLine.arguments.contains("--tactile-orange") {
            tactileOrange = TactileOrangeWindowController(model: model)
            tactileOrange?.show()
        }
        #endif
        if !model.preferences.onboardingCompleted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.onboarding.show() }
        }
    }

    private func connectCharacterWindow() {
        character.onClick = { [weak self] in self?.model.buddyClicked() }
        character.onRightClick = { [weak self] event, view in
            guard let self else { return }
            NSMenu.popUpContextMenu(BuddyContextMenu.make(model: self.model), with: event, for: view)
        }
        character.onDragChanged = { [weak self] dragging in
            guard let self else { return }
            self.model.character.setCarried(dragging)
            if dragging {
                self.model.setPanelOpen(false)
            } else {
                self.model.character.react(.land)
            }
        }
        character.onGaze = { [weak self] target in self?.model.character.look(at: target) }
        character.onMoved = { [weak self] origin in self?.model.preferences.buddyOrigin = origin }
        character.onOcclusionChanged = { [weak self] occluded in
            self?.isOccluded = occluded
            self?.updateRenderingPause()
        }
    }

    private func connectPanel() {
        panel.onOpenChanged = { [weak self] open in self?.model.panelDidChange(open: open) }
        model.windows = AppModel.WindowCommands(
            setPanelOpen: { [weak self] open in
                guard let self else { return }
                if open {
                    self.panel.open(beside: self.character.characterFrame, on: self.character.screen)
                } else {
                    self.panel.close()
                }
            },
            resetPosition: { [weak self] in self?.character.resetPosition() },
            openConnections: { [weak self] in self?.connections.show() },
            openSettings: { [weak self] in self?.settings.show() },
            showOnboarding: { [weak self] in self?.onboarding.show() }
        )
    }

    /// Hold right Option and click anywhere: Coco runs to the spot. Hold right Command and
    /// click: you throw her ball there and she fetches it.
    private func connectCalling() {
        callKey.onChange = { [weak self] held in self?.aimKeyChanged(.rightOption, held: held) }
        throwKey.onChange = { [weak self] held in self?.aimKeyChanged(.rightCommand, held: held) }
        treatKey.onChange = { [weak self] held in self?.aimKeyChanged(.rightShift, held: held) }
        callOverlay.onCall = { [weak self] point, key in
            switch key {
            case .rightOption: self?.call(to: point)
            case .rightCommand: self?.throwBall(to: point)
            case .rightShift: self?.throwTreat(to: point)
            }
        }
        // The cursor is over the overlay while aiming, so pass its moves on to her eyes.
        callOverlay.onCursorMoved = { [weak self] in self?.character.cursorMoved() }
        character.onDashFinished = { [weak self] in self?.dashFinished() }
        character.onFetchFinished = { [weak self] in
            self?.model.fetchFinished()
            self?.dashFinished()
        }
        character.onTreatFinished = { [weak self] in
            self?.model.treatEaten()
            self?.dashFinished()
        }
    }

    private func aimKeyChanged(_ key: HeldKey, held: Bool) {
        // Mid-game (fetch or a treat) she's busy: no key does anything until she's done.
        let aiming = held && model.preferences.isBuddyVisible && !character.isPlaying
        if aiming {
            callOverlay.show(for: key)
        } else if callOverlay.key == key {
            callOverlay.hide()
        }
        // Holding a treat out: she begs until it's thrown or put away.
        if key == .rightShift { character.setBegging(aiming) }
        character.isWatchingAim = callOverlay.isShowing
    }

    private func call(to point: CGPoint) {
        guard model.preferences.isBuddyVisible, !character.isPlaying else { return }
        model.buddyCalled()
        bubble.hide()
        callOverlay.showMarker(at: character.destination(forClickAt: point), below: character.window)
        character.call(to: point)
    }

    private func throwTreat(to point: CGPoint) {
        guard model.preferences.isBuddyVisible, !character.isPlaying else { return }
        model.buddyCalled()
        bubble.hide()
        // One treat at a time: the one in your hand goes away until she's done.
        callOverlay.hide()
        character.isWatchingAim = false
        character.throwTreat(to: point)
    }

    private func throwBall(to point: CGPoint) {
        guard model.preferences.isBuddyVisible, !character.isPlaying else { return }
        model.buddyCalled()
        bubble.hide()
        // One throw at a time: the aiming ball goes away until she's brought it back.
        callOverlay.hide()
        character.isWatchingAim = false
        character.throwBall(to: point)
    }

    private func dashFinished() {
        callOverlay.hideMarker()
        // Anything she was saying when she set off reappears above her new spot.
        if let speech = model.character.speech {
            bubble.show(speech.text, near: character.characterFrame, on: character.screen)
        }
    }

    private func observeModel() {
        let model = model
        track({ model.preferences.isBuddyVisible }) { [weak self] visible in
            guard let self else { return }
            self.character.setVisible(visible)
            if !visible {
                self.bubble.hide()
                self.callOverlay.hide()
            }
            self.updateRenderingPause()
        }
        track({ model.preferences.globalShortcutEnabled }) { [weak self] enabled in
            guard let self else { return }
            self.model.shortcutUnavailable = !self.shortcut.setEnabled(enabled)
        }
        track({ model.preferences.throwKeyEnabled }) { [weak self] enabled in
            self?.throwKey.setEnabled(enabled)
        }
        track({ model.preferences.treatKeyEnabled }) { [weak self] enabled in
            self?.treatKey.setEnabled(enabled)
        }
        track({ model.preferences.callKeyEnabled }) { [weak self] enabled in
            self?.callKey.setEnabled(enabled)
        }
        track({ model.preferences.alwaysOnTop }) { [weak self] onTop in
            self?.character.setAlwaysOnTop(onTop)
        }
        track({ model.characterSync }) { [weak self] sync in
            self?.character.followsCursor = sync.followsCursor
        }
        track({ model.character.speech }) { [weak self] speech in
            guard let self else { return }
            if let speech {
                // Mid-run the bubble waits; it shows when she arrives.
                guard !self.character.isDashing, !self.character.isPlaying else { return }
                self.bubble.show(speech.text, near: self.character.characterFrame, on: self.character.screen)
            } else {
                self.bubble.hide()
            }
        }
    }

    private func observeSystemSettings() {
        let workspace = NSWorkspace.shared
        model.character.setReduceMotion(workspace.accessibilityDisplayShouldReduceMotion)
        workspace.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.character.setReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.character.isLowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    /// Stop drawing entirely when nobody can see the buddy.
    private func updateRenderingPause() {
        let paused = isOccluded || !model.preferences.isBuddyVisible
        if model.character.isRenderingPaused != paused {
            model.character.isRenderingPaused = paused
        }
    }
}
