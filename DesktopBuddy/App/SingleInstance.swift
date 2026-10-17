import AppKit

/// One Coco at a time. Two running copies (an old and a new version, or an installed copy
/// and an Xcode run) would both draw her and both react to the held-key tricks.
///
/// A second copy hands over: the running one brings its panel forward, and the new one
/// quits. Debug builds do the opposite — the copy just launched from Xcode is the one being
/// worked on, so it asks the older copy to quit (politely, so it saves its state).
enum SingleInstance {
    /// Posted to the running copy to say "you were launched again".
    private static let reopen = Notification.Name("com.keefer.DesktopBuddy.reopen")

    /// The other running copies of this app (same bundle identifier), not this one.
    private static var others: [NSRunningApplication] {
        guard let id = Bundle.main.bundleIdentifier else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
    }

    /// Call first thing at a normal launch. Returns false when this copy should stop.
    static func claim(onReopen: @escaping @MainActor @Sendable () -> Void) -> Bool {
        #if DEBUG
        // Design experiments are meant to run next to the real app.
        let experiment = ["--editorial-orange", "--tactile-orange", "--plush-toybox"].contains { CommandLine.arguments.contains($0) }
        if !experiment {
            for app in others { app.terminate() }
        }
        #else
        if let running = others.first {
            DistributedNotificationCenter.default().postNotificationName(reopen, object: nil, deliverImmediately: true)
            running.activate()
            return false
        }
        #endif
        DistributedNotificationCenter.default().addObserver(forName: reopen, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onReopen() }
        }
        return true
    }
}
