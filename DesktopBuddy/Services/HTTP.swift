import Foundation
import BuddyIntegrations

/// One place where requests go out, so every response is classified the same way
/// (offline, needs reconnect, rate limited…) and nothing is cached to disk.
enum HTTP {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

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
