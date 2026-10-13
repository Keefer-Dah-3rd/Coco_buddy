import AppKit
import AuthenticationServices
import Observation
import BuddyCore
import BuddyIntegrations
import os

/// Google Calendar. Shows "connected" only after a real sign-in succeeded, and keeps the
/// last good events (with their timestamp) when a refresh fails.
///
/// One shared source of truth: events are fetched a week at a time — only the weeks being
/// looked at — and the Today card, the week browser, the chat and meeting reminders all
/// read from the same cache. Reading needs only view access; the first time the user
/// confirms a change, Google is asked once for permission to change events.
@Observable
final class GoogleCalendarService {
    enum Status: Equatable {
        /// No OAuth client ID entered yet.
        case needsClientID
        case disconnected
        case connecting
        case connected
        /// Was connected, but Google rejected the saved access — sign in again.
        case needsReconnect
    }

    private(set) var status: Status = .needsClientID
    /// The primary calendar's name — the Google account's email address.
    private(set) var accountName: String?
    /// Today's events (derived from the week cache).
    private(set) var schedule = DaySchedule(events: [])
    private(set) var lastUpdated: Date?
    /// Fetched weeks, keyed by the start of the week.
    private(set) var weeks: [Date: Week] = [:]
    /// Weeks being fetched right now.
    private(set) var loadingWeeks: Set<Date> = []
    /// Weeks whose latest fetch failed, with why.
    private(set) var weekProblems: [Date: String] = [:]
    /// Whether the user has allowed Coco to create, change and delete events.
    private(set) var canChangeEvents = false

    struct Week: Codable, Equatable {
        var start: Date
        var events: [CalendarEvent]
        var fetchedAt: Date
    }
    /// Set when the latest refresh failed; the previous schedule is still shown.
    private(set) var problem: String?
    private(set) var isRefreshing = false

    /// The OAuth client ID is an identifier, not a secret, so it's kept in preferences.
    var clientID: String {
        didSet {
            defaults.set(clientID, forKey: Key.clientID)
            if status == .needsClientID || status == .disconnected { status = client == nil ? .needsClientID : .disconnected }
        }
    }
    /// Minutes before a meeting to remind; 0 turns reminders off.
    var reminderMinutes: Int { didSet { defaults.set(reminderMinutes, forKey: Key.reminder) } }

    var client: GoogleOAuth.Client? { GoogleOAuth.Client(clientID: clientID) }
    var isConnected: Bool { status == .connected || status == .needsReconnect }

    @ObservationIgnored var onScheduleChanged: (() -> Void)?
    @ObservationIgnored private var tokens: OAuthTokens?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private var anchor: AuthAnchor?
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private var savedSignIn: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cache: JSONFileStore<CachedWeeks>?
    @ObservationIgnored private var fetches: [Date: Task<Void, Never>] = [:]
    @ObservationIgnored private let calendar = Calendar.current
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "calendar")

    private struct CachedWeeks: Codable {
        var accountName: String?
        var weeks: [Week]
    }

    private enum Key {
        static let clientID = "calendar.google.clientID"
        static let reminder = "calendar.reminderMinutes"
        static let tokens = "google.oauth.tokens"
    }

    init(persistent: Bool = true, defaults: UserDefaults = .standard) {
        self.persistent = persistent
        self.defaults = defaults
        cache = persistent ? try? JSONFileStore(name: "calendar-weeks") : nil
        clientID = defaults.string(forKey: Key.clientID) ?? ""
        reminderMinutes = defaults.object(forKey: Key.reminder) as? Int ?? 5

        status = client == nil ? .needsClientID : .disconnected
        // The saved sign-in is read off the main thread; refresh() waits for it.
        if persistent {
            savedSignIn = Task { [weak self] in
                guard let data = await Keychain.dataInBackground(for: Key.tokens) else { return }
                self?.restore(data)
            }
        }
    }

    private func restore(_ data: Data) {
        guard tokens == nil, let saved = try? JSONDecoder().decode(OAuthTokens.self, from: data) else { return }
        tokens = saved
        canChangeEvents = saved.canChangeEvents
        status = .connected
        if let cached = try? cache?.load() {
            accountName = cached.accountName
            for week in cached.weeks where isWorthKeeping(week.start) { weeks[week.start] = week }
            lastUpdated = weeks[weekStart(for: .now)]?.fetchedAt
            updateToday()
        }
        startAutoRefresh()
    }

    // MARK: - Connect / disconnect

    /// Signs in with Google in the system sheet (PKCE, no client secret). `allowChanges` also
    /// asks permission to change events, on top of what was granted before.
    func connect(presentingFrom window: NSWindow?, allowChanges: Bool = false) async {
        guard let client else { status = .needsClientID; return }
        let wasConnected = status == .connected
        status = .connecting
        problem = nil
        let pkce = PKCE()
        let state = UUID().uuidString
        do {
            let url = GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: state, allowChanges: allowChanges)
            let callback = try await authorize(url: url, scheme: client.callbackScheme, window: window)
            let code = try GoogleOAuth.authorizationCode(from: callback, expectedState: state)
            let data = try await HTTP.send(GoogleOAuth.tokenRequest(code: code, pkce: pkce, client: client))
            store(try GoogleOAuth.decodeTokens(data, now: .now, previousRefreshToken: tokens?.refreshToken))
            status = .connected
            if !wasConnected { await refresh() }
            startAutoRefresh()
        } catch let error as IntegrationError {
            status = tokens == nil ? .disconnected : .needsReconnect
            if error != .cancelled { problem = error.userMessage }
            log.error("Google sign-in failed: \(error.userMessage, privacy: .public)")
        } catch {
            status = tokens == nil ? .disconnected : .needsReconnect
            problem = error.localizedDescription
            log.error("Google sign-in failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Disconnects and forgets the client ID too (part of "Delete all my data").
    func eraseAll() async {
        await disconnect()
        clientID = ""
        defaults.removeObject(forKey: Key.clientID)
        defaults.removeObject(forKey: Key.reminder)
        reminderMinutes = 5
        status = .needsClientID
    }

    /// Revokes access at Google (best effort) and deletes every token and cached event.
    func disconnect() async {
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            _ = try? await HTTP.send(GoogleOAuth.revokeRequest(token: token))
        }
        tokens = nil
        canChangeEvents = false
        Keychain.remove(Key.tokens)
        try? cache?.delete()
        refreshTimer?.invalidate()
        fetches.values.forEach { $0.cancel() }
        fetches = [:]
        weeks = [:]
        loadingWeeks = []
        weekProblems = [:]
        schedule = DaySchedule(events: [])
        accountName = nil
        lastUpdated = nil
        problem = nil
        status = client == nil ? .needsClientID : .disconnected
        onScheduleChanged?()
    }

    // MARK: - Refresh

    func startAutoRefresh() {
        refreshTimer?.invalidate()
        guard status == .connected else { return }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        refreshTimer?.tolerance = 60
    }

    /// The week being browsed, if not this one: refreshed along with this week.
    @ObservationIgnored var browsingWeek: Date?

    /// Refetches this week (and the week being browsed). On failure the previous events
    /// stay, with a note.
    func refresh() async {
        await savedSignIn?.value
        guard status == .connected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        var starts = [weekStart(for: .now)]
        if let browsingWeek, browsingWeek != starts[0] { starts.append(browsingWeek) }
        for start in starts { await fetchWeek(start, force: true) }
        let thisWeek = weekStart(for: .now)
        problem = weekProblems[thisWeek]
        if weeks[thisWeek] == nil {
            // Nothing cached for this week (e.g. after a day change): don't show a stale day.
            schedule = DaySchedule(events: [])
        }
        updateToday()
    }

    /// Makes sure every week touching `from…to` is loaded and no older than `maxAge`.
    /// Throws only when a needed week has no data at all.
    func ensureLoaded(from: Date, to: Date, maxAge: TimeInterval = 5 * 60) async throws {
        await savedSignIn?.value
        guard status == .connected || status == .needsReconnect else { throw IntegrationError.notConnected }
        var start = weekStart(for: from)
        let last = weekStart(for: to)
        var starts: [Date] = []
        while start <= last {
            starts.append(start)
            guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { break }
            start = next
        }
        for start in starts {
            if let week = weeks[start], Date.now.timeIntervalSince(week.fetchedAt) < maxAge { continue }
            await fetchWeek(start, force: false)
        }
        if let missing = starts.first(where: { weeks[$0] == nil }) {
            if status == .needsReconnect { throw IntegrationError.unauthorized }
            throw IntegrationError.invalidResponse(weekProblems[missing] ?? "Couldn't load the calendar.")
        }
    }

    /// Loads a week in the background (the week browser calls this while you scrub).
    func prefetch(around day: Date) {
        guard status == .connected else { return }
        let start = weekStart(for: day)
        for offset in [0, -1, 1] {
            guard let week = calendar.date(byAdding: .weekOfYear, value: offset, to: start) else { continue }
            if weeks[week] == nil || Date.now.timeIntervalSince(weeks[week]!.fetchedAt) > 5 * 60 {
                Task { await fetchWeek(week, force: false) }
            }
        }
    }

    /// Events touching a day, or nil if its week hasn't been loaded.
    func events(on day: Date) -> [CalendarEvent]? {
        let start = weekStart(for: day)
        guard let week = weeks[start] else { return nil }
        return Availability.events(on: day, from: week.events, calendar: calendar)
    }

    func isLoading(_ day: Date) -> Bool { loadingWeeks.contains(weekStart(for: day)) }
    func problem(for day: Date) -> String? { weekProblems[weekStart(for: day)] }

    /// An event anywhere in the loaded weeks.
    func event(id: String) -> CalendarEvent? {
        weeks.values.lazy.flatMap(\.events).first { $0.id == id }
    }

    func weekStart(for day: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? calendar.startOfDay(for: day)
    }

    /// One fetch per week at a time; a second caller waits for the first.
    private func fetchWeek(_ start: Date, force: Bool) async {
        if let running = fetches[start] {
            await running.value
            if !force { return }
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.download(start)
        }
        fetches[start] = task
        await task.value
        if fetches[start] == task { fetches[start] = nil }
    }

    private func download(_ start: Date) async {
        guard let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return }
        loadingWeeks.insert(start)
        defer { loadingWeeks.remove(start) }
        do {
            var events: [CalendarEvent] = []
            var page: String?
            repeat {
                let token = try await validAccessToken()
                let data = try await HTTP.send(GoogleCalendarAPI.eventsRequest(from: start, to: end, pageToken: page, accessToken: token))
                let decoded = try GoogleCalendarAPI.decodeDay(data)
                events += decoded.events
                accountName = decoded.calendarName ?? accountName
                page = decoded.nextPageToken
            } while page != nil
            weeks[start] = Week(start: start, events: events, fetchedAt: .now)
            weekProblems[start] = nil
            if start == weekStart(for: .now) {
                lastUpdated = .now
                problem = nil
            }
            saveCache()
            updateToday()
        } catch IntegrationError.unauthorized {
            status = .needsReconnect
            weekProblems[start] = IntegrationError.unauthorized.userMessage
            problem = IntegrationError.unauthorized.userMessage
        } catch let error as IntegrationError {
            weekProblems[start] = error.userMessage
            log.error("Calendar fetch failed: \(error.userMessage, privacy: .public)")
        } catch {
            weekProblems[start] = error.localizedDescription
        }
    }

    /// Today's events for the Now/Next card and reminders.
    private func updateToday() {
        let today = events(on: .now) ?? []
        let updated = DaySchedule(events: today)
        if updated != schedule {
            schedule = updated
            onScheduleChanged?()
        }
    }

    /// Keeps last week to a few weeks ahead on disk — enough to open quickly offline.
    private func isWorthKeeping(_ start: Date) -> Bool {
        let now = weekStart(for: .now)
        guard let earliest = calendar.date(byAdding: .weekOfYear, value: -1, to: now),
              let latest = calendar.date(byAdding: .weekOfYear, value: 4, to: now) else { return false }
        return start >= earliest && start <= latest
    }

    private func saveCache() {
        let kept = weeks.values.filter { isWorthKeeping($0.start) }.sorted { $0.start < $1.start }
        try? cache?.save(CachedWeeks(accountName: accountName, weeks: kept))
    }

    // MARK: - Changing events

    /// Creates an event. Returns it only once Google has stored it.
    func create(_ draft: EventDraft, presentingFrom window: NSWindow?) async throws -> CalendarEvent {
        let token = try await changeAccessToken(window: window)
        let data = try await HTTP.send(GoogleCalendarAPI.insertRequest(draft, accessToken: token))
        let event = try GoogleCalendarAPI.decodeEvent(data)
        await reload(around: [event.start, event.end])
        return event
    }

    /// Changes an event in place (same id, same guests).
    func update(_ event: CalendarEvent, with changes: EventChanges, presentingFrom window: NSWindow?) async throws -> CalendarEvent {
        let token = try await changeAccessToken(window: window)
        let data = try await HTTP.send(GoogleCalendarAPI.patchRequest(eventID: event.id, changes, accessToken: token))
        let updated = try GoogleCalendarAPI.decodeEvent(data)
        await reload(around: [event.start, updated.start, updated.end])
        return updated
    }

    func delete(_ event: CalendarEvent, presentingFrom window: NSWindow?) async throws {
        let token = try await changeAccessToken(window: window)
        do {
            _ = try await HTTP.send(GoogleCalendarAPI.deleteRequest(eventID: event.id, accessToken: token))
        } catch IntegrationError.notFound {
            // Already gone (deleted in Google Calendar meanwhile) — the outcome the user wanted.
        }
        await reload(around: [event.start])
    }

    /// An access token allowed to change events, asking the user once if needed.
    private func changeAccessToken(window: NSWindow?) async throws -> String {
        if tokens?.canChangeEvents != true {
            await connect(presentingFrom: window, allowChanges: true)
            guard tokens?.canChangeEvents == true else {
                throw IntegrationError.forbidden("Coco wasn't given permission to change events, so nothing was changed.")
            }
        }
        return try await validAccessToken()
    }

    private func reload(around dates: [Date]) async {
        for start in Set(dates.map(weekStart(for:))) { await fetchWeek(start, force: true) }
    }

    private func validAccessToken() async throws -> String {
        guard var current = tokens, let client else { throw IntegrationError.notConnected }
        guard current.isExpired(at: .now) else { return current.accessToken }
        guard let refresh = current.refreshToken else { throw IntegrationError.unauthorized }
        let data = try await HTTP.send(GoogleOAuth.refreshRequest(refreshToken: refresh, client: client))
        current = try GoogleOAuth.decodeTokens(data, now: .now, previousRefreshToken: refresh)
        store(current)
        return current.accessToken
    }

    /// Saves the sign-in so it survives quitting and relaunching. If the Keychain refuses,
    /// say so instead of silently forgetting it.
    private func store(_ new: OAuthTokens) {
        tokens = new
        canChangeEvents = new.canChangeEvents
        guard persistent, let data = try? JSONEncoder().encode(new) else { return }
        if Keychain.set(data, for: Key.tokens) {
            log.notice("Google sign-in saved to the Keychain.")
        } else {
            problem = "Signed in, but the Keychain wouldn't save it (error \(Keychain.lastStatus)), so you'll need to sign in again next launch."
            log.error("Keychain save failed: \(Keychain.lastStatus, privacy: .public)")
        }
    }

    // MARK: - Sign-in sheet

    private func authorize(url: URL, scheme: String, window: NSWindow?) async throws -> URL {
        let anchor = AuthAnchor(window: window ?? NSApp.keyWindow ?? NSWindow())
        self.anchor = anchor
        defer { self.anchor = nil; authSession = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme,
                                                     completionHandler: Self.completion(resuming: continuation))
            session.presentationContextProvider = anchor
            authSession = session
            if !session.start() {
                continuation.resume(throwing: IntegrationError.invalidResponse("Couldn't open the sign-in sheet."))
            }
        }
    }
}

extension GoogleCalendarService {
    /// AuthenticationServices calls this on a background thread. Building it outside the
    /// main actor keeps Swift from treating it as main-thread code (which crashes there);
    /// it only resumes the continuation, which is safe from any thread.
    nonisolated private static func completion(
        resuming continuation: CheckedContinuation<URL, Error>
    ) -> ASWebAuthenticationSession.CompletionHandler {
        { callback, error in
            if let callback {
                continuation.resume(returning: callback)
            } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                continuation.resume(throwing: IntegrationError.cancelled)
            } else {
                continuation.resume(throwing: IntegrationError.invalidResponse(error?.localizedDescription ?? "Sign-in failed."))
            }
        }
    }
}

private final class AuthAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    let window: NSWindow

    init(window: NSWindow) {
        self.window = window
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}

#if DEBUG
extension GoogleCalendarService {
    /// Self-test only: a signed-in state with made-up tokens (requests go to a stand-in server).
    func loadTestSignIn(canChangeEvents: Bool) {
        clientID = "1234567890-selftest.apps.googleusercontent.com"
        let scopes = [GoogleOAuth.scope] + (canChangeEvents ? [GoogleOAuth.changeScope] : [])
        store(OAuthTokens(accessToken: "test", refreshToken: "test", expiresAt: .distantFuture, scopes: scopes))
        status = .connected
    }

    /// Snapshot renderer only: shows sample events without any account or network.
    func loadPreview(events: [CalendarEvent], account: String) {
        accountName = account
        lastUpdated = .now
        status = .connected
        var byWeek: [Date: [CalendarEvent]] = [:]
        for event in events { byWeek[weekStart(for: event.start), default: []].append(event) }
        byWeek[weekStart(for: .now), default: []] += []
        for (start, events) in byWeek { weeks[start] = Week(start: start, events: events, fetchedAt: .distantFuture) }
        updateToday()
    }
}
#endif
