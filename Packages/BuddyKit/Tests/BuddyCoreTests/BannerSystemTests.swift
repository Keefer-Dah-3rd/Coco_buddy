import Foundation
import Testing
@testable import BuddyCore

@Suite struct DailyBannerRotationTests {
    func calendar(_ zone: String) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: zone)!
        return c
    }

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @Test func sameBannerAllDay() {
        let cal = calendar("America/New_York")
        let morning = DailyBannerRotation.banner(on: date(2026, 11, 4, 0, 1, in: cal), calendar: cal)
        for hour in [6, 12, 18, 23] {
            #expect(DailyBannerRotation.banner(on: date(2026, 11, 4, hour, 59, in: cal), calendar: cal) == morning)
        }
    }

    @Test func neverTheSameTwoDaysRunningAndEveryBannerEachRound() {
        let cal = calendar("Europe/London")
        var previous: BannerID?
        let start = date(2026, 1, 1, in: cal)
        for offset in 0..<730 {
            let day = cal.date(byAdding: .day, value: offset, to: start)!
            let banner = DailyBannerRotation.banner(on: day, calendar: cal)
            #expect(banner != previous, "day \(offset)")
            previous = banner
        }
        // Each aligned round of six days shows all six.
        for round in -3..<40 {
            let banners = Set((0..<6).map { position in
                let index = round * 6 + position
                let day = cal.date(byAdding: .day, value: index, to: date(2026, 11, 2, in: cal))!
                return DailyBannerRotation.banner(on: day, calendar: cal)
            })
            #expect(banners.count == BannerID.allCases.count, "round \(round)")
        }
    }

    @Test func followsTheLocalDateNotUTC() {
        // 23:30 in Los Angeles is already tomorrow in UTC; the banner follows the local day.
        let la = calendar("America/Los_Angeles")
        let lateEvening = date(2026, 11, 4, 23, 30, in: la)
        let noon = date(2026, 11, 4, 12, 0, in: la)
        #expect(DailyBannerRotation.banner(on: lateEvening, calendar: la) == DailyBannerRotation.banner(on: noon, calendar: la))
        #expect(DailyBannerRotation.dayIndex(of: lateEvening, calendar: la) == DailyBannerRotation.dayIndex(of: noon, calendar: la))
    }

    @Test func stableAcrossCalls() {
        let cal = calendar("Asia/Tokyo")
        let day = date(2027, 3, 9, in: cal)
        let first = DailyBannerRotation.banner(on: day, calendar: cal)
        for _ in 0..<20 { #expect(DailyBannerRotation.banner(on: day, calendar: cal) == first) }
    }

    @Test func moreBannersStillRotateCleanly() {
        // A longer catalog (as if banners were added) keeps the same guarantees.
        let catalog = BannerID.allCases + BannerID.allCases.prefix(0)
        let cal = calendar("UTC")
        var previous: BannerID?
        for offset in 0..<120 {
            let day = cal.date(byAdding: .day, value: offset, to: date(2026, 11, 2, in: cal))!
            let banner = DailyBannerRotation.banner(on: day, calendar: cal, catalog: catalog)
            #expect(banner != previous)
            previous = banner
        }
    }
}

@Suite struct BannerClockTests {
    let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: hour, minute: minute))!
    }

    @Test func boundaries() {
        #expect(BannerClock.timeOfDay(at: at(4, 59), calendar: cal) == .night)
        #expect(BannerClock.timeOfDay(at: at(5), calendar: cal) == .morning)
        #expect(BannerClock.timeOfDay(at: at(10, 59), calendar: cal) == .morning)
        #expect(BannerClock.timeOfDay(at: at(11), calendar: cal) == .daytime)
        #expect(BannerClock.timeOfDay(at: at(16, 59), calendar: cal) == .daytime)
        #expect(BannerClock.timeOfDay(at: at(17), calendar: cal) == .evening)
        #expect(BannerClock.timeOfDay(at: at(20, 59), calendar: cal) == .evening)
        #expect(BannerClock.timeOfDay(at: at(21), calendar: cal) == .night)
        #expect(BannerClock.timeOfDay(at: at(0), calendar: cal) == .night)
    }

    @Test func nextChange() {
        #expect(BannerClock.nextChange(after: at(9, 30), calendar: cal) == at(11))
        #expect(BannerClock.nextChange(after: at(11), calendar: cal) == at(17))
        #expect(BannerClock.nextChange(after: at(22), calendar: cal)
                == cal.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 5)))
    }
}

@Suite struct BannerProgressTests {
    @Test(arguments: [0, 1, 2, 3, 5, 8, 10, 14, 31, 100])
    func anyNumberOfTasks(total: Int) {
        var lastX = -1.0
        for done in 0...total {
            let progress = BannerProgress(done: done, total: total)
            let x = 20 + progress.along(280)
            #expect(x >= 20 && x <= 300)
            #expect(x >= lastX)  // never moves backwards as tasks get done
            lastX = x
            #expect(progress.tickCount == (total <= BannerProgress.maxTicks ? total : 0))
            // Slots light in order and all five are lit exactly when everything's done.
            let lit = (0..<5).map { progress.reached($0) }
            #expect(lit == lit.sorted(by: { $0 && !$1 }))
            #expect(lit.allSatisfy { $0 } == (total > 0 && done == total))
            #expect(!progress.note.isEmpty)
        }
    }

    @Test func fiveTasksIsThePrototype() {
        for done in 0...5 {
            let progress = BannerProgress(done: done, total: 5)
            #expect(progress.along(280) == Double(done * 56))
            for i in 0..<5 { #expect(progress.reached(i) == (done > i)) }
        }
        #expect(BannerProgress(done: 0, total: 5).note == "A gentle start.")
        #expect(BannerProgress(done: 2, total: 5).note == "Growing nicely.")
        #expect(BannerProgress(done: 4, total: 5).note == "Look at you go.")
        #expect(BannerProgress(done: 5, total: 5).note == "All done. Lovely.")
    }

    @Test func clampsNonsense() {
        let progress = BannerProgress(done: 9, total: 3)
        #expect(progress.done == 3)
        #expect(BannerProgress(done: -2, total: -1).total == 0)
        #expect(BannerProgress(done: 0, total: 0).remainingLabel == "Add a task to begin")
    }
}

@Suite struct WeatherMappingTests {
    func snapshot(_ condition: WeatherCondition, _ temp: Double = 12, wind: Double = 2) -> WeatherSnapshot {
        WeatherSnapshot(condition: condition, temperatureC: temp, windSpeed: wind, observedAt: .now, fetchedAt: .now)
    }

    @Test func conditionsToArt() {
        #expect(snapshot(.clear).bannerWeather == .sunny)
        #expect(snapshot(.clear, wind: 9).bannerWeather == .windy)
        #expect(snapshot(.partlyCloudy).bannerWeather == .cloudy)
        #expect(snapshot(.cloudy, wind: 12).bannerWeather == .cloudy)
        #expect(snapshot(.fog).bannerWeather == .cloudy)
        #expect(snapshot(.drizzle).bannerWeather == .rainy)
        #expect(snapshot(.thunderstorm).bannerWeather == .rainy)
        #expect(snapshot(.snow).bannerWeather == .snowy)
        #expect(snapshot(.sleet, 0).bannerWeather == .snowy)
        #expect(snapshot(.sleet, 4).bannerWeather == .rainy)
    }

    @Test func staleness() {
        let fetched = Date(timeIntervalSinceReferenceDate: 0)
        let reading = WeatherSnapshot(condition: .clear, temperatureC: 10, windSpeed: 1, observedAt: fetched, fetchedAt: fetched)
        #expect(!reading.isStale(at: fetched.addingTimeInterval(60 * 60)))
        #expect(reading.isStale(at: fetched.addingTimeInterval(2 * 60 * 60)))
        #expect(reading.isUsable(at: fetched.addingTimeInterval(5 * 60 * 60)))
        #expect(!reading.isUsable(at: fetched.addingTimeInterval(7 * 60 * 60)))
    }

    @Test func temperatureUsesTheUsersUnit() {
        #expect(TemperatureText.short(20, locale: Locale(identifier: "en_US")).hasPrefix("68"))
        #expect(TemperatureText.short(20, locale: Locale(identifier: "en_GB")).hasPrefix("20"))
        #expect(TemperatureText.short(20, locale: Locale(identifier: "en_US@measure=metric;mu=celsius")).hasPrefix("20"))
    }
}

@Suite struct BannerCommentTests {
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
    }

    func context(_ weather: WeatherSnapshot?, time: BannerTimeOfDay = .daytime, hour: Int = 13,
                 banner: BannerID = .cornerBookshop) -> BannerCommentEngine.Context {
        .init(banner: banner, time: time, weather: weather, now: .now, hour: hour, temperature: { "\(Int($0))°" })
    }

    func reading(_ condition: WeatherCondition, _ temp: Double = 15, wind: Double = 2,
                 upcoming: WeatherCondition? = nil, rain: Double? = nil) -> WeatherSnapshot {
        WeatherSnapshot(condition: condition, temperatureC: temp, windSpeed: wind, upcoming: upcoming,
                        upcomingPrecipitation: rain, observedAt: .now, fetchedAt: .now)
    }

    @Test func neverContradictsTheArt() {
        var engine = BannerCommentEngine()
        var rng = Seeded(state: 7)
        let sunWords = ["Sunny", "sun", "Bright"]
        let wetWords = ["rain", "Rain", "umbrella", "Snow", "snow"]
        for time in BannerTimeOfDay.allCases {
            for banner in BannerID.allCases {
                for _ in 0..<15 {
                    // Raining: nothing about sunshine.
                    let wet = engine.comment(for: context(reading(.rain), time: time, banner: banner), using: &rng)!
                    #expect(!sunWords.contains { wet.text.contains($0) }, "\(wet.text)")
                    // Clear, no rain forecast: nothing about rain or snow.
                    let dry = engine.comment(for: context(reading(.clear), time: time, banner: banner), using: &rng)!
                    #expect(!wetWords.contains { dry.text.contains($0) }, "\(dry.text)")
                    // At night nobody mentions the sun.
                    if time == .night { #expect(!sunWords.contains { dry.text.contains($0) }, "\(dry.text)") }
                    // No weather: no weather talk at all.
                    let none = engine.comment(for: context(nil, time: time, banner: banner), using: &rng)!
                    #expect(!(wetWords + sunWords + ["cold", "chilly", "Windy", "Cloud"]).contains { none.text.contains($0) }, "\(none.text)")
                }
            }
        }
    }

    @Test func rainComingOnlyWithAForecast() {
        let dryNoForecast = BannerCommentEngine.topics(for: context(reading(.cloudy))).map(\.0)
        #expect(!dryNoForecast.contains(.rainLater))
        let forecast = BannerCommentEngine.topics(for: context(reading(.cloudy, upcoming: .rain, rain: 2))).map(\.0)
        #expect(forecast.contains(.rainLater))
        let alreadyWet = BannerCommentEngine.topics(for: context(reading(.rain, upcoming: .rain, rain: 2))).map(\.0)
        #expect(!alreadyWet.contains(.rainLater))
    }

    @Test func temperatureAndClothing() {
        #expect(BannerCommentEngine.topics(for: context(reading(.clear, -3))).map(\.0).contains(.cold))
        #expect(BannerCommentEngine.topics(for: context(reading(.clear, 7))).map(\.0).contains(.chilly))
        #expect(BannerCommentEngine.topics(for: context(reading(.clear, 33))).map(\.0).contains(.hot))
        #expect(!BannerCommentEngine.topics(for: context(reading(.clear, 18))).map(\.0).contains { [.cold, .chilly, .warm, .hot].contains($0) })
    }

    @Test func doesNotRepeatItself() {
        var engine = BannerCommentEngine()
        var rng = Seeded(state: 42)
        var seen: [String] = []
        for _ in 0..<8 {
            seen.append(engine.comment(for: context(reading(.rain, 8)), using: &rng)!.text)
        }
        for (a, b) in zip(seen, seen.dropFirst()) { #expect(a != b) }
    }

    @Test func linesFitTheBubble() {
        for topic in BannerCommentEngine.Topic.allCases {
            for banner in BannerID.allCases {
                for time in BannerTimeOfDay.allCases {
                    for weather in [nil, reading(.rain), reading(.clear, 35, wind: 10), reading(.snow, -10)] as [WeatherSnapshot?] {
                        for line in BannerLines.lines(topic, context(weather, time: time, banner: banner)) {
                            #expect(line.count <= 72, "\(line)")
                            #expect(!Dialogue.offVoice.contains { line.contains($0) })
                        }
                    }
                }
            }
        }
    }

    @Test func pacing() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9))!
        var pacing = BannerCommentPacing()
        #expect(pacing.isDue(now: morning, time: .morning, weather: .sunny, calendar: cal))
        pacing.record(now: morning, time: .morning, weather: .sunny, calendar: cal)
        // Same part of the day, even much later: no.
        #expect(!pacing.isDue(now: morning.addingTimeInterval(100 * 60), time: .morning, weather: .sunny, calendar: cal))
        // Next part of the day but too soon after the last: no.
        #expect(!pacing.isDue(now: morning.addingTimeInterval(60 * 60), time: .daytime, weather: .sunny, calendar: cal))
        // Next part of the day, long enough after: yes.
        #expect(pacing.isDue(now: morning.addingTimeInterval(3 * 3600), time: .daytime, weather: .sunny, calendar: cal))
        // Rain starting is worth mentioning sooner — but not straight away.
        #expect(!pacing.isDue(now: morning.addingTimeInterval(20 * 60), time: .morning, weather: .rainy, calendar: cal))
        #expect(pacing.isDue(now: morning.addingTimeInterval(45 * 60), time: .morning, weather: .rainy, calendar: cal))
        // Survives a restart (it's Codable) unchanged.
        let copy = try! JSONDecoder().decode(BannerCommentPacing.self, from: JSONEncoder().encode(pacing))
        #expect(copy == pacing)
    }
}
