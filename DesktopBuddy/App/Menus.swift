import SwiftUI
import BuddyCore
import BuddyCharacter

/// The menu bar dropdown.
struct MenuBarMenu: View {
    let model: AppModel

    var body: some View {
        @Bindable var preferences = model.preferences
        let timer = model.focus.timer

        Button("Open \(Buddy.name)") { model.openPanel() }
            .keyboardShortcut("o")
        Button("Talk to \(Buddy.name)") { model.talkToBuddy() }

        Divider()

        if timer.isActive {
            Text("\(timer.phase.label) · \(AppModel.clock(model.focus.remaining)) left")
            if timer.isRunning {
                Button("Pause") { model.focus.pause() }
            } else {
                Button("Resume") { model.focus.resume() }
            }
            Button("Stop Session") { model.focus.stop() }
        } else {
            Button("Start Focus (\(preferences.focusSettings.focusMinutes) min)") {
                model.focus.start(.focus, taskID: timer.taskID)
            }
        }

        Divider()

        Toggle("Show \(Buddy.name)", isOn: $preferences.isBuddyVisible)
        Toggle("Always on Top", isOn: $preferences.alwaysOnTop)
        Toggle("Mute Sounds", isOn: $preferences.soundsMuted)
        Toggle("\(Buddy.name) Speaks Aloud", isOn: $preferences.voiceEnabled)
        Picker("Presence", selection: $preferences.presence) {
            ForEach(Preferences.Presence.allCases) { Text($0.label).tag($0) }
        }
        Picker("During Focus", selection: $preferences.focusPresentation) {
            ForEach(Preferences.FocusPresentation.allCases) { Text($0.label).tag($0) }
        }
        Menu("Animation Preview") {
            ForEach(CharacterState.allCases, id: \.self) { state in
                Button(state.label) { model.preview(state) }
            }
        }
        Button("Reset Position") { model.resetPosition() }

        Divider()

        Button("Quit Desktop Buddy") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

/// Menu bar icon: a tiny corgi glyph, plus the countdown while a session runs.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let timer = model.focus.timer
        if timer.isActive {
            Image(nsImage: BuddyGlyph.menuBar)
            Text(AppModel.clock(model.focus.remaining))
                .monospacedDigit()
        } else {
            Image(nsImage: BuddyGlyph.menuBar)
        }
    }
}

enum BuddyGlyph {
    /// A template image so it adapts to light/dark menu bars.
    static let menuBar: NSImage = {
        // Coco's head: rounded corgi ears, the white blaze running into her muzzle, a nose.
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            NSColor.black.setFill()
            for mirror in [CGFloat(1), -1] {
                func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: 9 + (x - 9) * mirror, y: y) }
                let ear = NSBezierPath()
                ear.move(to: p(2.4, 8.2))
                ear.curve(to: p(3.0, 0.9), controlPoint1: p(1.6, 5.2), controlPoint2: p(2.0, 2.4))
                ear.curve(to: p(5.0, 0.8), controlPoint1: p(3.6, 0.0), controlPoint2: p(4.4, 0.0))
                ear.curve(to: p(8.6, 4.4), controlPoint1: p(6.4, 2.0), controlPoint2: p(7.6, 3.0))
                ear.close()
                ear.fill()
            }
            NSBezierPath(ovalIn: NSRect(x: 2.8, y: 3.4, width: 12.4, height: 10.8)).fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let blaze = NSBezierPath()
            blaze.move(to: NSPoint(x: 8.5, y: 4.2))
            blaze.line(to: NSPoint(x: 9.5, y: 4.2))
            blaze.line(to: NSPoint(x: 10.3, y: 10))
            blaze.line(to: NSPoint(x: 7.7, y: 10))
            blaze.close()
            blaze.fill()
            NSBezierPath(ovalIn: NSRect(x: 6.1, y: 9.3, width: 5.8, height: 4.4)).fill()
            NSBezierPath(ovalIn: NSRect(x: 5.2, y: 7.0, width: 1.8, height: 2.1)).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.0, y: 7.0, width: 1.8, height: 2.1)).fill()

            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSBezierPath(ovalIn: NSRect(x: 7.9, y: 9.6, width: 2.2, height: 1.6)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Desktop Buddy"
        return image
    }()
}

/// Right-click menu on the character itself.
enum BuddyContextMenu {
    static func make(model: AppModel) -> NSMenu {
        let menu = NSMenu()
        let preferences = model.preferences
        let timer = model.focus.timer

        menu.addItem(NSMenuItem.action("Open \(Buddy.name)") { model.openPanel() })
        menu.addItem(NSMenuItem.action("Talk to \(Buddy.name)") { model.talkToBuddy() })
        menu.addItem(.separator())
        if timer.isActive {
            if timer.isRunning {
                menu.addItem(NSMenuItem.action("Pause \(timer.phase.label)") { model.focus.pause() })
            } else {
                menu.addItem(NSMenuItem.action("Resume \(timer.phase.label)") { model.focus.resume() })
            }
            menu.addItem(NSMenuItem.action("Stop Session") { model.focus.stop() })
        } else {
            menu.addItem(NSMenuItem.action("Start Focus") { model.focus.start(.focus, taskID: timer.taskID) })
        }
        menu.addItem(.separator())

        let presence = NSMenu()
        for option in Preferences.Presence.allCases {
            presence.addItem(NSMenuItem.action(option.label, checked: preferences.presence == option) {
                preferences.presence = option
            })
        }
        menu.addItem(submenu: presence, titled: "Presence")

        let during = NSMenu()
        for option in Preferences.FocusPresentation.allCases {
            during.addItem(NSMenuItem.action(option.label, checked: preferences.focusPresentation == option) {
                preferences.focusPresentation = option
            })
        }
        menu.addItem(submenu: during, titled: "During Focus")

        menu.addItem(NSMenuItem.action("Always on Top", checked: preferences.alwaysOnTop) {
            preferences.alwaysOnTop.toggle()
        })
        menu.addItem(NSMenuItem.action("Mute Sounds", checked: preferences.soundsMuted) {
            preferences.soundsMuted.toggle()
        })
        menu.addItem(NSMenuItem.action("\(Buddy.name) Speaks Aloud", checked: preferences.voiceEnabled) {
            preferences.voiceEnabled.toggle()
        })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem.action("Hide \(Buddy.name)") { preferences.isBuddyVisible = false })
        menu.addItem(NSMenuItem.action("Reset Position") { model.resetPosition() })
        menu.addItem(.separator())
        menu.addItem(NSMenuItem.action("Quit Desktop Buddy") { NSApp.terminate(nil) })
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, titled title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

/// Menu items that run a closure, so menus can be built inline.
private final class MenuAction: NSObject {
    let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @objc func fire() { handler() }
}

private extension NSMenuItem {
    static func action(_ title: String, checked: Bool = false, handler: @escaping () -> Void) -> NSMenuItem {
        let target = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.fire), keyEquivalent: "")
        item.target = target
        // `target` is weak; the item keeps its action object alive.
        item.representedObject = target
        item.state = checked ? .on : .off
        return item
    }
}
