import Foundation

/// Every way a connected service can fail, in terms the UI can act on.
public enum IntegrationError: Error, Equatable, Sendable {
    /// No credentials stored.
    case notConnected
    /// The Mac is offline or the service couldn't be reached.
    case offline
    /// Credentials expired or were revoked — the user needs to reconnect.
    case unauthorized
    /// Connected, but not allowed to see this (e.g. a Notion page not shared with the integration).
    case forbidden(String)
    case notFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case server(status: Int)
    /// The response wasn't in the expected shape (or a property no longer matches the mapping).
    case invalidResponse(String)
    /// The user closed the sign-in sheet.
    case cancelled

    public var userMessage: String {
        switch self {
        case .notConnected: "Not connected."
        case .offline: "Can't reach the service — check your connection."
        case .unauthorized: "Access expired or was revoked. Reconnect to continue."
        case .forbidden(let detail): detail.isEmpty ? "Access to this was denied." : detail
        case .notFound(let detail): detail.isEmpty ? "Not found." : detail
        case .rateLimited: "Too many requests — trying again shortly."
        case .server(let status): "The service had a problem (\(status)). Try again later."
        case .invalidResponse(let detail): "Unexpected response: \(detail)"
        case .cancelled: "Sign-in was cancelled."
        }
    }

    /// Maps an HTTP response to an error, or nil for success.
    public static func from(status: Int, body: Data, retryAfter: String? = nil) -> IntegrationError? {
        switch status {
        case 200..<300: return nil
        case 401: return .unauthorized
        case 403: return .forbidden(Self.message(in: body))
        case 404: return .notFound(Self.message(in: body))
        case 429: return .rateLimited(retryAfter: retryAfter.flatMap(TimeInterval.init))
        case 400 where Self.code(in: body) == "invalid_grant": return .unauthorized
        case 400..<500: return .invalidResponse(Self.message(in: body))
        default: return .server(status: status)
        }
    }

    /// Classifies transport errors (no response at all).
    public static func from(transport error: Error) -> IntegrationError {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return .cancelled
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .timedOut, .dnsLookupFailed, .dataNotAllowed:
                return .offline
            default: break
            }
        }
        return .offline
    }

    private static func json(_ body: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    private static func code(in body: Data) -> String? {
        json(body)?["error"] as? String ?? json(body)?["code"] as? String
    }

    /// Google: {"error": {"message": …}} or {"error_description": …}; Notion: {"message": …}.
    private static func message(in body: Data) -> String {
        guard let object = json(body) else { return "" }
        if let message = object["message"] as? String { return message }
        if let description = object["error_description"] as? String { return description }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String { return message }
        return ""
    }
}

/// Builds `application/x-www-form-urlencoded` bodies.
enum FormEncoding {
    static func encode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}
