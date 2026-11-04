import Foundation
import BuddyIntegrations

/// One place where requests go out, so every response is classified the same way
/// (offline, needs reconnect, rate limited…) and nothing is cached to disk.
enum HTTP {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        #if DEBUG
        if let stand = standIn { configuration.protocolClasses = [stand] }
        #endif
        return URLSession(configuration: configuration)
    }()

    #if DEBUG
    /// Self-tests only: answers every request in-process instead of the network. Must be set
    /// before the first request.
    nonisolated(unsafe) static var standIn: AnyClass?
    #endif

    /// Like `send`, but also hands back the response (for caching headers), and treats
    /// 304 Not Modified as success with no body.
    static func fetch(_ request: URLRequest) async throws -> (data: Data?, response: HTTPURLResponse) {
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
        if http.statusCode == 304 { return (nil, http) }
        if let error = IntegrationError.from(status: http.statusCode, body: data,
                                             retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            throw error
        }
        return (data, http)
    }

    static func send(_ request: URLRequest) async throws -> Data {
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
        if let error = IntegrationError.from(status: http.statusCode, body: data,
                                             retryAfter: http.value(forHTTPHeaderField: "Retry-After")) {
            throw error
        }
        return data
    }
}
