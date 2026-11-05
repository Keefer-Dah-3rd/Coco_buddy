#if DEBUG
import AppKit
import QuartzCore
import BuddyCore
import BuddyIntegrations

/// Drives the real banner view, banner manager, weather store and Coco's remarks. Debug only:
///
///     DesktopBuddy.app/Contents/MacOS/DesktopBuddy --banner-selftest [--live]
///
/// `--live` also downloads one real forecast from MET Norway (for Oslo) and reads it.
/// Run an unsandboxed build: it uses throwaway defaults and never asks for location.
enum BannerSelfTest {
    @MainActor
    static func run() {
        var passed = 0
        var failed = 0
        func check(_ condition: Bool, _ name: String) {
            if condition { passed += 1 } else { failed += 1; print("banner selftest FAILED: \(name)") }
        }
        func wait(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
        func wait(until condition: () -> Bool, timeout: Double = 5) -> Bool {
            let end = Date().addingTimeInterval(timeout)
            while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
            return condition()
        }

        // MARK: The view: progress slides, looks crossfade, nothing piles up.
        let view = BannerSceneView(frame: NSRect(x: 0, y: 0, width: 350, height: 166.25))
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 350, height: 167),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        window.orderFrontRegardless()
        let a = BannerState(banner: .slowFerry, time: .daytime, weather: .sunny, progress: .init(done: 1, total: 5))
        view.show(a, animated: false)
        view.layoutSubtreeIfNeeded()
        wait(0.1)
        let scale: CGFloat = 350 / 320
        check(frameCount(view) == 1, "one frame at rest")
        check(abs((thumbX(view) ?? -1) - (20 + 56) * scale) < 0.5, "thumb starts at 1 of 5")
        check(ambientCount(view) > 0 || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "ambient motion runs")

        var b = a
        b.progress = .init(done: 3, total: 5)
        view.show(b, animated: true)
        wait(0.12)
        let mid = presentedThumbX(view) ?? -1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(abs(mid - (20 + 168) * scale) < 0.5, "Reduce Motion: the thumb jumps, no slide")
        } else {
            check(mid > (20 + 56) * scale + 1 && mid < (20 + 168) * scale - 0.5, "the thumb slides (mid-way at \(mid))")
        }
        check(frameCount(view) == 2, "the new frame fades in over the old")
        wait(0.6)
        check(frameCount(view) == 1, "the old frame is dropped after the fade")
        check(abs((presentedThumbX(view) ?? -1) - (20 + 168) * scale) < 0.5, "the thumb ends at 3 of 5")

        // A new light crossfades slowly, and the size never changes.
        var c = b
        c.time = .evening
        c.weather = .rainy
        let before = view.layer?.sublayers?.first?.bounds.size
        view.show(c, animated: true)
        wait(0.6)
        let fading = view.layer?.sublayers?.last?.presentation()?.opacity ?? 1
        check(frameCount(view) == 2 && fading > 0.05 && fading < 0.95, "a change of light crossfades (opacity \(fading))")
        wait(0.9)
        check(frameCount(view) == 1, "the crossfade settles")
        check(view.layer?.sublayers?.first?.bounds.size == before, "the banner keeps its size")

        // Tasks added, done, removed and done again in a rush: no pile-up, ends in the right place.
        var rush = c
        for (done, total) in [(3, 6), (4, 6), (4, 9), (0, 9), (9, 9), (2, 3), (0, 0), (1, 1), (5, 12), (7, 12)] {
            rush.progress = .init(done: done, total: total)
            view.show(rush, animated: true)
            wait(0.03)
        }
        check(frameCount(view) <= 11, "rapid changes stay bounded (\(frameCount(view)) frames)")
        _ = wait(until: { frameCount(view) == 1 }, timeout: 3)
        check(frameCount(view) == 1, "rapid changes settle to one frame")
        check(abs((presentedThumbX(view) ?? -1) - (20 + 280 * 7 / 12) * scale) < 0.5, "the thumb ends at 7 of 12")
        check(abs((presentedJourney(view) ?? -1) - (35 + 160 * 7 / 12) * scale) < 0.5, "the ferry ends at 7 of 12")
        window.orderOut(nil)

        // MARK: The day's banner and light follow the clock.
        let manager = DailyBannerManager()
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!
        manager.refresh(now: today)
        let first = manager.banner
        check(manager.time == .morning, "9 am is morning")
        manager.refresh(now: calendar.date(bySettingHour: 23, minute: 55, second: 0, of: today)!)
        check(manager.banner == first && manager.time == .night, "same banner all day; 11:55 pm is night")
        manager.refresh(now: calendar.date(byAdding: .day, value: 1, to: today)!)
        check(manager.banner != first, "a new day brings a different banner")
        manager.refresh(now: today)
        check(manager.banner == first, "back to today, the same banner (stable, not random)")

        // MARK: Weather: off, ready, offline with the last reading, location off.
        let defaults = UserDefaults(suiteName: "DesktopBuddy.selftest.weather")!
        defaults.removePersistentDomain(forName: "DesktopBuddy.selftest.weather")
        let preferences = Preferences(defaults: defaults)
        let provider = StandInProvider()
        let store = WeatherStore(preferences: preferences, provider: provider, persistent: false, locationAccess: false)
        store.refresh(olderThan: 0)
        check(store.status == .off && store.snapshot == nil, "weather is off until turned on")
        preferences.weatherPlace = WeatherPlace(name: "Lisbon", latitude: 38.72, longitude: -9.14)
        preferences.weatherEnabled = true
        store.refresh(olderThan: 0)
        check(wait(until: { store.status == .ready }), "a city gives a reading")
        check(store.snapshot?.condition == .rain && store.placeName == "Lisbon", "the reading is the provider's")
        check(provider.requests == 1, "one download")
        store.refresh(olderThan: WeatherStore.refreshAfter)
        wait(0.2)
        check(provider.requests == 1, "a fresh reading isn't downloaded again")
        provider.fails = true
        store.refresh(olderThan: 0)
        check(wait(until: { if case .unavailable = store.status { true } else { false } }), "offline is reported")
        check(store.snapshot?.condition == .rain, "offline keeps showing the last reading")
        store.refresh(olderThan: 0)
        wait(0.2)
        check(provider.requests == 2, "after a failure it backs off instead of retrying at once")
        let caption = manager.caption(store)
        check(caption.weather?.hasPrefix("RAIN · ") == true, "the corner says the weather (\(caption.weather ?? "nil"))")
        preferences.weatherPlace = nil
        let noLocation = WeatherStore(preferences: preferences, provider: provider, persistent: false, locationAccess: false)
        noLocation.refresh(olderThan: 0)
        check(wait(until: { noLocation.status == .locationDenied }), "location off and no city is reported")
        check(noLocation.snapshot == nil, "no reading without a place")
        store.turnOff()
        check(store.status == .off && store.snapshot == nil && !preferences.weatherEnabled, "turning off clears the reading")
        defaults.removePersistentDomain(forName: "DesktopBuddy.selftest.weather")

        // MARK: Coco's remarks: due once per part of the day, true to the art.
        let model = AppModel(preview: true)
        model.preferences.reset()
        model.banner.override = .init(banner: .cornerBookshop, time: .daytime, weather: .rainy)
        let noon = calendar.date(bySettingHour: 12, minute: 30, second: 0, of: .now)!
        let said = model.remarkForSelfTest(noon)
        check(said != nil, "a remark is due at first")
        check(!["sun", "Sunny", "Bright"].contains { said?.contains($0) ?? false }, "a rainy banner gets no sunshine talk (\(said ?? ""))")
        check(model.remarkForSelfTest(noon.addingTimeInterval(30 * 60)) == nil, "not again in the same part of the day")
        check(model.remarkForSelfTest(noon.addingTimeInterval(80 * 60)) == nil, "not again within 90 minutes")
        model.banner.override = .init(banner: .cornerBookshop, time: .evening, weather: .rainy)
        let again = model.remarkForSelfTest(noon.addingTimeInterval(5 * 3600))
        check(again != nil, "a new part of the day can have one")
        check(again != said, "and it's a different line")

        // MARK: One real forecast.
        if CommandLine.arguments.contains("--live") {
            var reading: WeatherSnapshot?
            var problem: String?
            Task {
                do {
                    let live = METNorwayProvider()
                    let download = try await live.download(latitude: 59.91, longitude: 10.75, ifModifiedSince: nil)
                    reading = try download.data.map { try live.snapshot(from: $0, now: .now) }
                } catch {
                    problem = "\(error)"
                }
            }
            _ = wait(until: { reading != nil || problem != nil }, timeout: 25)
            check(reading != nil, "MET Norway live forecast (\(problem ?? "ok"))")
            if let reading {
                print("live: \(reading.condition.label), \(TemperatureText.short(reading.temperatureC)), wind \(reading.windSpeed) m/s, next 6h \(reading.upcoming?.label ?? "-"), art \(reading.bannerWeather)")
            }
        }

        print("banner selftest: \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }

    // MARK: Peeking at the layers

    private static func frameCount(_ view: BannerSceneView) -> Int { view.layer?.sublayers?.count ?? 0 }

    private static func layers(_ view: BannerSceneView, named motion: BannerArt.Motion) -> [CALayer] {
        view.movers(motion)
    }

    private static func thumbX(_ view: BannerSceneView) -> CGFloat? {
        layers(view, named: .thumb).last.flatMap { $0.value(forKeyPath: "transform.translation.x") as? CGFloat }
    }

    private static func presentedThumbX(_ view: BannerSceneView) -> CGFloat? {
        layers(view, named: .thumb).last.flatMap { ($0.presentation() ?? $0).value(forKeyPath: "transform.translation.x") as? CGFloat }
    }

    private static func presentedJourney(_ view: BannerSceneView) -> CGFloat? {
        layers(view, named: .ferryJourney).last.flatMap { ($0.presentation() ?? $0).value(forKeyPath: "transform.translation.x") as? CGFloat }
    }

    private static func ambientCount(_ view: BannerSceneView) -> Int {
        BannerArt.Motion.allCases.flatMap { view.movers($0) }.filter { $0.animation(forKey: BannerMotion.ambientKey) != nil }.count
    }

    /// Hands out a fixed rainy reading, or fails as if offline, and counts downloads.
    final class StandInProvider: WeatherProvider, @unchecked Sendable {
        var fails = false
        var requests = 0
        var attribution: String { "Stand-in" }

        func download(latitude: Double, longitude: Double, ifModifiedSince: String?) async throws -> WeatherDownload {
            requests += 1
            if fails { throw IntegrationError.offline }
            let reading = WeatherSnapshot(condition: .rain, temperatureC: 11, windSpeed: 3, observedAt: .now, fetchedAt: .now)
            return WeatherDownload(data: try JSONEncoder().encode(reading), expires: nil, lastModified: nil)
        }

        func snapshot(from data: Data, now: Date) throws -> WeatherSnapshot {
            try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        }
    }
}
#endif
