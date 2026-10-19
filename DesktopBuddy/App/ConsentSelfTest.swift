#if DEBUG
import AppKit
import SwiftUI

/// Checks that nothing reaches Anthropic before the user allows it, that turning it off
/// stops and forgets the chat, and renders the consent screen. Debug builds only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --consent-selftest [<folder for the snapshot>]
enum ConsentSelfTest {
    @MainActor
    static func run() {
        var passed = 0
        var failed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { passed += 1 } else { failed += 1; print("consent selftest FAILED: \(name)") }
        }
        let model = AppModel(preview: true)
        model.preferences.reset()  // the preview defaults outlive a run: start from a fresh install
        model.start()
        let assistant = model.assistant
        assistant.loadPreview([], cost: 0)  // a key is "ready"; no network is involved

        check(!model.hasAIConsent && !assistant.mayShare(), "nothing allowed on a fresh install")
        assistant.send("What's on my calendar today?")
        check(assistant.turns.isEmpty && !assistant.isResponding, "a message before consent isn't sent")

        model.allowAIChat()
        check(model.hasAIConsent && assistant.mayShare(), "Allow lets the chat share")
        check(model.preferences.aiConsentVersion == AIConsent.version, "the version allowed is remembered")

        model.preferences.aiConsentVersion = AIConsent.version - 1
        check(!assistant.mayShare(), "a newer consent text asks again")
        model.allowAIChat()

        assistant.loadPreview([.init(role: .user, text: "Plan my day"), .init(role: .coco, text: "Sure!")], cost: 0.01)
        model.revokeAIChat()
        check(!assistant.mayShare() && assistant.turns.isEmpty && assistant.chatCost == 0, "turning it off forgets the chat")

        model.allowAIChat()
        model.preferences.reset()
        check(!model.hasAIConsent, "Delete all my data clears the permission")

        if CommandLine.arguments.count > 2, let folder = CommandLine.arguments.last, !folder.hasPrefix("--") {
            let url = URL(fileURLWithPath: folder)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            for (name, appearance) in [("consent.png", NSAppearance.Name.aqua), ("consent-dark.png", .darkAqua)] {
                let hosting = NSHostingView(rootView: AIConsentCard(model: model).frame(width: 380, height: 560).background(Theme.paper))
                hosting.frame.size = NSSize(width: 380, height: 560)
                let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: hosting.frame.size),
                                      styleMask: .borderless, backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: appearance)
                window.contentView = hosting
                window.orderFrontRegardless()
                hosting.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                hosting.cacheDisplay(in: hosting.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url.appendingPathComponent(name))
                window.orderOut(nil)
            }
            print("consent snapshots written to \(url.path)")
        }
        print("consent selftest: \(passed) passed, \(failed) failed")
    }
}
#endif
