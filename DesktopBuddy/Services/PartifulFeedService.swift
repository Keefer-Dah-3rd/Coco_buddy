import AppKit
import Observation
import OSLog
import BuddyCore
import BuddyIntegrations

/// The user's Partiful events, read from their personal Partiful calendar link — the link
/// Partiful itself offers for calendar sync (calendar icon under an event → Google Calendar →
/// Copy Link). Read-only: the events show in Coco's calendar and count for availability, but
/// nothing is ever written to Google Calendar or Partiful.
///
/// The link is a secret (anyone with it sees the user's events), so it lives in the Keychain;
/// the last good copy of the events is cached so they show offline.
@Observable
final class PartifulFeedService {
    enum Status: Equatable { case disconnected, connecting, connected }

    private(set) var status: Status = .disconnected
    /// Upcoming events (and the last week's), cancelled ones left out.
    private(set) var feedEvents: [ICalendar.Event] = []
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
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "partiful")
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

    private static let keychainAccount = "partiful.calendarLink"
    private static let maxBytes = 5_000_000
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
    }

    init(persistent: Bool = true) {
        self.persistent = persistent
        cache = persistent ? try? JSONFileStore(name: "partiful-feed") : nil
    }

    /// Picks up a saved link (and the cached events) and refreshes.
    func start() {
        guard persistent else { return }
        Task {
            guard let saved = await Keychain.stringInBackground(for: Self.keychainAccount), let url = URL(string: saved) else { return }
            link = url
            status = .connected
            if let cached = try? cache?.load() {
                feedEvents = cached.events
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
            return "That's a link to one invitation. Coco needs your calendar link: on partiful.com, open an event, click the calendar icon under the details, choose Google Calendar, then Copy Link."
        case .failure(.notPublic):
            return "That link points to this Mac or a local network, so Coco won't open it."
        case .failure(.notALink):
            return "That doesn't look like a calendar link. It should start with https:// or webcal://."
        }
        status = .connecting
        switch await download(url) {
        case .success(let events):
            guard !persistent || Keychain.set(Data(url.absoluteString.utf8), for: Self.keychainAccount) else {
                status = .disconnected
                return "Couldn't save the link in your Keychain."
            }
            link = url
            status = .connected
            apply(events)
            scheduleRefresh()
            log.info("Partiful calendar connected: \(events.count) events")
            return nil
        case .failure(let problem):
            status = .disconnected
            return problem.message
        }
    }

    /// Forgets the link and every Partiful event Coco kept.
    func disconnect() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        if persistent { Keychain.remove(Self.keychainAccount) }
        try? cache?.delete()
        link = nil
        status = .disconnected
        feedEvents = []
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
        case .success(let events):
            apply(events)
        case .failure(let failure):
            problem = failure.message
            log.error("Partiful refresh failed: \(failure.message, privacy: .public)")
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

    private func apply(_ events: [ICalendar.Event]) {
        let now = Date.now
        let kept = events.filter { $0.status != .cancelled && $0.end > now.addingTimeInterval(-7 * 86_400) }
            .sorted { $0.start < $1.start }
        lastUpdated = now
        problem = nil
        if kept != feedEvents {
            feedEvents = kept
            onEventsChanged?()
        }
        try? cache?.save(Cached(events: kept, fetchedAt: now))
    }

    private func download(_ url: URL) async -> Result<[ICalendar.Event], FeedProblem> {
        var request = URLRequest(url: url)
        request.setValue("DesktopBuddy (macOS; reads its user's own Partiful calendar link)", forHTTPHeaderField: "User-Agent")
        request.setValue("text/calendar, text/plain;q=0.5", forHTTPHeaderField: "Accept")
        let guardian = RedirectGuard(allow: CalendarFeedLink.mayFetch)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: guardian)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            return .failure(FeedProblem("This Mac is offline" + (lastUpdated.map { " — showing Partiful events from \($0.formatted(date: .omitted, time: .shortened))" } ?? "") + "."))
        } catch {
            return .failure(FeedProblem("Couldn't reach Partiful (\(error.localizedDescription))."))
        }
        if guardian.refused { return .failure(FeedProblem("The link redirected somewhere Coco won't follow (a local address or a non-https page).")) }
        guard let http = response as? HTTPURLResponse else { return .failure(FeedProblem("Partiful didn't answer properly.")) }
        switch http.statusCode {
        case 200..<300: break
        case 401, 403, 404, 410:
            return .failure(FeedProblem("Partiful didn't accept this calendar link — it may have been reset. Copy it again from Partiful and reconnect."))
        case 429, 503:
            return .failure(FeedProblem("Partiful is busy right now; Coco will try again later."))
        default:
            return .failure(FeedProblem("Partiful answered \(http.statusCode); Coco will try again later."))
        }
        guard data.count <= Self.maxBytes, let text = String(data: data, encoding: .utf8),
              let feed = ICalendar.parse(text) else {
            return .failure(FeedProblem("That link didn't return a calendar. Make sure you copied the calendar link (calendar icon → Google Calendar → Copy Link), not the event page."))
        }
        return .success(feed.events)
    }

    // MARK: - Events for the calendar

    /// Every kept event as a calendar event: read-only, linking back to the invitation.
    var events: [CalendarEvent] { feedEvents.map(Self.calendarEvent) }

    /// Events touching a day, or nil when not connected.
    func events(on day: Date) -> [CalendarEvent]? {
        guard isConnected else { return nil }
        let bounds = Availability.dayInterval(day, calendar: .current)
        return feedEvents.filter { $0.start < bounds.end && max($0.end, $0.start.addingTimeInterval(1)) > bounds.start }
            .map(Self.calendarEvent)
    }

    /// The feed's copy of one invitation, by its Partiful event id.
    func event(partifulID: String) -> ICalendar.Event? {
        feedEvents.first { $0.uid == partifulID }
    }

    static func calendarEvent(_ event: ICalendar.Event) -> CalendarEvent {
        let link = event.url ?? (Partiful.link(from: "partiful.com/e/\(event.uid)").map(\.url))
        return CalendarEvent(id: "partiful:\(event.uid)", title: event.title, start: event.start, end: event.end,
                             isAllDay: event.isAllDay, location: event.location, htmlLink: link,
                             colorID: "#E0457B",  // Partiful pink, so they stand out in the week
                             isBusy: true, canEdit: false, provider: .partiful, calendarName: "Partiful",
                             matchKeys: [event.uid, Partiful.sourceKey(id: event.uid)],
                             notes: event.description.map(AppModel.withoutPartifulBoilerplate),
                             endIsEstimated: !event.endListed)
    }
}

// MARK: - One of Coco's calendars

extension PartifulFeedService: AgendaSource {
    var sourceName: String { CalendarProvider.partiful.displayName }
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
        guard id.hasPrefix("partiful:") else { return nil }
        return event(partifulID: String(id.dropFirst("partiful:".count))).map(Self.calendarEvent)
    }
}
