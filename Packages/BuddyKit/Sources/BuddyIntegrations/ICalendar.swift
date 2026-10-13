import Foundation

/// A small iCalendar (RFC 5545) reader for subscription feeds such as the user's personal
/// Partiful calendar link: events with their times, place, link and description. Repeating
/// events aren't expanded (Partiful's feed has none); alarms and time-zone blocks are skipped.
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

        public init(uid: String, title: String, start: Date, end: Date, endListed: Bool = true, isAllDay: Bool = false,
                    location: String? = nil, url: URL? = nil, description: String? = nil, status: Status = .confirmed) {
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
        return Event(uid: uid, title: (title?.isEmpty ?? true) ? "Untitled event" : title!, start: start, end: end,
                     endListed: endListed, isAllDay: allDay, location: location, url: url, description: description, status: status)
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
