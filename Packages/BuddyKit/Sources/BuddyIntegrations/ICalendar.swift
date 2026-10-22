import Foundation

/// A small iCalendar (RFC 5545) reader for subscription feeds — the user's personal Partiful
/// calendar link, or a Google Calendar "secret address": events with their times, place, link
/// and description. Repeating events are expanded with `expand(_:from:to:calendar:)` (the
/// common rules: daily, weekly, monthly, yearly, with exceptions and moved occurrences);
/// alarms and time-zone blocks are skipped.
public enum ICalendar {
    public struct Event: Codable, Equatable, Sendable {
        public enum Status: String, Codable, Equatable, Sendable { case confirmed, tentative, cancelled }

        public var uid: String
        public var title: String
        public var start: Date
        public var end: Date
        /// False when the feed gave no DTEND (the end then comes from DURATION, or equals the start).
        public var endListed: Bool
        public var isAllDay: Bool
        public var location: String?
        public var url: URL?
        public var description: String?
        public var status: Status
        /// RRULE, for the first event of a repeating series.
        public var rule: String?
        /// EXDATE: occurrences of the series that were removed.
        public var exceptions: [Date]?
        /// RECURRENCE-ID: this event replaces the series' occurrence originally at this time.
        public var recurrenceID: Date?
        /// The zone the start was written in (TZID), so repeats keep their local time across DST.
        public var timeZoneID: String?
        /// Set on events made by `expand`: the occurrence's original start.
        public var occurrence: Date?

        public var isRepeating: Bool { rule != nil || recurrenceID != nil || occurrence != nil }

        public init(uid: String, title: String, start: Date, end: Date, endListed: Bool = true, isAllDay: Bool = false,
                    location: String? = nil, url: URL? = nil, description: String? = nil, status: Status = .confirmed,
                    rule: String? = nil, exceptions: [Date]? = nil, recurrenceID: Date? = nil, timeZoneID: String? = nil,
                    occurrence: Date? = nil) {
            self.uid = uid
            self.title = title
            self.start = start
            self.end = end
            self.endListed = endListed
            self.isAllDay = isAllDay
            self.location = location
            self.url = url
            self.description = description
            self.status = status
            self.rule = rule
            self.exceptions = exceptions
            self.recurrenceID = recurrenceID
            self.timeZoneID = timeZoneID
            self.occurrence = occurrence
        }
    }

    public struct Feed: Equatable, Sendable {
        /// X-WR-CALNAME, when the feed names itself.
        public var name: String?
        /// PRODID — "Partiful" for Partiful's feeds.
        public var producer: String?
        public var events: [Event]
    }

    /// Nil when the text isn't an iCalendar file at all.
    public static func parse(_ text: String, calendar: Calendar = .current) -> Feed? {
        let lines = unfold(text)
        guard lines.contains(where: { $0.uppercased() == "BEGIN:VCALENDAR" }) else { return nil }
        var feed = Feed(name: nil, producer: nil, events: [])
        var current: [Property]?
        var nested = 0
        for line in lines {
            guard let property = Property(line) else { continue }
            switch (property.name, property.value.uppercased()) {
            case ("BEGIN", "VEVENT") where current == nil:
                current = []
            case ("END", "VEVENT") where nested == 0:
                if let properties = current, let event = event(from: properties, calendar: calendar) { feed.events.append(event) }
                current = nil
            case ("BEGIN", _) where current != nil:
                nested += 1  // VALARM and friends: their properties aren't the event's.
            case ("END", _) where current != nil && nested > 0:
                nested -= 1
            default:
                if current != nil {
                    if nested == 0 { current?.append(property) }
                } else if property.name == "X-WR-CALNAME" {
                    feed.name = unescape(property.value)
                } else if property.name == "PRODID" {
                    feed.producer = property.value
                }
            }
        }
        return feed
    }

    // MARK: - Lines and properties

    /// Splits into content lines, joining folded continuations (a line starting with a space or tab).
    static func unfold(_ text: String) -> [String] {
        var lines: [String] = []
        for raw in text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1] += raw.dropFirst()
            } else if !raw.isEmpty {
                lines.append(String(raw))
            }
        }
        return lines
    }

    struct Property {
        var name: String
        var parameters: [String: String]
        var value: String

        init?(_ line: String) {
            // NAME;PARAM=VALUE;PARAM="quoted:value":the value — the first colon outside quotes ends the name part.
            var inQuotes = false
            var split: String.Index?
            for index in line.indices {
                let character = line[index]
                if character == "\"" { inQuotes.toggle() }
                if character == ":" && !inQuotes { split = index; break }
            }
            guard let split else { return nil }
            var head = [String]()
            var piece = ""
            inQuotes = false
            for character in line[..<split] {
                if character == "\"" { inQuotes.toggle(); continue }
                if character == ";" && !inQuotes { head.append(piece); piece = ""; continue }
                piece.append(character)
            }
            head.append(piece)
            name = head[0].uppercased()
            parameters = [:]
            for parameter in head.dropFirst() {
                let parts = parameter.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { parameters[parts[0].uppercased()] = parts[1] }
            }
            value = String(line[line.index(after: split)...])
        }
    }

    private static func event(from properties: [Property], calendar: Calendar) -> Event? {
        func first(_ name: String) -> Property? { properties.first { $0.name == name } }
        guard let startProperty = first("DTSTART"), let (start, allDay) = date(startProperty, calendar: calendar) else { return nil }
        let uid = first("UID")?.value.trimmingCharacters(in: .whitespaces) ?? ""
        let title = first("SUMMARY").map { unescape($0.value) }?.trimmingCharacters(in: .whitespacesAndNewlines)
        var end: Date
        var endListed = false
        if let endProperty = first("DTEND"), let (value, _) = date(endProperty, calendar: calendar), value > start {
            end = value
            endListed = true
        } else if let duration = first("DURATION").flatMap({ duration($0.value) }), duration > 0 {
            end = start.addingTimeInterval(duration)
        } else {
            // RFC 5545: a date-only event lasts the day; a timed one with no end is a moment.
            end = allDay ? (calendar.date(byAdding: .day, value: 1, to: start) ?? start) : start
        }
        let status: Event.Status = switch first("STATUS")?.value.uppercased() {
        case "CANCELLED": .cancelled
        case "TENTATIVE": .tentative
        default: .confirmed
        }
        let location = first("LOCATION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        let description = first("DESCRIPTION").map { unescape($0.value) }.flatMap { $0.isEmpty ? nil : $0 }
        let url = first("URL").flatMap { URL(string: $0.value.trimmingCharacters(in: .whitespaces)) }
            .flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        let exceptions = properties.filter { $0.name == "EXDATE" }.flatMap { dates($0, calendar: calendar) }
        let zone: String? = allDay ? nil
            : startProperty.value.uppercased().hasSuffix("Z") ? "UTC"
            : startProperty.parameters["TZID"].flatMap { TimeZone(identifier: $0)?.identifier }
        return Event(uid: uid, title: (title?.isEmpty ?? true) ? "Untitled event" : title!, start: start, end: end,
                     endListed: endListed, isAllDay: allDay, location: location, url: url, description: description, status: status,
                     rule: first("RRULE")?.value, exceptions: exceptions.isEmpty ? nil : exceptions,
                     recurrenceID: first("RECURRENCE-ID").flatMap { date($0, calendar: calendar)?.0 }, timeZoneID: zone)
    }

    /// Every value of a property that may list several dates ("EXDATE:20261020T090000Z,20261027T090000Z").
    static func dates(_ property: Property, calendar: Calendar) -> [Date] {
        property.value.split(separator: ",").compactMap { value in
            var single = property
            single.value = String(value)
            return date(single, calendar: calendar)?.0
        }
    }

    /// "20261025T210000Z" (UTC), "20261025T140000" with TZID (or floating: the user's zone),
    /// or "20261025" for a whole day.
    static func date(_ property: Property, calendar: Calendar) -> (Date, allDay: Bool)? {
        let value = property.value.trimmingCharacters(in: .whitespaces)
        let digits = value.filter(\.isNumber)
        guard digits.count >= 8, let year = Int(digits.prefix(4)), let month = Int(digits.dropFirst(4).prefix(2)),
              let day = Int(digits.dropFirst(6).prefix(2)) else { return nil }
        var zoned = Calendar(identifier: .gregorian)
        if property.parameters["VALUE"]?.uppercased() == "DATE" || !value.contains("T") {
            zoned.timeZone = calendar.timeZone
            guard let date = zoned.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return (date, true)
        }
        guard digits.count >= 14, let hour = Int(digits.dropFirst(8).prefix(2)), let minute = Int(digits.dropFirst(10).prefix(2)),
              let second = Int(digits.dropFirst(12).prefix(2)) else { return nil }
        if value.uppercased().hasSuffix("Z") {
            zoned.timeZone = TimeZone(identifier: "UTC")!
        } else {
            zoned.timeZone = property.parameters["TZID"].flatMap(TimeZone.init(identifier:)) ?? calendar.timeZone
        }
        guard let date = zoned.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))
        else { return nil }
        return (date, false)
    }

    /// "PT2H", "P1DT30M", "P1W" → seconds.
    static func duration(_ text: String) -> TimeInterval? {
        var value = text.trimmingCharacters(in: .whitespaces).uppercased()
        var sign: Double = 1
        if value.hasPrefix("-") { sign = -1; value.removeFirst() } else if value.hasPrefix("+") { value.removeFirst() }
        guard value.hasPrefix("P") else { return nil }
        var total: Double = 0
        var number = ""
        var inTime = false
        for character in value.dropFirst() {
            if character.isNumber { number.append(character); continue }
            if character == "T" { inTime = true; continue }
            guard let amount = Double(number) else { return nil }
            number = ""
            switch (character, inTime) {
            case ("W", false): total += amount * 7 * 86_400
            case ("D", false): total += amount * 86_400
            case ("H", true): total += amount * 3_600
            case ("M", true): total += amount * 60
            case ("S", true): total += amount
            default: return nil
            }
        }
        return number.isEmpty ? sign * total : nil
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var escaping = false
        for character in text {
            if escaping {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}

// MARK: - Repeating events

extension ICalendar {
    /// Every event touching `from..<to`: one-off events as they are, repeating series expanded
    /// into occurrences (removed ones left out, moved or edited ones taken from their override),
    /// cancelled occurrences dropped. Unsupported rules show only their first occurrence.
    public static func expand(_ events: [Event], from: Date, to: Date, calendar: Calendar = .current) -> [Event] {
        var overrides: [String: [Date: Event]] = [:]
        for event in events where event.recurrenceID != nil {
            overrides[event.uid, default: [:]][event.recurrenceID!] = event
        }
        var result: [Event] = []
        for event in events where event.recurrenceID == nil {
            guard let ruleText = event.rule, let rule = Rule(ruleText) else {
                if event.end > from && event.start < to { result.append(event) }
                continue
            }
            let length = event.end.timeIntervalSince(event.start)
            let removed = Set(event.exceptions ?? [])
            for start in rule.starts(of: event, until: to, calendar: calendar) {
                guard start.addingTimeInterval(max(length, 1)) > from, !removed.contains(start) else { continue }
                if let replacement = overrides[event.uid]?[start] {
                    var moved = replacement
                    moved.occurrence = start
                    if moved.status != .cancelled, moved.end > from, moved.start < to { result.append(moved) }
                    continue
                }
                var occurrence = event
                occurrence.start = start
                occurrence.end = start.addingTimeInterval(length)
                occurrence.occurrence = start
                occurrence.rule = nil
                occurrence.exceptions = nil
                result.append(occurrence)
            }
        }
        // Overrides whose series isn't in the feed (or that moved into the window from outside it).
        let masters = Set(events.filter { $0.recurrenceID == nil }.map(\.uid))
        for (uid, moved) in overrides where !masters.contains(uid) {
            for event in moved.values where event.status != .cancelled && event.end > from && event.start < to {
                var standalone = event
                standalone.occurrence = event.recurrenceID
                result.append(standalone)
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// RRULE: FREQ, INTERVAL, COUNT, UNTIL, BYDAY (with ordinals for monthly/yearly),
    /// BYMONTHDAY and BYMONTH.
    struct Rule {
        enum Frequency: String { case daily = "DAILY", weekly = "WEEKLY", monthly = "MONTHLY", yearly = "YEARLY" }

        var frequency: Frequency
        var interval = 1
        var count: Int?
        var until: Date?
        /// (ordinal, weekday 1 = Sunday … 7 = Saturday); ordinal 0 means "every".
        var byDay: [(Int, Int)] = []
        var byMonthDay: [Int] = []
        var byMonth: [Int] = []

        init?(_ text: String) {
            var parts: [String: String] = [:]
            for piece in text.split(separator: ";") {
                let pair = piece.split(separator: "=", maxSplits: 1).map(String.init)
                if pair.count == 2 { parts[pair[0].uppercased()] = pair[1].uppercased() }
            }
            guard let frequency = parts["FREQ"].flatMap(Frequency.init(rawValue:)) else { return nil }
            // Rules this reader doesn't understand: better one occurrence than wrong ones.
            let known: Set<String> = ["FREQ", "INTERVAL", "COUNT", "UNTIL", "BYDAY", "BYMONTHDAY", "BYMONTH", "WKST"]
            guard Set(parts.keys).isSubset(of: known) else { return nil }
            self.frequency = frequency
            interval = max(1, Int(parts["INTERVAL"] ?? "1") ?? 1)
            count = parts["COUNT"].flatMap(Int.init)
            if let value = parts["UNTIL"] {
                let property = Property("UNTIL:" + value)!
                until = ICalendar.date(property, calendar: Calendar(identifier: .gregorian)).map { value.contains("T") ? $0.0 : $0.0.addingTimeInterval(86_399) }
            }
            let days = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]
            for token in (parts["BYDAY"] ?? "").split(separator: ",") {
                let code = String(token.suffix(2))
                guard let weekday = days[code] else { return nil }
                byDay.append((Int(token.dropLast(2)) ?? 0, weekday))
            }
            byMonthDay = (parts["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }
            byMonth = (parts["BYMONTH"] ?? "").split(separator: ",").compactMap { Int($0) }
        }

        /// Occurrence starts from the series' first, in order, up to `limit` (or COUNT/UNTIL).
        func starts(of event: Event, until limit: Date, calendar userCalendar: Calendar) -> [Date] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = event.timeZoneID.flatMap(TimeZone.init(identifier:)) ?? userCalendar.timeZone
            calendar.firstWeekday = 2  // WKST=MO, the default
            let first = event.start
            let time = calendar.dateComponents([.hour, .minute, .second], from: first)
            let end = min(limit, until ?? limit)
            var found: [Date] = []
            var period = 0
            func at(_ day: DateComponents) -> Date? {
                var parts = day
                parts.hour = time.hour; parts.minute = time.minute; parts.second = time.second
                guard let date = calendar.date(from: parts),
                      calendar.component(.day, from: date) == parts.day else { return nil }  // no Feb 30
                return date
            }
            while period < 5_000 {
                defer { period += 1 }
                let candidates = dates(inPeriod: period, from: first, calendar: calendar).compactMap(at).sorted()
                if let earliest = candidates.first, earliest > end { break }
                for date in candidates where date >= first {
                    if date > end { return found }
                    found.append(date)
                    if let count, found.count >= count { return found }
                }
                // Periods whose dates all fall before the start (or don't exist) still move us on.
                if candidates.isEmpty, let periodStart = calendar.date(byAdding: unit, value: period * interval, to: first), periodStart > end { break }
            }
            return found
        }

        private var unit: Calendar.Component {
            switch frequency {
            case .daily: .day
            case .weekly: .weekOfYear
            case .monthly: .month
            case .yearly: .year
            }
        }

        /// The calendar days (year, month, day) in the n-th period after the first occurrence.
        private func dates(inPeriod period: Int, from first: Date, calendar: Calendar) -> [DateComponents] {
            guard let anchor = calendar.date(byAdding: unit, value: period * interval, to: first) else { return [] }
            let day = calendar.dateComponents([.year, .month, .day, .weekday], from: anchor)
            switch frequency {
            case .daily:
                if !byDay.isEmpty, !byDay.contains(where: { $0.1 == day.weekday }) { return [] }
                if !byMonth.isEmpty, !byMonth.contains(day.month!) { return [] }
                return [DateComponents(year: day.year, month: day.month, day: day.day)]
            case .weekly:
                guard let week = calendar.dateInterval(of: .weekOfYear, for: anchor) else { return [] }
                let weekdays = byDay.isEmpty ? [day.weekday!] : byDay.map(\.1)
                return weekdays.compactMap { weekday in
                    let offset = (weekday - calendar.firstWeekday + 7) % 7
                    return calendar.date(byAdding: .day, value: offset, to: week.start)
                        .map { calendar.dateComponents([.year, .month, .day], from: $0) }
                }
            case .monthly:
                if !byMonth.isEmpty, !byMonth.contains(day.month!) { return [] }
                return daysInMonth(year: day.year!, month: day.month!, defaultDay: calendar.component(.day, from: first), calendar: calendar)
            case .yearly:
                let months = byMonth.isEmpty ? [calendar.component(.month, from: first)] : byMonth
                return months.flatMap { daysInMonth(year: day.year!, month: $0, defaultDay: calendar.component(.day, from: first), calendar: calendar) }
            }
        }

        private func daysInMonth(year: Int, month: Int, defaultDay: Int, calendar: Calendar) -> [DateComponents] {
            guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                  let length = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count else { return [] }
            var days: [Int] = []
            if !byMonthDay.isEmpty {
                days = byMonthDay.map { $0 > 0 ? $0 : length + 1 + $0 }
            } else if !byDay.isEmpty {
                for (ordinal, weekday) in byDay {
                    let matching = (1...length).filter { day in
                        calendar.component(.weekday, from: calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)!) == weekday
                    }
                    if ordinal == 0 { days += matching }
                    else if ordinal > 0, ordinal <= matching.count { days.append(matching[ordinal - 1]) }
                    else if ordinal < 0, -ordinal <= matching.count { days.append(matching[matching.count + ordinal]) }
                }
            } else {
                days = [defaultDay]
            }
            return days.filter { (1...length).contains($0) }.map { DateComponents(year: year, month: month, day: $0) }
        }
    }
}

/// Checks a calendar subscription link the user pasted (e.g. their personal Partiful calendar
/// link): https only (webcal:// is read as https), a real public host name, no credentials,
/// and not an invitation page by mistake.
public enum CalendarFeedLink {
    public enum Problem: Error, Equatable, Sendable {
        case notALink
        /// They pasted one invitation (partiful.com/e/…) instead of their calendar link.
        case invitationLink
        /// localhost, a raw IP address, or a local network name.
        case notPublic
    }

    public static func validate(_ text: String) -> Result<URL, Problem> {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>\"'")))
        if Partiful.link(from: raw) != nil { return .failure(.invitationLink) }
        for prefix in ["webcals://", "webcal://", "http://"] where raw.lowercased().hasPrefix(prefix) {
            raw = "https://" + raw.dropFirst(prefix.count)
        }
        if !raw.contains("://") { raw = "https://" + raw }
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
            return .failure(.notALink)
        }
        return mayFetch(url) ? .success(url) : .failure(url.user != nil || url.password != nil ? .notALink : .notPublic)
    }

    /// Whether the feed reader may request this URL (the pasted link, and wherever it redirects).
    public static func mayFetch(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              host.contains(".") else { return false }
        // Raw IP addresses (v4 or v6) and local names never: only real public host names.
        if host.contains(":") || host.allSatisfy({ $0.isNumber || $0 == "." }) { return false }
        let local = ["localhost", ".local", ".localhost", ".internal", ".lan", ".home", ".home.arpa", ".corp", ".intranet"]
        if local.contains(where: { host == $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) || host.hasSuffix($0) }) { return false }
        return true
    }
}
