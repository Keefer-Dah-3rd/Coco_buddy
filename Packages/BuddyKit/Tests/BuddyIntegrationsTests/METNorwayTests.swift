import Foundation
import Testing
import BuddyCore
@testable import BuddyIntegrations

@Suite struct METNorwayTests {
    /// The shape api.met.no returns (trimmed), with rain arriving in the afternoon.
    static let sample = """
    {"type":"Feature","properties":{"meta":{"updated_at":"2026-11-04T10:30:36Z","units":{"air_temperature":"celsius"}},
     "timeseries":[
      {"time":"2026-11-04T09:00:00Z","data":{"instant":{"details":{"air_temperature":3.1,"wind_speed":1.2}},
        "next_1_hours":{"summary":{"symbol_code":"clearsky_day"},"details":{"precipitation_amount":0.0}}}},
      {"time":"2026-11-04T10:00:00Z","data":{"instant":{"details":{"air_temperature":4.5,"wind_speed":2.4}},
        "next_1_hours":{"summary":{"symbol_code":"partlycloudy_day"},"details":{"precipitation_amount":0.0}},
        "next_6_hours":{"summary":{"symbol_code":"lightrain"},"details":{"precipitation_amount":2.6}}}},
      {"time":"2026-11-04T14:00:00Z","data":{"instant":{"details":{"air_temperature":7.9,"wind_speed":5.0}},
        "next_1_hours":{"summary":{"symbol_code":"rain"},"details":{"precipitation_amount":1.1}}}},
      {"time":"2026-11-04T22:00:00Z","data":{"instant":{"details":{"air_temperature":1.0,"wind_speed":3.0}},
        "next_1_hours":{"summary":{"symbol_code":"cloudy"},"details":{"precipitation_amount":0.0}}}},
      {"time":"2026-11-05T06:00:00Z","data":{"instant":{"details":{"air_temperature":-4.0,"wind_speed":3.0}},
        "next_6_hours":{"summary":{"symbol_code":"snow"},"details":{"precipitation_amount":3.0}}}}
     ]}}
    """

    var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func readsTheHourUnderWay() throws {
        let now = ISO8601DateFormatter().date(from: "2026-11-04T10:20:00Z")!
        let reading = try METNorway.snapshot(from: Data(Self.sample.utf8), now: now, calendar: utc)
        #expect(reading.condition == .partlyCloudy)
        #expect(reading.temperatureC == 4.5)
        #expect(reading.windSpeed == 2.4)
        #expect(reading.upcoming == .drizzle)
        #expect(reading.upcomingPrecipitation == 2.6)
        // Rest of the (UTC) day: 4.5, 7.9, 1.0 — tomorrow's -4 doesn't count.
        #expect(reading.laterLowC == 1.0)
        #expect(reading.laterHighC == 7.9)
        #expect(reading.fetchedAt == now)
        #expect(reading.observedAt == ISO8601DateFormatter().date(from: "2026-11-04T10:30:36Z"))
    }

    @Test func symbolCodes() {
        #expect(METNorway.condition("clearsky_night") == .clear)
        #expect(METNorway.condition("fair_day") == .clear)
        #expect(METNorway.condition("partlycloudy_polartwilight") == .partlyCloudy)
        #expect(METNorway.condition("cloudy") == .cloudy)
        #expect(METNorway.condition("fog") == .fog)
        #expect(METNorway.condition("lightrainshowers_day") == .drizzle)
        #expect(METNorway.condition("rainshowers_night") == .rain)
        #expect(METNorway.condition("heavyrain") == .heavyRain)
        #expect(METNorway.condition("lightssleetshowersandthunder_day") == .thunderstorm)
        #expect(METNorway.condition("heavysleet") == .sleet)
        #expect(METNorway.condition("lightsnow") == .snow)
        #expect(METNorway.condition("somethingnew") == nil)
    }

    @Test func requestKeepsTheTerms() {
        let request = METNorway.request(latitude: 40.712776, longitude: -74.005974, userAgent: "DesktopBuddy/1.0 test")
        #expect(request.url?.absoluteString == "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=40.71&lon=-74.01")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "DesktopBuddy/1.0 test")
    }

    @Test func badDataIsAnError() {
        #expect(throws: IntegrationError.self) {
            try METNorway.snapshot(from: Data("{}".utf8), now: .now)
        }
        #expect(throws: IntegrationError.self) {
            try METNorway.snapshot(from: Data(#"{"properties":{"timeseries":[]}}"#.utf8), now: .now)
        }
    }
}
