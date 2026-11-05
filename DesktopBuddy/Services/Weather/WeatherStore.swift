import AppKit
import CoreLocation
import Foundation
import Observation
import os
import BuddyCore
import BuddyIntegrations

/// The local weather for Today's banner and Coco's comments.
///
/// Off until the user turns it on (Settings › Weather, or the offer under the banner); then it
/// asks once for approximate location — or uses a city they typed — and downloads a forecast.
/// The forecast is kept on disk and read hour by hour, so the network is only asked again when
/// the reading is getting old (and never before the server's `Expires`): roughly every hour or
/// two while Coco is running, after the Mac wakes if the reading is old, and when the panel opens
/// on a stale reading. Failures back off (5, 15, 30 minutes) and keep showing the last good
/// reading for up to six hours, marked as stale.
@Observable
final class WeatherStore {
    enum Status: Equatable {
        /// Weather is turned off.
        case off
        /// Waiting for the user to answer the location prompt.
        case askingForLocation
        /// Location is off for Coco (or for the Mac) and no city is set.
        case locationDenied
        /// Getting the first reading.
        case loading
        /// Showing a reading (check `snapshot` for staleness).
        case ready
        /// Couldn't get weather; `snapshot` may still hold the last good reading.
        case unavailable(String)
    }

    private(set) var status: Status = .off
    /// The reading for right now, if there's one recent enough to trust.
    private(set) var snapshot: WeatherSnapshot?
    /// “Brooklyn”, “Lisbon” — where the weather is for, when known.
    private(set) var placeName: String?
    var attribution: String { provider.attribution }
    var isOn: Bool { preferences.weatherEnabled }

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let provider: any WeatherProvider
    @ObservationIgnored private let location: LocationProvider?
    @ObservationIgnored private let file: JSONFileStore<Cached>?
    @ObservationIgnored private var cached: Cached?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var nextAttempt = Date.distantPast
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var timer: Timer?
    /// The last location fix, reused for a while instead of asking location services each time.
    @ObservationIgnored private var lastFix: (latitude: Double, longitude: Double, at: Date)?
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "weather")

    /// Refresh the reading from the network once it's this old.
    static let refreshAfter: TimeInterval = 45 * 60
    /// After waking, refresh if older than this (the Mac may have moved, or hours passed).
    static let refreshAfterWake: TimeInterval = 20 * 60
    /// Use the last known location for this long before asking for a new fix.
    static let locationLifetime: TimeInterval = 3 * 3600

    private struct Cached: Codable {
        var forecast: Data
        var fetchedAt: Date
        var expires: Date?
        var lastModified: String?
        var latitude: Double
        var longitude: Double
        var placeName: String?
    }

    init(preferences: Preferences, provider: any WeatherProvider = METNorwayProvider(), persistent: Bool = true,
         locationAccess: Bool = true) {
        self.preferences = preferences
        self.provider = provider
        location = locationAccess ? LocationProvider() : nil
        file = persistent ? try? JSONFileStore(name: "weather-forecast") : nil
        cached = try? file?.load()
        placeName = preferences.weatherPlace?.name ?? cached?.placeName
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(olderThan: Self.refreshAfter) }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // The Mac may be somewhere new: read the location again next time.
                self?.lastFix = nil
                self?.refresh(olderThan: Self.refreshAfterWake)
            }
        }
        refresh(olderThan: Self.refreshAfter)
    }

    // MARK: Turning it on and off

    /// Turns weather on from the Mac's location, asking for access if it hasn't been asked.
    func turnOnWithMacLocation() async {
        preferences.weatherPlace = nil
        preferences.weatherEnabled = true
        if location?.access == .notAsked {
            status = .askingForLocation
            _ = await location?.requestAccess()
        }
        nextAttempt = .distantPast
        await refreshNow()
    }

    /// Turns weather on for a city the user typed (no location access needed).
    /// Returns a message if the city couldn't be found.
    func turnOn(city: String) async -> String? {
        let name = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Type a town or city." }
        do {
            let found = try await CLGeocoder().geocodeAddressString(name)
            guard let place = found.first, let coordinate = place.location?.coordinate else {
                return "Couldn't find “\(name)”."
            }
            preferences.weatherPlace = WeatherPlace(name: place.locality ?? place.name ?? name,
                                                    latitude: coordinate.latitude, longitude: coordinate.longitude)
            placeName = preferences.weatherPlace?.name
            preferences.weatherEnabled = true
            cached = nil
            nextAttempt = .distantPast
            await refreshNow()
            return nil
        } catch {
            return "Couldn't look up “\(name)” — check your connection."
        }
    }

    func turnOff() {
        preferences.weatherEnabled = false
        status = .off
        snapshot = nil
    }

    /// Part of “Delete all my data”.
    func eraseAll() {
        turnOff()
        cached = nil
        placeName = nil
        try? file?.delete()
    }

    var locationAccess: LocationProvider.Access { location?.access ?? .denied }

    // MARK: Refreshing

    /// Rereads the current hour from the saved forecast, and downloads a new one if the reading
    /// is older than `age` (and the server's `Expires` and any back-off have passed).
    func refresh(olderThan age: TimeInterval) {
        guard preferences.weatherEnabled else {
            status = .off
            snapshot = nil
            return
        }
        readCached()
        let now = Date.now
        let old = cached.map { now.timeIntervalSince($0.fetchedAt) > age } ?? true
        let expired = cached?.expires.map { now >= $0 } ?? true
        guard old, expired, now >= nextAttempt, !refreshing else { return }
        Task { await refreshNow() }
    }

    /// When the panel opens: only if the reading has gone stale.
    func refreshIfStale() {
        refresh(olderThan: WeatherSnapshot.staleAfter)
    }

    private func refreshNow() async {
        guard preferences.weatherEnabled, !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if snapshot == nil { status = .loading }
        do {
            let (latitude, longitude, name) = try await coordinates()
            let sameSpot = cached.map { abs($0.latitude - latitude) < 0.01 && abs($0.longitude - longitude) < 0.01 } ?? false
            let download = try await provider.download(latitude: latitude, longitude: longitude,
                                                       ifModifiedSince: sameSpot ? cached?.lastModified : nil)
            let now = Date.now
            if let data = download.data {
                _ = try provider.snapshot(from: data, now: now)  // check it reads before keeping it
                cached = Cached(forecast: data, fetchedAt: now, expires: download.expires, lastModified: download.lastModified,
                                latitude: latitude, longitude: longitude, placeName: name ?? cached?.placeName)
            } else if var same = cached {
                same.fetchedAt = now
                same.expires = download.expires ?? same.expires
                cached = same
            }
            try? cached.map { try file?.save($0) }
            if cached?.placeName != nil { placeName = cached?.placeName }
            failures = 0
            nextAttempt = .distantPast
            status = .ready
            readCached()
            if name == nil, preferences.weatherPlace == nil { Task { await nameThePlace(latitude, longitude) } }
        } catch LocationProvider.Failure.notAllowed(let access) {
            status = access == .notAsked ? .askingForLocation : .locationDenied
            snapshot = nil
        } catch {
            failures += 1
            let backOff: TimeInterval = [5, 15, 30][min(failures, 3) - 1] * 60
            nextAttempt = .now.addingTimeInterval(backOff)
            readCached()
            let reason = (error as? IntegrationError)?.userMessage
                ?? (error is LocationProvider.Failure ? "Couldn't find where this Mac is right now." : error.localizedDescription)
            status = .unavailable(reason)
            log.notice("weather refresh failed: \(reason, privacy: .public)")
        }
    }

    /// The forecast's reading for this hour, if it's recent enough to trust.
    private func readCached() {
        guard preferences.weatherEnabled, let cached else {
            snapshot = nil
            return
        }
        let now = Date.now
        guard var reading = try? provider.snapshot(from: cached.forecast, now: now) else {
            snapshot = nil
            return
        }
        reading.fetchedAt = cached.fetchedAt
        guard reading.isUsable(at: now) else {
            snapshot = nil
            return
        }
        if snapshot != reading { snapshot = reading }
        switch status {
        case .unavailable, .locationDenied: break
        default: status = .ready
        }
    }

    private func coordinates() async throws -> (Double, Double, String?) {
        if let place = preferences.weatherPlace { return (place.latitude, place.longitude, place.name) }
        guard let location else { throw LocationProvider.Failure.notAllowed(.denied) }
        guard location.access == .allowed else { throw LocationProvider.Failure.notAllowed(location.access) }
        let sameAsCached: (Double, Double) -> String? = { [cached] lat, lon in
            guard let cached, abs(cached.latitude - lat) < 0.05, abs(cached.longitude - lon) < 0.05 else { return nil }
            return cached.placeName
        }
        // Reuse a recent fix rather than waking location services every refresh.
        if let fix = lastFix, Date.now.timeIntervalSince(fix.at) < Self.locationLifetime {
            return (fix.latitude, fix.longitude, sameAsCached(fix.latitude, fix.longitude))
        }
        do {
            let fix = try await location.currentLocation()
            lastFix = (fix.coordinate.latitude, fix.coordinate.longitude, .now)
            return (fix.coordinate.latitude, fix.coordinate.longitude, sameAsCached(fix.coordinate.latitude, fix.coordinate.longitude))
        } catch {
            // No fix right now (indoors, offline Wi-Fi scan…): the last known place will do.
            if let cached { return (cached.latitude, cached.longitude, cached.placeName) }
            throw error
        }
    }

    private func nameThePlace(_ latitude: Double, _ longitude: Double) async {
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(CLLocation(latitude: latitude, longitude: longitude)).first,
              let name = mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea else { return }
        placeName = name
        cached?.placeName = name
        try? cached.map { try file?.save($0) }
    }
}
