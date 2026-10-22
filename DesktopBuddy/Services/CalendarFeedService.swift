import AppKit
import Observation
import OSLog
import BuddyCore
import BuddyIntegrations

/// A calendar Coco reads from a private subscription link the user pastes:
/// - **Partiful**: the personal calendar link Partiful offers for calendar sync (calendar icon
///   under an event › Google Calendar › Copy Link);
/// - **Google Calendar**: a calendar's "Secret address in iCal format" (Google Calendar ›
///   Settings › the calendar › Integrate calendar). No Google sign-in or Google Cloud project.
///
/// Read-only: the events show in Coco's calendar and count for availability; nothing is ever
/// written back. Repeating events are expanded for about the last week and the next six months.
/// The link is a secret (anyone with it sees the events), so it lives in the Keychain; the last
/// good copy of the events is cached so they show offline.
@Observable
final class CalendarFeedService {
    enum Status: Equatable { case disconnected, connecting, connected }

    enum Kind {
        case partiful, google

        var name: String { self == .partiful ? "Partiful" : "Google Calendar" }
        var provider: CalendarProvider { self == .partiful ? .partiful : .google }
        fileprivate var keychainAccount: String { self == .partiful ? "partiful.calendarLink" : "google.calendarLink" }
        fileprivate var cacheName: String { self == .partiful ? "partiful-feed" : "google-feed" }
        fileprivate var idPrefix: String { self == .partiful ? "partiful:" : "gcal:" }
        /// Google's feeds hold years of history, so they can be large.
        fileprivate var maxBytes: Int { self == .partiful ? 5_000_000 : 30_000_000 }
        /// Where to copy the link from, for error messages.
        var whereToFind: String {
            switch self {
            case .partiful: "on partiful.com, open an event, click the calendar icon under the details, choose Google Calendar, then Copy Link"
            case .google: "in Google Calendar on the web, open Settings, choose the calendar, then under Integrate calendar copy the Secret address in iCal format"
            }
        }
    }

    let kind: Kind

    private(set) var status: Status = .disconnected
    /// Upcoming events (and the last week's), repeating ones expanded, cancelled ones left out.
    private(set) var feedEvents: [ICalendar.Event] = []
    /// The calendar's own name, when the feed gives one (Google: usually the account's email).
    private(set) var calendarName: String?
    private(set) var lastUpdated: Date?
    /// Set when the latest refresh failed; the last good events are still shown.
    private(set) var problem: String?
    private(set) var isRefreshing = false

    var isConnected: Bool { status == .connected }

    @ObservationIgnored var onEventsChanged: (() -> Void)?
    @ObservationIgnored private var link: URL?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private let cache: JSONFileStore<Cached>?
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "feeds")
    @ObservationIgnored private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        #if DEBUG
        if let stand = HTTP.standIn { configuration.protocolClasses = [stand] }
        #endif
        return URLSession(configuration: configuration)
    }()

    /// How often the feed is read again while Coco is running.
    static let refreshInterval: TimeInterval = 30 * 60

    private struct FeedProblem: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    private struct Cached: Codable {
        var events: [ICalendar.Event]
        var fetchedAt: Date
        var name: String?
    }

    private struct Download {
        var events: [ICalendar.Event]
        var name: String?
    }

    init(kind: Kind, persistent: Bool = true) {
        self.kind = kind
        self.persistent = persistent
        cache = persistent ? try? JSONFileStore(name: kind.cacheName) : nil
    }

    /// Picks up a saved link (and the cached events) and refreshes.
    func start() {
        guard persistent else { return }
        Task {
            guard let saved = await Keychain.stringInBackground(for: kind.keychainAccount), let url = URL(string: saved) else { return }
            link = url
            status = .connected
            if let cached = try? cache?.load() {
                feedEvents = cached.events
                calendarName = cached.name
                lastUpdated = cached.fetchedAt
                onEventsChanged?()
            }
            await refresh()
            scheduleRefresh()
        }
    }

    // MARK: - Connecting

    /// Checks the pasted link, reads it once, and only then saves it. Returns a problem to show, or nil.
    func connect(_ text: String) async -> String? {
        let url: URL
        switch CalendarFeedLink.validate(text) {
        case .success(let valid): url = valid
        case .failure(.invitationLink):
            return "That's a link to one invitation. \(Buddy.name) needs your calendar link: \(kind.whereToFind)."
        case .failure(.notPublic):
            return "That link points to this Mac or a local network, so \(Buddy.name) won't open it."
        case .failure(.notALink):
            return "That doesn't look like a calendar link. It should start with https:// or webcal://."
        }
        if kind == .google, let problem = Self.googleLinkProblem(url) { return problem }
        status = .connecting
        switch await download(url) {
        case .success(let download):
            guard !persistent || Keychain.set(Data(url.absoluteString.utf8), for: kind.keychainAccount) else {
                status = .disconnected
                return "Couldn't save the link in your Keychain."
            }
            link = url
            status = .connected
            apply(download)
            scheduleRefresh()
            log.info("\(self.kind.name, privacy: .public) calendar connected: \(download.events.count) events")
            return nil
        case .failure(let problem):
            status = .disconnected
            return problem.message
        }
    }

    /// Forgets the link and every event Coco kept from it.
    func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if persistent { Keychain.remove(kind.keychainAccount) }
        try? cache?.delete()
        link = nil
        status = .disconnected
        feedEvents = []
        calendarName = nil
        lastUpdated = nil
        problem = nil
        onEventsChanged?()
    }

    // MARK: - Reading

    func refresh() async {
        guard let link, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        switch await download(link) {
        case .success(let download):
            apply(download)
        case .failure(let failure):
            problem = failure.message
            log.error("\(self.kind.name, privacy: .public) refresh failed: \(failure.message, privacy: .public)")
        }
    }

    /// Refreshes if the events are older than `maxAge` — e.g. when the calendar card opens.
    func refreshIfStale(maxAge: TimeInterval = 15 * 60) {
        guard isConnected, !isRefreshing, Date.now.timeIntervalSince(lastUpdated ?? .distantPast) > maxAge else { return }
        Task { await refresh() }
    }

    private func scheduleRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
    }

    private func apply(_ download: Download) {
        let now = Date.now
        // About a week back to six months ahead, repeating events expanded.
        let window = (from: now.addingTimeInterval(-7 * 86_400), to: now.addingTimeInterval(183 * 86_400))
        let kept = ICalendar.expand(download.events, from: window.from, to: window.to)
            .filter { $0.status != .cancelled }
        lastUpdated = now
        problem = nil
        calendarName = download.name
        if kept != feedEvents {
            feedEvents = kept
            onEventsChanged?()
        }
        try? cache?.save(Cached(events: kept, fetchedAt: now, name: download.name))
    }

    /// Google: only a calendar's iCal address works (not a Calendar web page or an embed link).
    static func googleLinkProblem(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        guard host == "calendar.google.com" || host == "www.google.com" else {
            return "That isn't a Google Calendar address. In Google Calendar's settings, copy the calendar's Secret address in iCal format (it starts with https://calendar.google.com/calendar/ical/)."
        }
        guard url.path.contains("/ical/"), url.path.hasSuffix(".ics") else {
            return "That's a Google Calendar page, not the calendar's address. In Settings › your calendar › Integrate calendar, copy the Secret address in iCal format (it ends in .ics)."
        }
        return nil
    }

    private func download(_ url: URL) async -> Result<Download, FeedProblem> {
        let name = kind.name
        var request = URLRequest(url: url)
        request.setValue("DesktopBuddy (macOS; reads its user's own calendar link)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/calendar, text/plain;q=0.5", forHTTPHeaderField: "Accept")
        let guardian = RedirectGuard(allow: CalendarFeedLink.mayFetch)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: guardian)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            return .failure(FeedProblem("This Mac is offline" + (lastUpdated.map { " — showing \(name) events from \($0.formatted(date: .omitted, time: .shortened))" } ?? "") + "."))
        } catch {
            return .failure(FeedProblem("Couldn't reach \(name) (\(error.localizedDescription))."))
        }
        if guardian.refused { return .failure(FeedProblem("The link redirected somewhere Coco won't follow (a local address or a non-https page).")) }
        guard let http = response as? HTTPURLResponse else { return .failure(FeedProblem("\(name) didn't answer properly.")) }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403, 404, 410:
            return .failure(FeedProblem(kind == .google
                ? "Google didn't accept this address. Use the Secret address in iCal format (the public one only works for a public calendar). If you reset it in Google, copy the new one."
                : "Partiful didn't accept this calendar link — it may have been reset. Copy it again from Partiful and reconnect."))
        case 429, 503:
            return .failure(FeedProblem("\(name) is busy right now; \(Buddy.name) will try again later."))
        default:
            return .failure(FeedProblem("\(name) answered \(http.statusCode); \(Buddy.name) will try again later."))
        }
        guard data.count <= kind.maxBytes, let text = String(data: data, encoding: .utf8),
              let feed = ICalendar.parse(text) else {
            return .failure(FeedProblem("That link didn't return a calendar. Make sure you copied the right one: \(kind.whereToFind)."))
        }
        return .success(Download(events: feed.events, name: feed.name))
    }

    // MARK: - Events for the calendar

    /// Every kept event as a calendar event: read-only, linking back to the invitation.
    var events: [CalendarEvent] { feedEvents.map(calendarEvent) }

    /// Events touching a day, or nil when not connected.
    func events(on day: Date) -> [CalendarEvent]? {
        guard isConnected else { return nil }
        let bounds = Availability.dayInterval(day, calendar: .current)
        return feedEvents.filter { $0.start < bounds.end && max($0.end, $0.start.addingTimeInterval(1)) > bounds.start }
            .map(calendarEvent)
    }

    /// The feed's copy of one invitation, by its Partiful event id.
    func event(partifulID: String) -> ICalendar.Event? {
        guard kind == .partiful else { return nil }
        return feedEvents.first { $0.uid == partifulID }
    }

    /// One id per occurrence: the UID, plus the original start for a repeat.
    private func id(of event: ICalendar.Event) -> String {
        kind.idPrefix + event.uid + (event.occurrence.map { "@\(Int($0.timeIntervalSince1970))" } ?? "")
    }

    func calendarEvent(_ event: ICalendar.Event) -> CalendarEvent {
        switch kind {
        case .partiful:
            let link = event.url ?? (Partiful.link(from: "partiful.com/e/\(event.uid)").map(\.url))
            return CalendarEvent(id: id(of: event), title: event.title, start: event.start, end: event.end,
                                 isAllDay: event.isAllDay, location: event.location, htmlLink: link,
                                 colorID: "#E0457B",  // Partiful pink, so they stand out in the week
                                 isBusy: true, canEdit: false, provider: .partiful, calendarName: "Partiful",
                                 matchKeys: [event.uid, Partiful.sourceKey(id: event.uid)],
                                 notes: event.description.map(AppModel.withoutPartifulBoilerplate),
                                 endIsEstimated: !event.endListed)
        case .google:
            // Same UID as Calendar.app's copy of the account, so the two merge into one event.
            return CalendarEvent(id: id(of: event), title: event.title, start: event.start, end: event.end,
                                 isAllDay: event.isAllDay, location: event.location, htmlLink: event.url,
                                 isBusy: event.status != .tentative, isRecurring: event.isRepeating, canEdit: false,
                                 provider: .google, calendarID: "feed", calendarName: calendarName ?? "Google Calendar",
                                 matchKeys: event.uid.isEmpty ? [] : [event.uid], occurrenceStart: event.occurrence,
                                 timeZone: event.timeZoneID, notes: event.description,
                                 endIsEstimated: !event.endListed && !event.isAllDay)
        }
    }
}

// MARK: - One of Coco's calendars

extension CalendarFeedService: AgendaSource {
    var sourceName: String { kind.name }
    var isActive: Bool { isConnected }

    /// The feed covers every date at once: read it again if it's stale, and fail only when
    /// there are no events at all to show.
    func load(from: Date, to: Date) async throws {
        if Date.now.timeIntervalSince(lastUpdated ?? .distantPast) > 15 * 60 { await refresh() }
        if lastUpdated == nil, let problem { throw FeedProblem(problem) }
    }

    func prefetch(around day: Date) { refreshIfStale() }
    func isLoading(_ day: Date) -> Bool { isRefreshing }
    func problem(for day: Date) -> String? { problem }

    func event(id: String) -> CalendarEvent? {
        guard id.hasPrefix(kind.idPrefix) else { return nil }
        return feedEvents.first { self.id(of: $0) == id }.map(calendarEvent)
    }
}
