import Foundation
import BuddyCore
import BuddyIntegrations

/// Somewhere the user picked to get weather for, instead of the Mac's own location.
struct WeatherPlace: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
}

/// One forecast download.
struct WeatherDownload: Sendable {
    /// The forecast, or nil when the server said nothing changed (304).
    var data: Data?
    /// Don't ask again before this (the server's `Expires`).
    var expires: Date?
    /// For `If-Modified-Since` next time.
    var lastModified: String?
}

/// Where forecasts come from. The banner, Coco's comments and Settings only ever see
/// `WeatherSnapshot`s, so swapping MET Norway for another service is one new conformance.
protocol WeatherProvider: Sendable {
    /// Shown in Settings, as the data's licence asks.
    var attribution: String { get }
    func download(latitude: Double, longitude: Double, ifModifiedSince: String?) async throws -> WeatherDownload
    /// The reading for `now` from a downloaded forecast. Forecasts cover days ahead, so one
    /// download keeps the banner right hour by hour without asking the network again.
    func snapshot(from data: Data, now: Date) throws -> WeatherSnapshot
}

/// api.met.no — free, worldwide, no key. See `METNorway` for their terms.
struct METNorwayProvider: WeatherProvider {
    var attribution: String { METNorway.attribution }

    /// MET asks for an app name and a way to reach its maker.
    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "DesktopBuddy/\(version) (+https://keefer-dah-3rd.github.io/Coco_buddy/support/)"
    }

    func download(latitude: Double, longitude: Double, ifModifiedSince: String?) async throws -> WeatherDownload {
        let request = METNorway.request(latitude: latitude, longitude: longitude, userAgent: Self.userAgent,
                                        ifModifiedSince: ifModifiedSince)
        let (data, response) = try await HTTP.fetch(request)
        let expires = response.value(forHTTPHeaderField: "Expires").flatMap(Self.httpDate)
        return WeatherDownload(data: data, expires: expires,
                               lastModified: response.value(forHTTPHeaderField: "Last-Modified"))
    }

    func snapshot(from data: Data, now: Date) throws -> WeatherSnapshot {
        try METNorway.snapshot(from: data, now: now)
    }

    static func httpDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text)
    }
}

#if DEBUG
/// Made-up weather for previews, snapshots and `--banner-weather`. Never used for real readings:
/// `WeatherStore` only takes it when told to by a Debug launch argument.
struct MockWeatherProvider: WeatherProvider {
    var reading: WeatherSnapshot

    var attribution: String { "Test weather (Debug)" }

    func download(latitude: Double, longitude: Double, ifModifiedSince: String?) async throws -> WeatherDownload {
        WeatherDownload(data: try JSONEncoder().encode(reading), expires: nil, lastModified: nil)
    }

    func snapshot(from data: Data, now: Date) throws -> WeatherSnapshot {
        var reading = try JSONDecoder().decode(WeatherSnapshot.self, from: data)
        reading.fetchedAt = now
        return reading
    }

    /// A reading that shows `weather` in the art.
    static func reading(_ weather: BannerWeather, temperatureC: Double = 12) -> WeatherSnapshot {
        let condition: WeatherCondition = switch weather {
        case .sunny, .windy: .clear
        case .cloudy: .cloudy
        case .rainy: .rain
        case .snowy: .snow
        }
        return WeatherSnapshot(condition: condition, temperatureC: weather == .snowy ? -2 : temperatureC,
                               windSpeed: weather == .windy ? 11 : 2, observedAt: .now, fetchedAt: .now)
    }
}
#endif
