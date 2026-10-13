import Foundation
import OSLog
import BuddyIntegrations

/// Reads a Partiful invitation the user shared in chat. Fetches only from Partiful (redirects
/// included), sends no cookies or sign-in, says who it is, and never tries to get past a
/// password, sign-in or bot check — it reports them instead. Results are kept for a few
/// minutes, so sharing the same link again doesn't fetch it again.
final class EventLinkReader {
    enum Failure: Error, Equatable {
        case notPartiful
        /// The link redirected away from Partiful; it wasn't followed.
        case leftPartiful
        case notFound
        case passwordProtected
        case accessDenied
        case blocked
        case unreadable
        case offline
        case failed(String)

        /// What the assistant hears (it explains this to the user in its own words).
        var explanation: String {
            switch self {
            case .notPartiful:
                "That isn't a Partiful event link (partiful.com/e/… or go.partiful.com/…). Only Partiful invitations can be read; "
                    + "for anything else, ask the user to paste the event details."
            case .leftPartiful:
                "That link redirects away from Partiful, so Coco didn't follow it. Ask the user for the partiful.com/e/… link "
                    + "or the event details."
            case .notFound:
                "Partiful says this event doesn't exist — the link may be mistyped, or the host deleted the event. "
                    + "Ask the user to check the link, or paste the invitation text."
            case .passwordProtected:
                "This invitation is password-protected, and Coco can't enter passwords for other sites. "
                    + "Ask the user to paste the event details (title, date, time, place) from the invitation."
            case .accessDenied:
                "Partiful wouldn't show this event without signing in, which Coco doesn't do. "
                    + "Ask the user to paste the event details from the invitation."
            case .blocked:
                "Partiful didn't let Coco read the page just now (it may be limiting automated requests). "
                    + "Don't retry right away — ask the user to paste the event details, or try again in a few minutes."
            case .unreadable:
                "The page opened, but it had no event details to read (it may be private or only visible after RSVPing). "
                    + "Ask the user to paste the invitation text."
            case .offline:
                "This Mac seems to be offline, so the link couldn't be opened."
            case .failed(let reason):
                "The link couldn't be read (\(reason)). Ask the user to paste the event details instead."
            }
        }
    }

    private struct Cached {
        let at: Date
        let result: Result<LinkedEvent, Failure>
    }

    private var cache: [URL: Cached] = [:]
    private let log = Logger(subsystem: "com.keefer.DesktopBuddy", category: "links")
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        #if DEBUG
        if let stand = HTTP.standIn { configuration.protocolClasses = [stand] }
        #endif
        return URLSession(configuration: configuration)
    }()
    private static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "DesktopBuddy/\(version) (macOS; reads an invitation link its user shared)"
    }()
    private static let maxBytes = 3_000_000

    func read(_ text: String) async -> Result<LinkedEvent, Failure> {
        // The link itself, or the first Partiful link in whatever text was passed along with it.
        guard let (url, link) = Partiful.link(from: text) ?? Partiful.links(in: text).first.flatMap({ Partiful.link(from: $0.absoluteString) })
        else { return .failure(.notPartiful) }
        let key: URL = if case .event(let id) = link { Partiful.canonicalURL(id: id) } else { url }
        if let cached = cache[key], Date.now.timeIntervalSince(cached.at) < 10 * 60 { return cached.result }

        let result = await fetch(url)
        if case .failure(.offline) = result {} else { cache[key] = Cached(at: .now, result: result) }
        if case .success(let event) = result { cache[event.url] = Cached(at: .now, result: result) }
        switch result {
        case .success(let event): log.info("Read Partiful event \(event.id, privacy: .public)")
        case .failure(let failure): log.error("Couldn't read Partiful link: \(String(describing: failure), privacy: .public)")
        }
        return result
    }

    private func fetch(_ url: URL) async -> Result<LinkedEvent, Failure> {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let guardian = RedirectGuard(allow: Partiful.mayFetch)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request, delegate: guardian)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed].contains(error.code) {
            return .failure(.offline)
        } catch let error as URLError where error.code == .timedOut {
            return .failure(.failed("Partiful took too long to answer"))
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        if guardian.refused { return .failure(.leftPartiful) }
        guard let http = response as? HTTPURLResponse, let finalURL = http.url, Partiful.mayFetch(finalURL) else {
            return .failure(.notPartiful)
        }
        switch http.statusCode {
        case 200..<300: break
        case 404, 410: return .failure(.notFound)
        case 401, 403: return .failure(http.statusCode == 403 && data.isEmpty ? .blocked : .accessDenied)
        case 429, 503: return .failure(.blocked)
        default: return .failure(.failed("Partiful answered \(http.statusCode)"))
        }
        guard data.count <= Self.maxBytes, let html = String(data: data, encoding: .utf8) else { return .failure(.unreadable) }
        // A redirect to a sign-in page or anywhere that isn't an event: nothing to read.
        guard case .event? = Partiful.link(from: finalURL.absoluteString)?.link else {
            return .failure(finalURL.path.contains("login") ? .accessDenied : .unreadable)
        }
        switch Partiful.parse(html: html, url: finalURL) {
        case .event(let event): return .success(event)
        case .passwordProtected: return .failure(.passwordProtected)
        case .unreadable: return .failure(.unreadable)
        }
    }
}

/// Follows redirects only to places `allow` accepts, and at most a few hops.
nonisolated final class RedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let allow: @Sendable (URL) -> Bool
    private var hops = 0
    private var _refused = false
    var refused: Bool { lock.withLock { _refused } }

    init(allow: @escaping @Sendable (URL) -> Bool) {
        self.allow = allow
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        let allowed: Bool = lock.withLock {
            hops += 1
            let ok = hops <= 5 && request.url.map(allow) == true
            if !ok { _refused = true }
            return ok
        }
        completionHandler(allowed ? request : nil)
    }
}
