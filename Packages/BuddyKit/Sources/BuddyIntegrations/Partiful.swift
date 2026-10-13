import Foundation

/// An event read from an invitation page (today: Partiful). Only what the page actually
/// said — anything it didn't show stays nil, so nothing is ever filled in by guesswork.
public struct LinkedEvent: Equatable, Sendable {
    /// Partiful's event id, e.g. "3ea9jKHiRgcLhkrJJHwX".
    public var id: String
    /// The canonical invitation link, https://partiful.com/e/<id>.
    public var url: URL
    public var title: String
    public var start: Date?
    public var end: Date?
    /// The time zone the host set for the event, when the page says.
    public var timeZone: TimeZone?
    /// The venue's name ("4100 Bar"), when it differs from the address.
    public var venue: String?
    public var address: String?
    public var description: String?
    public var isCancelled: Bool
    public var isPostponed: Bool

    public init(id: String, url: URL, title: String, start: Date? = nil, end: Date? = nil, timeZone: TimeZone? = nil,
                venue: String? = nil, address: String? = nil, description: String? = nil,
                isCancelled: Bool = false, isPostponed: Bool = false) {
        self.id = id
        self.url = url
        self.title = title
        self.start = start
        self.end = end
        self.timeZone = timeZone
        self.venue = venue
        self.address = address
        self.description = description
        self.isCancelled = isCancelled
        self.isPostponed = isPostponed
    }

    /// Venue and address together, for a calendar event's location.
    public var location: String? {
        switch (venue, address) {
        case let (venue?, address?): "\(venue), \(address)"
        case let (venue?, nil): venue
        case let (nil, address?): address
        case (nil, nil): nil
        }
    }

    /// The key a calendar event created from this link carries, so the same invitation is
    /// never added twice.
    public var sourceKey: String { Partiful.sourceKey(id: id) }
}

/// Partiful invitation links: recognising them, and reading the public event page.
///
/// Event pages carry schema.org `Event` data (the same thing search engines and link previews
/// read), plus the page's own data with the host's time zone. Partiful's robots.txt welcomes
/// link-preview fetchers; the app reads a page only when the user shares its link, identifies
/// itself honestly, sends no cookies, and never tries to get past a password or sign-in.
public enum Partiful {
    public enum Link: Equatable, Sendable {
        /// partiful.com/e/<id>
        case event(id: String)
        /// go.partiful.com/<code> — a short link that redirects to an event.
        case short(code: String)
    }

    static let eventHosts: Set<String> = ["partiful.com", "www.partiful.com"]
    static let shortHosts: Set<String> = ["go.partiful.com"]

    /// Parses one link as the user might paste it: with or without https://, www., query
    /// strings or a trailing slash. Anything that isn't a Partiful event or short link is nil.
    public static func link(from text: String) -> (url: URL, link: Link)? {
        var raw = text.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "<>()\"'")))
        if !raw.contains("://") { raw = "https://" + raw }
        guard var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased() else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        if eventHosts.contains(host), parts.count >= 2, parts[0] == "e", isID(parts[1]) {
            return (canonicalURL(id: parts[1]), .event(id: parts[1]))
        }
        if shortHosts.contains(host), parts.count == 1, isID(parts[0], minimum: 4) {
            components.scheme = "https"
            components.host = host
            components.query = nil
            components.fragment = nil
            components.path = "/" + parts[0]
            guard let url = components.url else { return nil }
            return (url, .short(code: parts[0]))
        }
        return nil
    }

    /// Every Partiful link in a message, in order, without repeats.
    public static func links(in text: String) -> [URL] {
        var seen = Set<URL>()
        return text.split(whereSeparator: { $0.isWhitespace }).compactMap { word in
            guard word.localizedCaseInsensitiveContains("partiful.com") else { return nil }
            return link(from: String(word).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?")))?.url
        }.filter { seen.insert($0).inserted }
    }

    /// Whether a request may go to this URL — the only places the reader ever fetches from,
    /// including where redirects lead.
    public static func mayFetch(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(), url.user == nil,
              url.port == nil || url.port == 443 else { return false }
        return eventHosts.contains(host) || shortHosts.contains(host)
    }

    public static func canonicalURL(id: String) -> URL {
        URL(string: "https://partiful.com/e/\(id)")!
    }

    public static func sourceKey(id: String) -> String { "partiful:\(id)" }

    static func isID(_ text: String, minimum: Int = 8) -> Bool {
        (minimum...40).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    // MARK: Reading the page

    public enum Page: Equatable, Sendable {
        case event(LinkedEvent)
        /// The host locked the invitation with a password.
        case passwordProtected
        /// The page loaded but had no event details to read.
        case unreadable
    }

    /// Reads an event page. `url` is where the page was fetched from (after redirects).
    public static func parse(html: String, url: URL) -> Page {
        let pageData = nextData(in: html)
        let props = (pageData?["props"] as? [String: Any])?["pageProps"] as? [String: Any]
        if props?["passwordRequired"] as? Bool == true { return .passwordProtected }
        let pageEvent = props?["event"] as? [String: Any]

        guard let id = (pageEvent?["id"] as? String).flatMap({ isID($0) ? $0 : nil })
                ?? link(from: url.absoluteString).flatMap({ if case .event(let id) = $0.link { id } else { nil } })
        else { return .unreadable }

        let structured = jsonLDEvent(in: html)
        let title = clean(structured?["name"] as? String) ?? clean(pageEvent?["title"] as? String)
            ?? metaContent("og:title", in: html).map { $0.replacingOccurrences(of: " | Partiful", with: "") }.flatMap(clean)
        guard let title else { return .unreadable }

        var event = LinkedEvent(id: id, url: canonicalURL(id: id), title: title)
        event.start = date(structured?["startDate"]) ?? date(pageEvent?["startDate"])
        event.end = date(structured?["endDate"]) ?? date(pageEvent?["endDate"])
        if let start = event.start, let end = event.end, end <= start { event.end = nil }
        event.timeZone = (pageEvent?["timezone"] as? String).flatMap(TimeZone.init(identifier:))
        event.description = clean(structured?["description"] as? String) ?? clean(pageEvent?["description"] as? String)

        if let place = structured?["location"] as? [String: Any] {
            let name = clean(place["name"] as? String)
            let address = (place["address"] as? [String: Any]).flatMap(postalAddress)
                ?? clean(place["address"] as? String)
            event.address = address ?? name
            event.venue = address == nil || name == address ? nil : name
        } else if let location = clean(pageEvent?["location"] as? String) {
            event.address = location
        }

        let status = (structured?["eventStatus"] as? String ?? "") + " " + (pageEvent?["status"] as? String ?? "")
        event.isCancelled = status.localizedCaseInsensitiveContains("cancel")
        event.isPostponed = status.localizedCaseInsensitiveContains("postpone")
        return .event(event)
    }

    /// The page's schema.org Event, wherever it sits in its JSON-LD blocks.
    static func jsonLDEvent(in html: String) -> [String: Any]? {
        for block in scripts(in: html, matching: "application/ld+json") {
            guard let data = block.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else { continue }
            var queue: [Any] = [value]
            while !queue.isEmpty {
                let item = queue.removeFirst()
                if let array = item as? [Any] { queue += array; continue }
                guard let object = item as? [String: Any] else { continue }
                let type = object["@type"]
                if (type as? String)?.hasSuffix("Event") == true || (type as? [String])?.contains(where: { $0.hasSuffix("Event") }) == true {
                    return object
                }
                if let graph = object["@graph"] { queue.append(graph) }
            }
        }
        return nil
    }

    static func nextData(in html: String) -> [String: Any]? {
        guard let range = html.range(of: #"<script id="__NEXT_DATA__"[^>]*>"#, options: .regularExpression),
              let end = html.range(of: "</script>", range: range.upperBound..<html.endIndex),
              let data = String(html[range.upperBound..<end.lowerBound]).data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func scripts(in html: String, matching type: String) -> [String] {
        var blocks: [String] = []
        var cursor = html.startIndex
        let pattern = #"<script[^>]*type=["']"# + NSRegularExpression.escapedPattern(for: type) + #"["'][^>]*>"#
        while let open = html.range(of: pattern, options: [.regularExpression, .caseInsensitive], range: cursor..<html.endIndex),
              let close = html.range(of: "</script>", options: .caseInsensitive, range: open.upperBound..<html.endIndex) {
            blocks.append(String(html[open.upperBound..<close.lowerBound]))
            cursor = close.upperBound
        }
        return blocks
    }

    private static func metaContent(_ property: String, in html: String) -> String? {
        let pattern = #"<meta[^>]*(?:property|name)=["']"# + NSRegularExpression.escapedPattern(for: property) + #"["'][^>]*content=["']([^"']*)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        return decodeEntities(String(html[range]))
    }

    private static func postalAddress(_ address: [String: Any]) -> String? {
        let street = clean(address["streetAddress"] as? String)
        let city = clean(address["addressLocality"] as? String)
        let region = [clean(address["addressRegion"] as? String), clean(address["postalCode"] as? String)]
            .compactMap { $0 }.joined(separator: " ")
        let parts = [street, city, region.isEmpty ? nil : region].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let precise = ISO8601DateFormatter()
        precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return precise.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func clean(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
    }
}
