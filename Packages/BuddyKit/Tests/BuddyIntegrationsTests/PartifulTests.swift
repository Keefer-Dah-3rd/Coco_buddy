import Foundation
import Testing
@testable import BuddyIntegrations

/// An event page shaped like Partiful's: schema.org JSON-LD plus the page's own data.
func partifulPage(ld: [String: Any]? = nil, event: [String: Any]? = nil, passwordRequired: Bool = false, ogTitle: String? = nil) -> String {
    func json(_ object: Any) -> String {
        String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
    }
    var head = "<html><head><meta charSet=\"utf-8\"/>"
    if let ogTitle { head += "<meta property=\"og:title\" content=\"\(ogTitle)\" data-next-head=\"\"/>" }
    if let ld { head += "<script type=\"application/ld+json\" data-next-head=\"\">\(json(ld))</script>" }
    var props: [String: Any] = ["passwordRequired": passwordRequired]
    if let event { props["event"] = event }
    let next = ["props": ["pageProps": props], "page": "/e/[id]"] as [String: Any]
    return head + "</head><body><div id=\"__next\"></div><script id=\"__NEXT_DATA__\" type=\"application/json\">\(json(next))</script></body></html>"
}

@Suite struct PartifulLinkTests {
    @Test func recognisesTheWaysPeoplePasteLinks() {
        let id = "3ea9jKHiRgcLhkrJJHwX"
        let canonical = URL(string: "https://partiful.com/e/\(id)")!
        for text in ["https://partiful.com/e/\(id)", "http://partiful.com/e/\(id)", "partiful.com/e/\(id)",
                     "https://www.partiful.com/e/\(id)", "https://partiful.com/e/\(id)?c=Ab12&utm_source=imessage",
                     "https://partiful.com/e/\(id)/", " <https://partiful.com/e/\(id)> ", "HTTPS://Partiful.com/e/\(id)"] {
            let parsed = Partiful.link(from: text)
            #expect(parsed?.url == canonical, "\(text)")
            #expect(parsed?.link == .event(id: id), "\(text)")
        }
        let short = Partiful.link(from: "https://go.partiful.com/VtxO62x5?x=1")
        #expect(short?.link == .short(code: "VtxO62x5"))
        #expect(short?.url.absoluteString == "https://go.partiful.com/VtxO62x5")
    }

    @Test func refusesEverythingElse() {
        for text in ["https://partiful.com.evil.example/e/3ea9jKHiRgcLhkrJJHwX",
                     "https://evil.example/partiful.com/e/3ea9jKHiRgcLhkrJJHwX",
                     "https://partiful.com@evil.example/e/3ea9jKHiRgcLhkrJJHwX",
                     "https://user:pw@partiful.com/e/3ea9jKHiRgcLhkrJJHwX",
                     "https://partiful.com:8080/e/3ea9jKHiRgcLhkrJJHwX",
                     "ftp://partiful.com/e/3ea9jKHiRgcLhkrJJHwX",
                     "https://partiful.com/u/3ea9jKHiRgcLhkrJJHwX",
                     "https://partiful.com/e/short",
                     "https://partiful.com/e/../../admin",
                     "https://partiful.com/e/abc%2F..%2Fdef12345",
                     "https://partiful.com/", "https://127.0.0.1/e/3ea9jKHiRgcLhkrJJHwX",
                     "https://go.partiful.com/a/b", "not a link at all"] {
            #expect(Partiful.link(from: text) == nil, "\(text)")
        }
    }

    @Test func findsLinksInAMessage() {
        let message = "can you add this? partiful.com/e/3ea9jKHiRgcLhkrJJHwX. also https://go.partiful.com/VtxO62x5, "
            + "and again https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX?c=1 and https://example.com/e/xyz12345678"
        #expect(Partiful.links(in: message).map(\.absoluteString) == [
            "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX", "https://go.partiful.com/VtxO62x5",
        ])
    }

    @Test func onlyEverFetchesFromPartiful() {
        #expect(Partiful.mayFetch(URL(string: "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")!))
        #expect(Partiful.mayFetch(URL(string: "https://go.partiful.com/VtxO62x5")!))
        #expect(!Partiful.mayFetch(URL(string: "http://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")!))
        #expect(!Partiful.mayFetch(URL(string: "https://accounts.google.com/signin")!))
        #expect(!Partiful.mayFetch(URL(string: "https://169.254.169.254/latest/meta-data")!))
        #expect(!Partiful.mayFetch(URL(string: "https://localhost/e/3ea9jKHiRgcLhkrJJHwX")!))
    }
}

@Suite struct PartifulPageTests {
    let url = URL(string: "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")!
    let ld: [String: Any] = [
        "@context": "https://schema.org", "@type": "Event", "name": "Gigi Flea 🕸️ 4100 Bar",
        "description": "Costumes encouraged.\nFree entry, 21+",
        "startDate": "2026-10-25T21:00:00.000Z", "endDate": "2026-10-26T02:00:00.000Z",
        "eventStatus": "https://schema.org/EventScheduled",
        "location": ["@type": "Place", "name": "4100 Bar",
                     "address": ["@type": "PostalAddress", "streetAddress": "1087 Manzanita St", "addressLocality": "Los Angeles",
                                 "addressRegion": "CA", "postalCode": "90029", "addressCountry": "US"]],
        "url": "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX",
    ]
    let pageEvent: [String: Any] = ["id": "3ea9jKHiRgcLhkrJJHwX", "title": "Gigi Flea 🕸️ 4100 Bar", "timezone": "America/Los_Angeles",
                                    "startDate": "2026-10-25T21:00:00.000Z", "visibility": "public", "status": "PUBLISHED"]

    @Test func readsAPublicEvent() throws {
        guard case .event(let event) = Partiful.parse(html: partifulPage(ld: ld, event: pageEvent), url: url) else {
            Issue.record("expected an event"); return
        }
        #expect(event.id == "3ea9jKHiRgcLhkrJJHwX")
        #expect(event.url == url)
        #expect(event.title == "Gigi Flea 🕸️ 4100 Bar")
        #expect(event.start == ISO8601DateFormatter().date(from: "2026-10-25T21:00:00Z"))
        #expect(event.end == ISO8601DateFormatter().date(from: "2026-10-26T02:00:00Z"))
        #expect(event.timeZone?.identifier == "America/Los_Angeles")
        #expect(event.venue == "4100 Bar")
        #expect(event.address == "1087 Manzanita St, Los Angeles, CA 90029")
        #expect(event.location == "4100 Bar, 1087 Manzanita St, Los Angeles, CA 90029")
        #expect(event.description == "Costumes encouraged.\nFree entry, 21+")
        #expect(event.sourceKey == "partiful:3ea9jKHiRgcLhkrJJHwX")
        #expect(!event.isCancelled)
    }

    @Test func missingDetailsStayMissing() {
        var bare = ld
        bare["endDate"] = nil
        bare["description"] = nil
        bare["location"] = nil
        guard case .event(let event) = Partiful.parse(html: partifulPage(ld: bare, event: ["id": "3ea9jKHiRgcLhkrJJHwX"]), url: url) else {
            Issue.record("expected an event"); return
        }
        #expect(event.end == nil)
        #expect(event.timeZone == nil)
        #expect(event.location == nil)
        #expect(event.description == nil)
    }

    @Test func aFreeformPlaceIsTheAddress() {
        var freeform = ld
        freeform["location"] = ["@type": "Place", "name": "2457 Hunter St Suite B, Los Angeles, CA 90021"]
        guard case .event(let event) = Partiful.parse(html: partifulPage(ld: freeform), url: url) else {
            Issue.record("expected an event"); return
        }
        #expect(event.venue == nil)
        #expect(event.location == "2457 Hunter St Suite B, Los Angeles, CA 90021")
    }

    @Test func fallsBackToThePageDataWithoutStructuredData() {
        var only = pageEvent
        only["endDate"] = "2026-10-26T01:00:00.000Z"
        only["location"] = "The Mulberry BK, 1299 Gates Ave, Brooklyn, NY"
        only["description"] = "Come through"
        guard case .event(let event) = Partiful.parse(html: partifulPage(event: only), url: url) else {
            Issue.record("expected an event"); return
        }
        #expect(event.title == "Gigi Flea 🕸️ 4100 Bar")
        #expect(event.end != nil)
        #expect(event.location == "The Mulberry BK, 1299 Gates Ave, Brooklyn, NY")
    }

    @Test func aTitleWithoutADateIsStillUseful() {
        guard case .event(let event) = Partiful.parse(html: partifulPage(ogTitle: "Secret dinner | Partiful"), url: url) else {
            Issue.record("expected an event"); return
        }
        #expect(event.title == "Secret dinner")
        #expect(event.start == nil)
    }

    @Test func passwordsAndEmptyPagesAreReported() {
        #expect(Partiful.parse(html: partifulPage(passwordRequired: true), url: url) == .passwordProtected)
        #expect(Partiful.parse(html: "<html><body>Sign in to see this event</body></html>", url: url) == .unreadable)
        #expect(Partiful.parse(html: partifulPage(), url: url) == .unreadable)
    }

    @Test func cancellationsAndNonsenseTimes() {
        var cancelled = ld
        cancelled["eventStatus"] = "https://schema.org/EventCancelled"
        cancelled["endDate"] = "2026-10-25T20:00:00.000Z"  // before the start: ignored, not trusted
        guard case .event(let event) = Partiful.parse(html: partifulPage(ld: cancelled), url: url) else {
            Issue.record("expected an event"); return
        }
        #expect(event.isCancelled)
        #expect(event.end == nil)
    }
}

@Suite struct CalendarSourceTests {
    let source = EventSource(name: "Partiful", url: URL(string: "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")!,
                             key: "partiful:3ea9jKHiRgcLhkrJJHwX")

    @Test func theInviteLinkIsKeptOnTheEvent() throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let draft = EventDraft(title: "Gigi Flea", start: start, end: start + 3600, notes: "Bring a costume", source: source)
        let request = GoogleCalendarAPI.insertRequest(draft, accessToken: "t")
        let body = try #require(try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        #expect(body["description"] as? String == "Bring a costume\n\nPartiful invite: https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")
        #expect((body["source"] as? [String: String])?["url"] == "https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")
        let properties = (body["extendedProperties"] as? [String: Any])?["private"] as? [String: String]
        #expect(properties?[GoogleCalendarAPI.sourceProperty] == "partiful:3ea9jKHiRgcLhkrJJHwX")

        let linkOnly = EventDraft(title: "x", start: start, end: start + 60, source: source)
        #expect(linkOnly.description == "Partiful invite: https://partiful.com/e/3ea9jKHiRgcLhkrJJHwX")
        let plain = EventDraft(title: "x", start: start, end: start + 60)
        let plainBody = try #require(try JSONSerialization.jsonObject(with: GoogleCalendarAPI.insertRequest(plain, accessToken: "t").httpBody!) as? [String: Any])
        #expect(plainBody["source"] == nil && plainBody["extendedProperties"] == nil && plainBody["description"] == nil)
    }

    @Test func findsEventsMadeFromTheSameInvite() throws {
        let request = GoogleCalendarAPI.eventsRequest(sourceKey: source.key, accessToken: "t")
        let query = try #require(request.url?.query(percentEncoded: true))
        #expect(query.contains("privateExtendedProperty=cocoSource%3Dpartiful%3A3ea9jKHiRgcLhkrJJHwX"))
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "privateExtendedProperty" }?.value == "cocoSource=partiful:3ea9jKHiRgcLhkrJJHwX")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }
}
