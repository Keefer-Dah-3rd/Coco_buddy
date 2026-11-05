import Foundation
import BuddyIntegrations

/// One place where requests go out, so every response is classified the same way
/// (offline, needs reconnect, rate limited…) and nothing is cached to disk.
enum HTTP {
    private static let session = makeSession()

    /// An ephemeral session: nothing cached to disk, no waiting for connectivity, and the
    /// self-tests' stand-in server when one is set. `cookies: false` also refuses cookies and
    /// the memory cache — for pages read on the user's behalf (Partiful).
    static func makeSession(timeout: TimeInterval = 20, cookies: Bool = true) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.waitsForConnectivity = false
        if !cookies {
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCache = nil
        }
        #if DEBUG
        if let stand = standIn { configuration.protocolClasses = [stand] }
        #endif
        return URLSession(configuration: configuration)
    }

    #if DEBUG
    /// Self-tests only: answers every request in-process instead of the network. Must be set
    /// before the first request.
    nonisolated(unsafe) static var standIn: AnyClass?
    #endif

    /// Like `send`, but also hands back the response (for caching headers), and treats
    /// 304 Not Modified as success with no body.
    static func fetch(_ request: URLRequest) async throws -> (data: Data?, response: HTTPURLResponse) {
        let (data, http) = try await exchange(request)
        if http.statusCode == 304 { return (nil, http) }
        try check(http, body: data)
        return (data, http)
    }

    static func send(_ request: URLRequest) async throws -> Data {
        let (data, http) = try await exchange(request)
        try check(http, body: data)
        return data
    }

    /// The transport step: a response of any status, or an `IntegrationError` for no response at all.
    private static func exchange(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw IntegrationError.from(transport: error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw IntegrationError.invalidResponse("No HTTP response.")
        }
        return (data, http)
    }

    private static func check(_ http: HTTPURLResponse, body: Data) throws {
        if let error = IntegrationError.from(status: http.statusCode, body: body,
                                             retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            throw error
        }
    }
}
