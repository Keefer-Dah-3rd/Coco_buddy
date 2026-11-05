#if DEBUG
import AppKit
import SwiftUI
import BuddyCore

/// Clicks and types into the real Focus tab in an invisible window: the quick picks, typing a
/// length on the clock (Return, Esc, Tab, a refused entry, the 3-hour cap, Start while typing),
/// Space while typing, Tab onto the clock, and a stopped break coming back as focus. Takes keyboard
/// focus for a few seconds (exits 2, skipped, if macOS won't give it). Debug builds only; pass a
/// folder to also save what the card looks like:
///
///     Coco.app/Contents/MacOS/Coco --focus-length-selftest [png folder]
enum FocusLengthSelfTest {
    @MainActor
    static func run(pngFolder: URL?) {
        setvbuf(stdout, nil, _IONBF, 0)  // every line out at once, even if the run is cut short
        var passed = 0
        var failed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { passed += 1 } else { failed += 1; print("focus length selftest FAILED: \(name)") }
        }
        func spin(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

        let model = AppModel(preview: true)
        model.preferences.reset()
        model.start()
        let focus = model.focus
        let size = CGSize(width: 425, height: 620)
        let hosting = NSHostingView(rootView: FocusView(model: model)
            .frame(width: size.width, height: size.height)
            .background(Sky.paper))
        // The panel's own window: key without activating the app, and Esc closes it.
        let window = InteractionPanel()
        var panelEscapes = 0
        window.onEscape = { panelEscapes += 1 }
        window.appearance = NSAppearance(named: .aqua)
        window.setContentSize(size)
        window.contentView = hosting
        window.alphaValue = 0
        window.ignoresMouseEvents = true  // real clicks pass through; the test's own go straight to the window
        if let screen = NSScreen.main?.visibleFrame { window.setFrameOrigin(CGPoint(x: screen.minX + 40, y: screen.minY + 40)) }
        window.makeKeyAndOrderFront(nil)
        spin(0.5)
        // Now and then macOS won't make a background run's panel key; then no key reaches it.
        guard window.isKeyWindow else {
            print("focus length selftest: SKIPPED, the panel couldn't become key (another app holds the keyboard). Run it again.")
            exit(2)
        }

        func editor() -> NSTextView? { window.firstResponder as? NSTextView }
        func save(_ name: String) {
            guard let pngFolder else { return }
            let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            try? FileManager.default.createDirectory(at: pngFolder, withIntermediateDirectories: true)
            try? rep.representation(using: .png, properties: [:])?.write(to: pngFolder.appendingPathComponent("focus-length-\(name).png"))
        }

        /// Where things sit on the Focus tab, in points from the top left (see the saved PNGs).
        /// The accessibility tree isn't built without an assistive client, so it can't be asked.
        let places: [String: CGPoint] = ["15m": CGPoint(x: 59, y: 21), "25m": CGPoint(x: 136, y: 21), "45m": CGPoint(x: 212, y: 21),
                                         "1h": CGPoint(x: 289, y: 21), "1h 30m": CGPoint(x: 365, y: 21),
                                         "clock": CGPoint(x: 120, y: 93), "Start focus": CGPoint(x: 212, y: 346)]
        func click(_ name: String, settle: TimeInterval = 0.3) {
            guard let place = places[name] else { return check(false, "knows where “\(name)” is") }
            let point = CGPoint(x: place.x, y: size.height - place.y)
            func mouse(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            }
            // A real click on the panel makes it key; something else may have taken that since.
            if !window.isKeyWindow {
                print("focus length selftest: the panel wasn't key before clicking “\(name)”")
                window.makeKeyAndOrderFront(nil)
            }
            // Never click into an open text field here: it waits for a real mouse-up and the test stalls.
            window.sendEvent(mouse(.leftMouseDown))
            window.sendEvent(mouse(.leftMouseUp))
            spin(settle)
        }
        func press(_ characters: String, keyCode: UInt16) {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window.windowNumber, context: nil, characters: characters,
                                             charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
                NSApp.sendEvent(event)  // the app's own routing: shortcuts first, then the focused view
            }
            spin(0.05)
        }
        let keyCodes: [Character: UInt16] = ["0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26, "8": 28, "9": 25,
                                             "h": 4, "m": 46, "a": 0, "b": 11, "c": 8, " ": 49]
        func type(_ text: String) {
            for character in text { press(String(character), keyCode: keyCodes[character] ?? 0) }
            spin(0.2)
        }
        let returnKey = ("\r", UInt16(36)), escapeKey = ("\u{1b}", UInt16(53)), tabKey = ("\t", UInt16(48))

        // The picks replace Focus / Short / Long and set the focus length.
        check(focus.timer.phase == .focus && focus.remaining == 25 * 60, "starts on a 25-minute focus session")
        click("1h 30m")
        check(model.preferences.focusSettings.focusMinutes == 90 && focus.remaining == 90 * 60, "the 1h 30m pick sets 90 minutes")
        click("45m")
        check(model.preferences.focusSettings.focusMinutes == 45 && focus.remaining == 45 * 60, "the 45m pick sets and saves 45 minutes")
        save("1-picked-45")

        // Clicking the clock selects the time; typing replaces it, Space included; Return sets it.
        click("clock")
        spin(0.2)
        check(editor() != nil, "clicking the clock starts typing")
        check(editor()?.string == "45:00" && editor()?.selectedRange() == NSRange(location: 0, length: 5),
              "the time is selected, so typing replaces it (got “\(editor()?.string ?? "-")” \(editor().map { NSStringFromRange($0.selectedRange()) } ?? "-"))")
        save("2-clicked")
        type("1h 30")
        check(editor()?.string == "1h 30", "typed “1h 30” (got “\(editor()?.string ?? "-")”)")
        check(!focus.timer.isActive, "Space while typing doesn't start the session")
        save("3-typed")
        press(returnKey.0, keyCode: returnKey.1)
        spin(0.3)
        check(focus.remaining == 90 * 60 && model.preferences.focusSettings.focusMinutes == 90, "Return sets 1h 30m")
        check(editor() == nil, "and closes the field")
        save("4-set-90")

        // Something that isn't a length keeps the field open; Esc drops it.
        click("clock")
        type("abc")
        press(returnKey.0, keyCode: returnKey.1)
        spin(0.45)
        check(editor() != nil && focus.remaining == 90 * 60, "Return on “abc” keeps the field open and the length as it was")
        save("5-refused")
        press(escapeKey.0, keyCode: escapeKey.1)
        spin(0.3)
        check(editor() == nil && focus.remaining == 90 * 60, "Esc closes the field without a change")
        check(panelEscapes == 0, "and leaves the panel open")

        // Past the longest length, it's capped at 3 hours.
        click("clock")
        type("500")
        press(returnKey.0, keyCode: returnKey.1)
        spin(0.3)
        check(focus.remaining == 180 * 60, "500 is capped at 3 hours")

        // Tab out keeps what was typed.
        click("clock")
        type("20")
        press(tabKey.0, keyCode: tabKey.1)
        spin(0.3)
        check(focus.remaining == 20 * 60 && editor() == nil, "Tab keeps a typed 20 (remaining \(Int(focus.remaining / 60))m)")
        check(model.preferences.focusSettings.focusMinutes == 20, "and saves it as the focus length")

        // Typing straight after the click keeps every key, and Start uses what was typed.
        click("clock", settle: 0.1)
        for character in "35" {
            press(String(character), keyCode: keyCodes[character]!)
            spin(0.03)
        }
        check(editor()?.string == "35", "typing 0.1 s after the click keeps every key (got “\(editor()?.string ?? "-")”)")
        click("Start focus")
        check(focus.timer.isRunning && focus.timer.duration == 35 * 60, "Start while typing starts a 35-minute session")
        save("6-running")
        click("clock")
        check(editor() == nil, "the running clock can't be typed into")
        focus.stop()
        spin(0.2)

        // Space still starts a session when nobody is typing.
        window.makeFirstResponder(nil)
        press(" ", keyCode: 49)
        spin(0.2)
        check(focus.timer.isRunning, "Space starts the session when not typing")
        focus.stop()
        spin(0.2)

        // The keyboard can reach the clock too: Tab onto it to type, Esc to leave.
        window.makeFirstResponder(nil)
        press(tabKey.0, keyCode: tabKey.1)
        spin(0.3)
        check(editor()?.string == "35:00" && editor()?.selectedRange() == NSRange(location: 0, length: 5),
              "Tab onto the clock opens it with the time selected (got “\(editor()?.string ?? "-")”)")
        press(escapeKey.0, keyCode: escapeKey.1)
        spin(0.3)
        check(editor() == nil && panelEscapes == 0, "Esc leaves it, with the panel still open")

        // A stopped break comes back as a focus session, since there's no phase picker.
        focus.start(.shortBreak)
        spin(0.1)
        focus.stop()
        spin(0.2)
        check(focus.timer.phase == .focus && focus.remaining == 35 * 60, "a stopped break shows the focus length again")
        save("7-after-break")

        window.orderOut(nil)
        print("focus length selftest: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }

}
#endif
