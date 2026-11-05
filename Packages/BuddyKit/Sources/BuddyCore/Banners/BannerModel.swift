import Foundation

/// The illustrated task banners at the top of Today: little places Coco spends the day in.
/// Each is ported from the Figma Make file “Illustrated Task Card Concepts” (8qgFt7CDBmWWB55sQO6sAg)
/// and keeps its Make number and title. Add a case (and its art in `BannerArt`) to add a banner;
/// the daily rotation picks it up by itself.
public enum BannerID: String, CaseIterable, Codable, Sendable, Identifiable {
    case tidalPool
    case windowNook
    case slowFerry
    case cornerBookshop
    case laundryInTheSky
    case quietCarriage

    public var id: Self { self }

    public var title: String {
        switch self {
        case .tidalPool: "A Little Tidal Pool"
        case .windowNook: "Coco’s Window Nook"
        case .slowFerry: "The Slow Ferry"
        case .cornerBookshop: "The Corner Bookshop"
        case .laundryInTheSky: "Laundry in the Sky"
        case .quietCarriage: "The Quiet Carriage"
        }
    }

    /// What the scene is, for VoiceOver.
    public var accessibilityDescription: String {
        switch self {
        case .tidalPool: "A low-tide pool with a paper boat and a coral star."
        case .windowNook: "Coco’s window nook: a cushion, a plant and a tennis ball by a big window."
        case .slowFerry: "A small orange ferry crossing a harbour towards a lighthouse."
        case .cornerBookshop: "A corner bookshop with a striped awning and five arched windows."
        case .laundryInTheSky: "A rooftop clothesline over the city."
        case .quietCarriage: "The view from a quiet train carriage, with a cup of tea on the table."
        }
    }
}

/// The four lights the art is drawn in. “Daytime” is the Make file's name for the afternoon light.
public enum BannerTimeOfDay: String, CaseIterable, Codable, Sendable {
    case morning, daytime, evening, night

    /// As the Make file and Figma write it: “Morning”, “Daytime”…
    public var label: String { rawValue.capitalized }
}

/// The five weathers the art is drawn in. Real conditions map onto these in
/// `WeatherSnapshot.bannerWeather` (storms show as rain, fog as cloud…).
public enum BannerWeather: String, CaseIterable, Codable, Sendable {
    case sunny, cloudy, rainy, snowy, windy

    public var label: String { rawValue.capitalized }
}

/// What a banner frame shows.
public struct BannerState: Equatable, Sendable {
    public var banner: BannerID
    public var time: BannerTimeOfDay
    public var weather: BannerWeather
    public var progress: BannerProgress

    public init(banner: BannerID, time: BannerTimeOfDay, weather: BannerWeather, progress: BannerProgress) {
        self.banner = banner
        self.time = time
        self.weather = weather
        self.progress = progress
    }

    /// The art without the progress — what a change of light or weather crossfades between.
    public var look: Look { Look(banner: banner, time: time, weather: weather) }

    public struct Look: Hashable, Sendable {
        public var banner: BannerID
        public var time: BannerTimeOfDay
        public var weather: BannerWeather

        public init(banner: BannerID, time: BannerTimeOfDay, weather: BannerWeather) {
            self.banner = banner
            self.time = time
            self.weather = weather
        }
    }
}

/// Today's progress as the banner draws it, for any number of tasks.
///
/// The Make prototype was built for five tasks (`x = 20 + done * 56`). Here everything is a
/// share of the rail instead: the thumb, the fill and the ferry move by `done / total`; there's
/// one tick per task (up to `maxTicks`, then the rail is continuous); and art drawn with five
/// slots of its own — the bookshop's windows, the laundry, the ticket punches — lights each
/// slot once that fifth of the day is done. With five tasks this is exactly the prototype.
public struct BannerProgress: Equatable, Sendable {
    public var done: Int
    public var total: Int

    /// Above this many tasks the rail drops its ticks rather than crowd them.
    public static let maxTicks = 30

    public init(done: Int, total: Int) {
        self.total = max(0, total)
        self.done = min(max(0, done), self.total)
    }

    public var fraction: Double { total == 0 ? 0 : Double(done) / Double(total) }
    public var isEmpty: Bool { total == 0 }
    public var remaining: Int { total - done }

    /// `span · done / total`, multiplied first so five tasks give the prototype's whole numbers.
    public func along(_ span: Double) -> Double {
        total == 0 ? 0 : Double(done) * span / Double(total)
    }

    /// Whether slot `index` of art drawn with `slots` places is lit (the prototype's `done > i`).
    public func reached(_ index: Int, of slots: Int = 5) -> Bool {
        total > 0 && done * slots >= (index + 1) * total
    }

    /// Ticks along the rail: one per task, the last at the end.
    public var tickCount: Int { total <= Self.maxTicks ? total : 0 }

    /// Coco's note in the banner (the Make file's `getCocoNote`, by share instead of count).
    public var note: String {
        if total == 0 { return "Nothing on the list yet." }
        if done == 0 { return "A gentle start." }
        if done == total { return "All done. Lovely." }
        return fraction < 0.5 ? "Growing nicely." : "Look at you go."
    }

    /// The small line under the light and weather.
    public var remainingLabel: String {
        if total == 0 { return "Add a task to begin" }
        return done == total ? "All complete" : "\(remaining) remaining"
    }
}
