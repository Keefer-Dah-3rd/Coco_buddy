import Foundation
import BuddyCore

/// The Norwegian Meteorological Institute's Locationforecast 2.0 (api.met.no): free worldwide
/// forecasts, no account or key, licensed CC BY 4.0 (credit “MET Norway”). Their terms ask for
/// an identifying User-Agent, at most four decimals of latitude/longitude, and no request before
/// the previous answer's `Expires` — `WeatherService` keeps all three.
/// https://api.met.no/doc/TermsOfService · https://api.met.no/weatherapi/locationforecast/2.0/documentation
public enum METNorway {
    public static let attribution = "Weather data from MET Norway (CC BY 4.0)"

    /// Coordinates rounded to two decimals (about a kilometre): plenty for weather, and it means
    /// the forecast service never sees a precise location.
    public static func request(latitude: Double, longitude: Double, userAgent: String,
                               ifModifiedSince: String? = nil) -> URLRequest {
        var components = URLComponents(string: "https://api.met.no/weatherapi/locationforecast/2.0/compact")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: rounded(latitude)),
            URLQueryItem(name: "lon", value: rounded(longitude)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let ifModifiedSince { request.setValue(ifModifiedSince, forHTTPHeaderField: "If-Modified-Since") }
        return request
    }

    public static func rounded(_ degrees: Double) -> String {
        String(format: "%.2f", (degrees * 100).rounded() / 100)
    }

    /// The reading for `now` from a compact forecast: the hour in progress for the condition,
    /// temperature and wind; the next six hours for what's coming; the rest of the local day
    /// for the low and high.
    public static func snapshot(from data: Data, now: Date, calendar: Calendar = .current) throws -> WeatherSnapshot {
        let forecast: Forecast
        do {
            forecast = try JSONDecoder.met.decode(Forecast.self, from: data)
        } catch {
            throw IntegrationError.invalidResponse("The weather forecast couldn't be read.")
        }
        let series = forecast.properties.timeseries.sorted { $0.time < $1.time }
        // The hour that's under way (or the first one, if the forecast starts later).
        guard let current = series.last(where: { $0.time <= now }) ?? series.first,
              let details = current.data.instant?.details,
              let temperature = details.air_temperature else {
            throw IntegrationError.invalidResponse("The weather forecast was empty.")
        }
        guard let symbol = current.data.next_1_hours?.summary?.symbol_code
                ?? current.data.next_6_hours?.summary?.symbol_code,
              let condition = condition(symbol) else {
            throw IntegrationError.invalidResponse("The weather forecast had no conditions.")
        }
        let upcoming = current.data.next_6_hours?.summary?.symbol_code.flatMap(Self.condition)
        let endOfDay = calendar.startOfDay(for: now).addingTimeInterval(86_400)
        let rest = series.filter { $0.time >= current.time && $0.time < endOfDay }
            .compactMap { $0.data.instant?.details?.air_temperature }
        return WeatherSnapshot(
            condition: condition,
            temperatureC: temperature,
            windSpeed: details.wind_speed ?? 0,
            upcoming: upcoming,
            upcomingPrecipitation: current.data.next_6_hours?.details?.precipitation_amount,
            laterLowC: rest.min(),
            laterHighC: rest.max(),
            observedAt: forecast.properties.meta?.updated_at ?? current.time,
            fetchedAt: now)
    }

    /// MET's symbol codes (`lightrainshowers_day`, `heavysnowandthunder`, `fair_night`…) as
    /// conditions. Thunder wins, then sleet, snow and rain by strength, then fog and cloud.
    public static func condition(_ symbol: String) -> WeatherCondition? {
        let code = symbol.split(separator: "_").first.map(String.init) ?? symbol
        if code.contains("thunder") { return .thunderstorm }
        if code.contains("sleet") { return .sleet }
        if code.contains("snow") { return .snow }
        if code.contains("heavyrain") { return .heavyRain }
        if code.contains("lightrain") { return .drizzle }
        if code.contains("rain") { return .rain }
        switch code {
        case "fog": return .fog
        case "cloudy": return .cloudy
        case "partlycloudy": return .partlyCloudy
        case "fair", "clearsky": return .clear
        default: return nil
        }
    }

    // MARK: Wire format (only what's used)

    struct Forecast: Decodable {
        struct Properties: Decodable {
            struct Meta: Decodable { var updated_at: Date? }
            var meta: Meta?
            var timeseries: [Step]
        }
        var properties: Properties
    }

    struct Step: Decodable {
        struct Payload: Decodable {
            struct Instant: Decodable {
                struct Details: Decodable {
                    var air_temperature: Double?
                    var wind_speed: Double?
                }
                var details: Details?
            }
            struct Period: Decodable {
                struct Summary: Decodable { var symbol_code: String? }
                struct Details: Decodable { var precipitation_amount: Double? }
                var summary: Summary?
                var details: Details?
            }
            var instant: Instant?
            var next_1_hours: Period?
            var next_6_hours: Period?
        }
        var time: Date
        var data: Payload
    }
}

private extension JSONDecoder {
    static let met: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
