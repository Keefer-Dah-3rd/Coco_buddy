import Foundation

/// Which banner a day gets. One banner a day, the same all day however often Coco is opened,
/// working through every banner before any comes round again, and never the same one two days
/// running.
///
/// Days are counted in the user's own calendar and time zone, so the banner changes at their
/// midnight. The order within each round of banners is shuffled from the round number (a fixed
/// seed, not the clock or a random generator), so it reads as a fresh sequence yet is the same
/// on every launch and every Mac. Adding banners to `BannerID` reshuffles future days.
public enum DailyBannerRotation {
    /// The first day of round 0 — any fixed date works; this is the day the banners arrived.
    static let epoch = DateComponents(year: 2026, month: 11, day: 2)

    public static func banner(on date: Date, calendar: Calendar = .current,
                              catalog: [BannerID] = BannerID.allCases) -> BannerID {
        precondition(!catalog.isEmpty)
        let index = dayIndex(of: date, calendar: calendar)
        let count = catalog.count
        let round = Int(floor(Double(index) / Double(count)))
        let position = index - round * count
        return order(round: round, catalog: catalog)[position]
    }

    /// Whole days since the epoch, in `calendar`'s time zone (negative before it).
    public static func dayIndex(of date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.date(from: epoch).map { calendar.startOfDay(for: $0) } ?? .distantPast
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: day).day ?? 0
    }

    /// The banners in the order round `round` shows them. A round never starts with the banner
    /// the round before ended on.
    static func order(round: Int, catalog: [BannerID]) -> [BannerID] {
        var order = shuffled(catalog, seed: UInt64(bitPattern: Int64(round)))
        if catalog.count > 1 {
            let previousLast = shuffled(catalog, seed: UInt64(bitPattern: Int64(round - 1))).last
            if order.first == previousLast { order.swapAt(0, 1) }
            // The swap could only matter for the round's own last banner when there are two.
        }
        return order
    }

    private static func shuffled(_ items: [BannerID], seed: UInt64) -> [BannerID] {
        var generator = SplitMix64(seed: seed &+ 0x9E37_79B9_7F4A_7C15)
        return items.shuffled(using: &generator)
    }
}

/// A small, fixed pseudo-random sequence (SplitMix64): the same seed always gives the same
/// shuffle, on every platform and Swift version.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Morning, daytime, evening or night by the local clock.
///
/// Boundaries (local time): morning 5:00–11:00, daytime 11:00–17:00, evening 17:00–21:00,
/// night 21:00–5:00. They follow the Make file's four lights and Coco's greetings, and don't
/// need a location, so the light is right even with weather off.
public enum BannerClock {
    /// The hour each light starts, in order through the day.
    public static let starts: [(hour: Int, time: BannerTimeOfDay)] = [
        (5, .morning), (11, .daytime), (17, .evening), (21, .night),
    ]

    public static func timeOfDay(at date: Date, calendar: Calendar = .current) -> BannerTimeOfDay {
        let hour = calendar.component(.hour, from: date)
        return starts.last { $0.hour <= hour }?.time ?? .night
    }

    /// When the light next changes after `date` — a timer goes off then, and again after waking.
    public static func nextChange(after date: Date, calendar: Calendar = .current) -> Date {
        let candidates = starts.compactMap { start in
            calendar.nextDate(after: date, matching: DateComponents(hour: start.hour, minute: 0, second: 0),
                              matchingPolicy: .nextTime)
        }
        return candidates.min() ?? date.addingTimeInterval(3600)
    }
}
