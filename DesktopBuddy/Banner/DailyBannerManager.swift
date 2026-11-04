import AppKit
import Foundation
import Observation
import BuddyCore

/// Today's banner and light: which of the little places Coco is in today (`DailyBannerRotation`)
/// and whether it's morning, daytime, evening or night there (`BannerClock`), kept current
/// without a restart.
///
/// It re-checks when the day changes at midnight, when the Mac wakes, when the clock or time
/// zone is changed, and at each change of light (a timer set for the next boundary, re-armed
/// after every check). Everything is worked out from the local date and time, so reopening Coco
/// never changes today's banner.
@Observable
final class DailyBannerManager {
    private(set) var banner: BannerID
    private(set) var time: BannerTimeOfDay

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    #if DEBUG
    /// Debug: pin the banner, light or weather (launch arguments `--banner`, `--banner-time`,
    /// `--banner-weather`, or the Debug menu) to check every state by hand.
    struct Override: Equatable {
        var banner: BannerID?
        var time: BannerTimeOfDay?
        var weather: BannerWeather?
    }
    var override = Override() { didSet { refresh() } }
    #endif

    init(now: Date = .now) {
        banner = DailyBannerRotation.banner(on: now)
        time = BannerClock.timeOfDay(at: now)
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ flag: String) -> String? {
            arguments.firstIndex(of: flag).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        override = Override(banner: value("--banner").flatMap(BannerID.init(rawValue:)),
                            time: value("--banner-time").flatMap(BannerTimeOfDay.init(rawValue:)),
                            weather: value("--banner-weather").flatMap(BannerWeather.init(rawValue:)))
        #endif
        refresh(now: now)
    }

    func start() {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        let local = NotificationCenter.default
        let watch: [(NotificationCenter, Notification.Name)] = [
            (local, .NSCalendarDayChanged),
            (local, .NSSystemClockDidChange),
            (local, .NSSystemTimeZoneDidChange),
            (workspace, NSWorkspace.didWakeNotification),
            (workspace, NSWorkspace.screensDidWakeNotification),
        ]
        for (center, name) in watch {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            observers.append((center, token))
        }
        refresh()
    }

    func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        timer?.invalidate()
    }

    /// Works out the banner and light for `now`, and sets the timer for the next change of light.
    func refresh(now: Date = .now) {
        var calendar = Calendar.current
        calendar.timeZone = .current
        var banner = DailyBannerRotation.banner(on: now, calendar: calendar)
        var time = BannerClock.timeOfDay(at: now, calendar: calendar)
        #if DEBUG
        if let pinned = override.banner { banner = pinned }
        if let pinned = override.time { time = pinned }
        #endif
        if banner != self.banner { self.banner = banner }
        if time != self.time { self.time = time }

        timer?.invalidate()
        let next = min(BannerClock.nextChange(after: now, calendar: calendar),
                       calendar.startOfDay(for: now).addingTimeInterval(86_400 + 1))
        let timer = Timer(fire: next.addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 30
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// The frame to draw: today's banner in the current light, the weather (if any) and progress.
    func state(progress: BannerProgress, weather: WeatherSnapshot?) -> BannerState {
        var shown = weather?.bannerWeather ?? .sunny
        #if DEBUG
        if let pinned = override.weather { shown = pinned }
        #endif
        return BannerState(banner: banner, time: time, weather: shown, progress: progress)
    }

    /// The corner label's weather part for a store's current reading.
    func caption(_ store: WeatherStore, now: Date = .now) -> BannerCaption {
        #if DEBUG
        if let pinned = override.weather { return BannerCaption(weather: pinned.label.uppercased()) }
        #endif
        guard let reading = store.snapshot else {
            return BannerCaption(isLoading: store.status == .loading || store.status == .askingForLocation)
        }
        let temperature = TemperatureText.short(reading.temperatureC)
        // The art's own word where it says it best (as in the Make file: “SUNNY”); otherwise
        // the real condition, which the art approximates (“DRIZZLE”, “FOGGY”, “THUNDERSTORMS”).
        let name: String = switch reading.bannerWeather {
        case .sunny: time == .night ? "clear" : "sunny"
        case .windy: "windy"
        case .snowy: "snowy"
        case .cloudy, .rainy: reading.condition.label
        }
        let checked = reading.fetchedAt.formatted(date: .omitted, time: .shortened)
        let place = store.placeName.map { " for \($0)" } ?? ""
        let stale = reading.isStale(at: now)
        return BannerCaption(
            weather: "\(name.uppercased()) · \(temperature)",
            detail: "\(reading.condition.label.capitalized), \(temperature)\(place). Checked at \(checked)\(stale ? " — checking again soon" : "").",
            isStale: stale)
    }
}
