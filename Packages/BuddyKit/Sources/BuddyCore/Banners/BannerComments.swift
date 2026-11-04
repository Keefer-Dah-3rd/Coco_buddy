import Foundation

/// Coco's remarks about what's going on outside — the weather, the temperature, the time of
/// day and today's banner — in her voice, not a weather app's.
///
/// Every line is chosen from what the banner is actually showing: rain lines only when the art
/// is rainy, sun lines only in daylight when it's clear, “rain is coming” only when the forecast
/// says so. With no weather (off, denied, offline) she sticks to the time of day and the scene.
///
/// The copy is all in `BannerLines` below — edit it freely. Keep lines short enough for her
/// speech bubble (about 70 characters), one thought each, light on exclamation marks.
public struct BannerCommentEngine: Sendable {
    public struct Context: Sendable {
        public var banner: BannerID
        public var time: BannerTimeOfDay
        /// The weather the banner shows, or nil when it shows none.
        public var weather: WeatherSnapshot?
        public var now: Date
        public var hour: Int
        /// Formats a Celsius temperature in the user's unit (“12°”).
        public var temperature: @Sendable (Double) -> String

        public init(banner: BannerID, time: BannerTimeOfDay, weather: WeatherSnapshot?, now: Date, hour: Int,
                    temperature: @escaping @Sendable (Double) -> String = { TemperatureText.short($0) }) {
            self.banner = banner
            self.time = time
            self.weather = weather
            self.now = now
            self.hour = hour
            self.temperature = temperature
        }

        /// The art's weather, when weather is known.
        public var shown: BannerWeather? { weather?.bannerWeather }
    }

    public enum Topic: String, CaseIterable, Sendable {
        case storm, rainNow, rainLater, snowNow, windy, fog, gloomy
        case cold, chilly, warm, hot
        case clearMorning, clearDaytime, clearEvening, clearNight
        case windDown, lateNight
        case scene
        case noWeatherMorning, noWeatherDaytime
    }

    public struct Comment: Equatable, Sendable {
        public var text: String
        public var topic: Topic
    }

    private var recentLines: [String] = []
    private var recentTopics: [Topic] = []

    public init() {}

    /// Topics that fit right now, most pressing first, each with a weight.
    public static func topics(for context: Context) -> [(Topic, Double)] {
        var topics: [(Topic, Double)] = []
        let late = context.hour >= 22 || context.hour < 5
        if let weather = context.weather, let shown = context.shown {
            switch shown {
            case .rainy:
                topics.append(weather.condition == .thunderstorm ? (.storm, 6) : (.rainNow, 6))
            case .snowy:
                topics.append((.snowNow, 6))
            case .windy:
                topics.append((.windy, 4))
            case .cloudy:
                topics.append(weather.condition == .fog ? (.fog, 4) : (.gloomy, 3))
            case .sunny:
                switch context.time {
                case .morning: topics.append((.clearMorning, 3))
                case .daytime: topics.append((.clearDaytime, 3))
                case .evening: topics.append((.clearEvening, 3))
                case .night: topics.append((.clearNight, 2))
                }
            }
            // Rain on its way: only when it isn't already wet and the forecast says so.
            if !weather.condition.isWet, shown != .snowy, let upcoming = weather.upcoming, upcoming.isWet,
               upcoming != .sleet || weather.temperatureC > 1,
               (weather.upcomingPrecipitation ?? 1) >= 0.3 {
                topics.append((.rainLater, 7))
            }
            switch weather.temperatureC {
            case ..<3: topics.append((.cold, 5))
            case ..<11: topics.append((.chilly, 3))
            case 30...: topics.append((.hot, 5))
            case 25...: topics.append((.warm, 3))
            default: break
            }
        } else {
            switch context.time {
            case .morning: topics.append((.noWeatherMorning, 3))
            case .daytime: topics.append((.noWeatherDaytime, 3))
            case .evening, .night: break
            }
        }
        if context.time == .evening { topics.append((.windDown, 2)) }
        if late { topics.append((.lateNight, 4)) }
        if !BannerLines.scene(context).isEmpty { topics.append((.scene, 2)) }
        return topics
    }

    /// A remark for the moment, avoiding the topics and lines used lately.
    public mutating func comment<G: RandomNumberGenerator>(for context: Context, using generator: inout G) -> Comment? {
        let candidates = Self.topics(for: context)
        guard !candidates.isEmpty else { return nil }
        // Prefer topics she hasn't just talked about; fall back to any that fit.
        let fresh = candidates.filter { !recentTopics.suffix(2).contains($0.0) }
        let pool = fresh.isEmpty ? candidates : fresh
        var order: [Topic] = []
        var remaining = pool
        while !remaining.isEmpty {
            let total = remaining.reduce(0) { $0 + $1.1 }
            var roll = Double.random(in: 0..<total, using: &generator)
            let index = remaining.firstIndex { roll -= $0.1; return roll < 0 } ?? 0
            order.append(remaining.remove(at: index).0)
        }
        for topic in order {
            let lines = BannerLines.lines(topic, context)
            let unused = lines.filter { !recentLines.contains($0) }
            guard let line = (unused.isEmpty ? lines : unused).randomElement(using: &generator) else { continue }
            recentLines.append(line)
            if recentLines.count > 24 { recentLines.removeFirst(recentLines.count - 24) }
            recentTopics.append(topic)
            if recentTopics.count > 6 { recentTopics.removeFirst() }
            return Comment(text: line, topic: topic)
        }
        return nil
    }

    public mutating func comment(for context: Context) -> Comment? {
        var generator = SystemRandomNumberGenerator()
        return comment(for: context, using: &generator)
    }
}

/// When Coco may remark on the weather: rarely, and never twice for the same thing.
///
/// - At most once in each part of the day (morning, daytime, evening, night) — four a day at most.
/// - At least `minimumGap` apart, however the parts fall.
/// - Sooner (after `changeGap`) only for a real change worth hearing about: rain or snow
///   starting, or a storm.
/// The caller adds the usual manners: never during focus, a meeting, while the panel is open
/// or while the user is away (see `AppModel.environmentTick`).
public struct BannerCommentPacing: Codable, Equatable, Sendable {
    public var lastCommentAt: Date?
    /// "2026-11-04 evening": the part of the day last remarked on.
    public var lastPeriod: String?
    /// The art's weather when she last spoke.
    public var lastWeather: BannerWeather?

    public static let minimumGap: TimeInterval = 90 * 60
    public static let changeGap: TimeInterval = 40 * 60

    public init() {}

    public static func periodKey(_ date: Date, time: BannerTimeOfDay, calendar: Calendar = .current) -> String {
        // Night after midnight belongs to the evening before it.
        var day = date
        if time == .night, calendar.component(.hour, from: date) < 12 {
            day = calendar.date(byAdding: .day, value: -1, to: date) ?? date
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d %@", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0, time.rawValue)
    }

    public func isDue(now: Date, time: BannerTimeOfDay, weather: BannerWeather?, calendar: Calendar = .current) -> Bool {
        guard let last = lastCommentAt else { return true }
        let since = now.timeIntervalSince(last)
        if since < 0 { return true }  // the clock went back; start over
        let turnedWet = (weather == .rainy || weather == .snowy) && weather != lastWeather
        if turnedWet, since >= Self.changeGap { return true }
        guard since >= Self.minimumGap else { return false }
        return Self.periodKey(now, time: time, calendar: calendar) != lastPeriod
    }

    public mutating func record(now: Date, time: BannerTimeOfDay, weather: BannerWeather?, calendar: Calendar = .current) {
        lastCommentAt = now
        lastPeriod = Self.periodKey(now, time: time, calendar: calendar)
        lastWeather = weather
    }
}

/// The words. Each pool is plain text; `\(t)` style values are filled from the reading.
public enum BannerLines {
    public static func lines(_ topic: BannerCommentEngine.Topic, _ context: BannerCommentEngine.Context) -> [String] {
        let t = context.weather.map { context.temperature($0.temperatureC) } ?? ""
        switch topic {
        case .storm: return [
            "Thunder about. I'm being very brave. Mostly.",
            "Stormy out there. Good day to stay in and tick things off.",
            "Big storm noises. I'll be under the desk, supervising.",
        ]
        case .rainNow: return [
            "It's raining. Don't forget an umbrella if you head out!",
            "Rainy day. Cosy weather for getting things checked off.",
            "Rain on the windows. I'm staying right here, thanks.",
            "Wet out there. My paws are staying dry today.",
        ]
        case .rainLater: return [
            "Looks like rain is coming. Don't forget an umbrella!",
            "Rain's on the way later. Outside errands first, maybe?",
            "I can smell rain coming. Well, the forecast can.",
        ]
        case .snowNow: return [
            "Snow! I would like to roll in it immediately.",
            "It's snowing. Boots and a warm coat if you head out.",
            "Snowy day. Everything's quieter. Good for focus.",
        ]
        case .windy: return [
            "Windy out there. Hold on to your hat.",
            "Breezy today. My ears are doing a lot.",
            "Blustery one. A hood might beat an umbrella today.",
        ]
        case .fog: return [
            "Foggy out. Let's take it slow, one thing at a time.",
            "Can't see much out there. Good thing the list is in here.",
        ]
        case .gloomy: return [
            "A little gloomy outside, but we've got this.",
            "Grey skies. Still good light for getting things done.",
            "Cloudy and calm. Nice and steady today.",
        ]
        case .cold: return [
            "Brr. It's \(t) out there. Big coat, please.",
            "Properly cold today. Grab a coat. I've got mine on. It's fur.",
            "It's \(t). Warm drink, short list, cosy socks.",
        ]
        case .chilly: return [
            "It's a little chilly today. Maybe grab a coat.",
            "Bit nippy out. A jumper kind of day.",
            "\(t) and crisp. My ears approve.",
        ]
        case .warm: return [
            "Warm one today. Don't forget some water.",
            "It's \(t) and lovely. Shady spot for me, please.",
        ]
        case .hot: return [
            "It's \(t) out. Water for you, water for me.",
            "Too hot for zoomies. Let's keep things gentle.",
        ]
        case .clearMorning: return [
            "Sunny morning! Perfect weather for getting things done.",
            "Bright out there. Good morning for a fresh start.",
        ]
        case .clearDaytime: return [
            "Perfect weather for getting things done.",
            "Lovely day out there. A little walk later, maybe?",
        ]
        case .clearEvening: return [
            "A quiet evening for getting things checked off.",
            "Nice clear evening. Good time to wrap up gently.",
        ]
        case .clearNight: return [
            "Clear night. The stars are out. So is the couch.",
            "Clear skies tonight. Nice and still.",
        ]
        case .windDown: return [
            "Evening's here. What's the one last thing?",
            "Getting on in the day. Let's keep the list small.",
        ]
        case .lateNight: return [
            "It's getting late. Maybe it's time to wind down.",
            "Late one. Write tomorrow's first thing and rest?",
        ]
        case .noWeatherMorning: return [
            "Morning! Fresh page today.",
            "New day, new little place. What's first?",
        ]
        case .noWeatherDaytime: return [
            "Middle of the day. Good time for one more thing.",
            "Afternoon already. We're doing fine.",
        ]
        case .scene: return scene(context)
        }
    }

    /// Lines about today's banner, only where they fit what it's showing.
    public static func scene(_ context: BannerCommentEngine.Context) -> [String] {
        let shown = context.shown
        let dark = context.time == .night
        var lines: [String] = []
        switch context.banner {
        case .slowFerry:
            lines.append("Slow ferry today. We get there when we get there.")
            if shown == .rainy { lines.append("Rainy crossing. The ferry doesn't mind, so neither do I.") }
            if shown == .windy { lines.append("Choppy water today. Hold on tight.") }
            if dark { lines.append("The lighthouse is on. Steady as we go.") }
        case .cornerBookshop:
            lines.append("Bookshop day. One good page at a time.")
            if shown == .rainy { lines.append("Rainy day at the bookshop. One more chapter?") }
            if dark { lines.append("The bookshop's still open. Very cosy.") }
        case .laundryInTheSky:
            if shown == .windy { lines.append("Great drying weather. The laundry's having a lovely time.") }
            if shown == .rainy { lines.append("Not a great day for laundry. Good day for lists.") }
            if shown == .sunny, !dark { lines.append("Sunny rooftop. The washing's drying nicely.") }
            if shown == nil { lines.append("Rooftop day. Small things, lighter days.") }
        case .quietCarriage:
            lines.append("Quiet carriage today. Shh. Focus mode.")
            if shown == .snowy { lines.append("Snow going past the window. Very cosy in here.") }
            if shown == .rainy { lines.append("Rain on the train window. Good for thinking.") }
        case .windowNook:
            lines.append("Window nook day. Best seat in the house.")
            if shown == .rainy { lines.append("Watching the rain from the nook. Ten out of ten.") }
            if shown == .sunny, !dark { lines.append("Sun in the window. Prime nap real estate.") }
        case .tidalPool:
            lines.append("Tide's out. Little steps today.")
            if shown == .rainy { lines.append("Rain on the tide pool. Little ripples everywhere.") }
        }
        return lines
    }
}
