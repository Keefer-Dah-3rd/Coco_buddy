import Foundation

/// Weather as it really is outside — finer than the banner art's five weathers. Providers
/// (MET Norway today) map their own codes onto these.
public enum WeatherCondition: String, Codable, Sendable, CaseIterable {
    case clear
    case partlyCloudy
    case cloudy
    case fog
    case drizzle
    case rain
    case heavyRain
    case sleet
    case snow
    case thunderstorm

    public var isWet: Bool {
        switch self {
        case .drizzle, .rain, .heavyRain, .sleet, .thunderstorm: true
        default: false
        }
    }

    /// A plain description for VoiceOver and Settings: “light rain”, “partly cloudy”…
    public var label: String {
        switch self {
        case .clear: "clear"
        case .partlyCloudy: "partly cloudy"
        case .cloudy: "cloudy"
        case .fog: "foggy"
        case .drizzle: "drizzle"
        case .rain: "rain"
        case .heavyRain: "heavy rain"
        case .sleet: "sleet"
        case .snow: "snow"
        case .thunderstorm: "thunderstorms"
        }
    }
}

/// One reading of the local weather, plus what the next few hours hold when the provider says.
public struct WeatherSnapshot: Codable, Equatable, Sendable {
    public var condition: WeatherCondition
    /// Air temperature, °C. Shown in the user's own unit; Coco's thresholds use Celsius.
    public var temperatureC: Double
    /// Wind speed, metres per second.
    public var windSpeed: Double
    /// The most likely condition over the next hours, if the forecast has one.
    public var upcoming: WeatherCondition?
    /// Precipitation expected over the next hours, mm, if forecast.
    public var upcomingPrecipitation: Double?
    /// The forecast's lowest and highest temperature for the rest of today, °C.
    public var laterLowC: Double?
    public var laterHighC: Double?
    /// When the provider made this reading (not when we fetched it).
    public var observedAt: Date
    /// When we got it.
    public var fetchedAt: Date

    public init(condition: WeatherCondition, temperatureC: Double, windSpeed: Double,
                upcoming: WeatherCondition? = nil, upcomingPrecipitation: Double? = nil,
                laterLowC: Double? = nil, laterHighC: Double? = nil,
                observedAt: Date, fetchedAt: Date) {
        self.condition = condition
        self.temperatureC = temperatureC
        self.windSpeed = windSpeed
        self.upcoming = upcoming
        self.upcomingPrecipitation = upcomingPrecipitation
        self.laterLowC = laterLowC
        self.laterHighC = laterHighC
        self.observedAt = observedAt
        self.fetchedAt = fetchedAt
    }

    /// Wind this strong (≈ 30 km/h, a “strong breeze” in Beaufort 6 terms is 10.8) shows as the
    /// windy art when nothing is falling.
    public static let windyAt: Double = 8.0

    /// Older than this and the reading is stale: still shown, but refreshed as soon as possible.
    public static let staleAfter: TimeInterval = 90 * 60
    /// Older than this and it's no longer trusted at all: the banner goes back to its plain look.
    public static let expiresAfter: TimeInterval = 6 * 3600

    public func age(at now: Date) -> TimeInterval { now.timeIntervalSince(fetchedAt) }
    public func isStale(at now: Date) -> Bool { age(at: now) > Self.staleAfter }
    public func isUsable(at now: Date) -> Bool { age(at: now) < Self.expiresAfter }

    /// The banner art for this weather. The Make file draws sunny, cloudy, rainy, snowy and
    /// windy; the rest use the closest of those (documented in docs/BANNERS.md):
    /// partly cloudy, overcast and fog → cloudy (the cloudy art keeps a soft sun);
    /// drizzle, rain, heavy rain, thunderstorms → rainy (there's no storm art);
    /// sleet → snowy at or below 1 °C, else rainy; clear or partly cloudy with a strong breeze
    /// → windy (the windy art is the clear scene with gusts).
    public var bannerWeather: BannerWeather {
        switch condition {
        case .snow: return .snowy
        case .sleet: return temperatureC <= 1 ? .snowy : .rainy
        case .drizzle, .rain, .heavyRain, .thunderstorm: return .rainy
        case .partlyCloudy: return windSpeed >= Self.windyAt ? .windy : .cloudy
        case .cloudy, .fog: return .cloudy
        case .clear: return windSpeed >= Self.windyAt ? .windy : .sunny
        }
    }
}

/// Temperatures in the unit the user picked in System Settings › General › Language & Region.
public enum TemperatureText {
    /// “12°” in the user's unit (no letter, like the menu bar), rounded.
    public static func short(_ celsius: Double, locale: Locale = .current) -> String {
        Measurement(value: celsius, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
    }

    /// The user's unit, for Settings: “°C” or “°F”.
    public static func unitSymbol(locale: Locale = .current) -> String {
        UnitTemperature(forLocale: locale, usage: .weather).symbol
    }
}
