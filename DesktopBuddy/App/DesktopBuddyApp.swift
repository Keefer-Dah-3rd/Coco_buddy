import SwiftUI

@main
struct DesktopBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item is the buddy's "home": always reachable, even when the buddy is hidden.
        MenuBarExtra {
            MenuBarMenu(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
    }
}
