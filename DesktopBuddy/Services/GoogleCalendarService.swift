import AppKit
import AuthenticationServices
import Observation
import BuddyCore
import BuddyIntegrations
import os

/// Google Calendar, read-only. Shows "connected" only after a real sign-in succeeded,
/// and keeps the last good schedule (with its timestamp) when a refresh fails.
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
    private(set) var schedule = DaySchedule(events: [])
    private(set) var lastUpdated: Date?
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
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let cache: JSONFileStore<CachedDay>?
    @ObservationIgnored private let persistent: Bool
    @ObservationIgnored private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "calendar")

    private struct CachedDay: Codable {
        var day: Date
        var accountName: String?
        var events: [CalendarEvent]
        var fetchedAt: Date
    }

    private enum Key {
        static let clientID = "calendar.google.clientID"
        static let reminder = "calendar.reminderMinutes"
        static let tokens = "google.oauth.tokens"
    }

    init(persistent: Bool = true, defaults: UserDefaults = .standard) {
        self.persistent = persistent
        self.defaults = defaults
        cache = persistent ? try? JSONFileStore(name: "calendar-cache") : nil
        clientID = defaults.string(forKey: Key.clientID) ?? ""
        reminderMinutes = defaults.object(forKey: Key.reminder) as? Int ?? 5

        if persistent, let data = Keychain.data(for: Key.tokens),
           let saved = try? JSONDecoder().decode(OAuthTokens.self, from: data) {
            tokens = saved
            status = .connected
            if let cached = try? cache?.load(), Calendar.current.isDateInToday(cached.day) {
                schedule = DaySchedule(events: cached.events)
                accountName = cached.accountName
                lastUpdated = cached.fetchedAt
            }
        } else {
            status = client == nil ? .needsClientID : .disconnected
        }
    }

    // MARK: - Connect / disconnect

    /// Signs in with Google in the system sheet (PKCE, no client secret).
    func connect(presentingFrom window: NSWindow?) async {
        guard let client else { status = .needsClientID; return }
        status = .connecting
        problem = nil
        let pkce = PKCE()
        let state = UUID().uuidString
        do {
            let callback = try await authorize(url: GoogleOAuth.authorizationURL(client: client, pkce: pkce, state: state),
                                               scheme: client.callbackScheme, window: window)
            let code = try GoogleOAuth.authorizationCode(from: callback, expectedState: state)
            let data = try await HTTP.send(GoogleOAuth.tokenRequest(code: code, pkce: pkce, client: client))
            store(try GoogleOAuth.decodeTokens(data, now: .now))
            status = .connected
            await refresh()
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

    /// Revokes access at Google (best effort) and deletes every token and cached event.
    func disconnect() async {
        if let token = tokens?.refreshToken ?? tokens?.accessToken {
            _ = try? await HTTP.send(GoogleOAuth.revokeRequest(token: token))
        }
        tokens = nil
        Keychain.remove(Key.tokens)
        try? cache?.delete()
        refreshTimer?.invalidate()
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

    /// Fetches today's events. On failure the previous schedule stays, with a note.
    func refresh() async {
        guard status == .connected, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let token = try await validAccessToken()
            let data = try await HTTP.send(GoogleCalendarAPI.eventsRequest(for: .now, accessToken: token))
            let day = try GoogleCalendarAPI.decodeDay(data)
            schedule = DaySchedule(events: day.events)
            accountName = day.calendarName
            lastUpdated = .now
            problem = nil
            try? cache?.save(CachedDay(day: .now, accountName: accountName, events: day.events, fetchedAt: .now))
            onScheduleChanged?()
        } catch IntegrationError.unauthorized {
            status = .needsReconnect
            problem = IntegrationError.unauthorized.userMessage
        } catch let error as IntegrationError {
            problem = error.userMessage
            log.error("Calendar refresh failed: \(error.userMessage, privacy: .public)")
        } catch {
            problem = error.localizedDescription
        }
        // A cached schedule from yesterday is no use today.
        if let lastUpdated, !Calendar.current.isDateInToday(lastUpdated) {
            schedule = DaySchedule(events: [])
            onScheduleChanged?()
        }
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
    /// Snapshot renderer only: shows sample events without any account or network.
    func loadPreview(events: [CalendarEvent], account: String) {
        schedule = DaySchedule(events: events)
        accountName = account
        lastUpdated = .now
        status = .connected
    }
}
#endif
