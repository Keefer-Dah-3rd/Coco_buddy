#if DEBUG
import AppKit

/// Debug-only launch arguments: the in-app self-tests and snapshot renders described in the
/// README and docs/BANNERS.md. They run before any window exists, on in-memory stores where
/// they render the app. Most exit when done; `--focus-length-selftest` and `--banner-selftest`
/// drive the running app, so it carries on after them.
@MainActor
enum DebugLaunch {
    private static let arguments = CommandLine.arguments

    /// The folder named after `flag`, if there is one.
    private static func folder(after flag: String) -> URL? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Runs every flag given, in this order.
    static func run() {
        if arguments.contains("--keychain-selftest") {
            let saved = Keychain.set(Data("selftest".utf8), for: "selftest")
            let read = Keychain.string(for: "selftest")
            Keychain.remove("selftest")
            print("keychain selftest: saved=\(saved) readBack=\(read == "selftest") status=\(Keychain.lastStatus)")
            exit(0)
        }
        if let folder = folder(after: "--run-preview") {
            RunPreview.run(into: folder)
            exit(0)
        }
        if arguments.contains("--fetch-selftest") {
            FetchSelfTest.run()
            exit(0)
        }
        if arguments.contains("--consent-selftest") {
            ConsentSelfTest.run()
            exit(0)
        }
        if arguments.contains("--partiful-selftest") {
            PartifulSelfTest.run()
            exit(0)
        }
        if arguments.contains("--calendar-selftest") {
            CalendarSelfTest.run()
            exit(0)
        }
        if arguments.contains("--apple-calendar-selftest") {
            AppleCalendarSelfTest.run()
            exit(0)
        }
        if arguments.contains("--tasks-selftest") {
            TasksSelfTest.run()
            exit(0)
        }
        if arguments.contains("--focus-length-selftest") {
            FocusLengthSelfTest.run(pngFolder: folder(after: "--focus-length-selftest"))
        }
        if arguments.contains("--dash-selftest") {
            DashSelfTest.run()
            exit(0)
        }
        if arguments.contains("--voice-selftest") {
            VoiceSelfTest.run()
            exit(0)
        }
        if arguments.contains("--banner-selftest") {
            BannerSelfTest.run()
        }
        if let folder = folder(after: "--banner-snapshots") {
            BannerSnapshots.run(into: folder)
            exit(0)
        }
        if let folder = folder(after: "--snapshots") {
            SnapshotRenderer.run(into: folder)
            exit(0)
        }
    }
}
#endif
