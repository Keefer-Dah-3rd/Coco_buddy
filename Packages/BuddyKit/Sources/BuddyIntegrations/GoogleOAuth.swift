import CryptoKit
import Foundation

/// Proof Key for Code Exchange: proves the app that finishes sign-in is the one that started it,
/// so no client secret is needed in the app.
public struct PKCE: Sendable, Equatable {
    public let verifier: String
    public let challenge: String

    public init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        self.init(verifier: Data(bytes).base64URLEncoded())
    }

    public init(verifier: String) {
        self.verifier = verifier
        self.challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

public struct OAuthTokens: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date

    public init(accessToken: String, refreshToken: String?, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    /// Treats tokens as expired a minute early so requests don't race the deadline.
    public func isExpired(at now: Date) -> Bool {
        now.addingTimeInterval(60) >= expiresAt
    }
}

/// Google sign-in for a native Mac app: an **iOS**-type OAuth client (Google's guidance for
/// macOS), the reversed client ID as the redirect scheme, PKCE, and no client secret.
/// Read-only access to calendar events is the only scope requested.
public enum GoogleOAuth {
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let revokeEndpoint = URL(string: "https://oauth2.googleapis.com/revoke")!
    public static let scope = "https://www.googleapis.com/auth/calendar.events.readonly"

    public struct Client: Equatable, Sendable {
        public let clientID: String

        /// nil unless this looks like a Google OAuth client ID.
        public init?(clientID: String) {
            let trimmed = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasSuffix(".apps.googleusercontent.com"), trimmed.count > 30, !trimmed.contains(" ") else { return nil }
            self.clientID = trimmed
        }

        /// "123-abc.apps.googleusercontent.com" → "com.googleusercontent.apps.123-abc"
        public var callbackScheme: String {
            clientID.split(separator: ".").reversed().joined(separator: ".")
        }

        public var redirectURI: String { "\(callbackScheme):/oauth2redirect" }
    }

    public static func authorizationURL(client: Client, pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: client.clientID),
            URLQueryItem(name: "redirect_uri", value: client.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Pulls the authorization code out of the redirect, checking `state` against forgery.
    public static func authorizationCode(from callback: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw error == "access_denied" ? IntegrationError.cancelled : IntegrationError.invalidResponse(error)
        }
        guard value("state") == expectedState else { throw IntegrationError.invalidResponse("Sign-in state didn't match.") }
        guard let code = value("code"), !code.isEmpty else { throw IntegrationError.invalidResponse("No authorization code.") }
        return code
    }

    public static func tokenRequest(code: String, pkce: PKCE, client: Client) -> URLRequest {
        formRequest(tokenEndpoint, [
            ("code", code),
            ("client_id", client.clientID),
            ("redirect_uri", client.redirectURI),
            ("grant_type", "authorization_code"),
            ("code_verifier", pkce.verifier),
        ])
    }

    public static func refreshRequest(refreshToken: String, client: Client) -> URLRequest {
        formRequest(tokenEndpoint, [
            ("refresh_token", refreshToken),
            ("client_id", client.clientID),
            ("grant_type", "refresh_token"),
        ])
    }

    public static func revokeRequest(token: String) -> URLRequest {
        formRequest(revokeEndpoint, [("token", token)])
    }

    /// Decodes a token response. Refresh responses usually omit the refresh token, so the
    /// previous one is kept.
    public static func decodeTokens(_ data: Data, now: Date, previousRefreshToken: String? = nil) throws -> OAuthTokens {
        struct Response: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
            let scope: String?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw IntegrationError.invalidResponse("Couldn't read the sign-in response.")
        }
        if let granted = response.scope, !granted.split(separator: " ").contains(Substring(scope)) {
            throw IntegrationError.forbidden("Calendar access wasn't granted. Reconnect and allow viewing events.")
        }
        return OAuthTokens(accessToken: response.access_token,
                           refreshToken: response.refresh_token ?? previousRefreshToken,
                           expiresAt: now.addingTimeInterval(response.expires_in))
    }

    private static func formRequest(_ url: URL, _ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormEncoding.encode(fields)
        return request
    }
}

extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
