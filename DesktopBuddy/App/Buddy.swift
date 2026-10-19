import Foundation

/// The companion's identity, in one place so it can be renamed or re-skinned.
enum Buddy {
    static let name = "Coco"
}

/// How people reach the developer: the chat's Report link, Settings, and the privacy policy
/// (docs/privacy/index.html) all use this address.
enum Support {
    static let email = "johnkeefedesign@gmail.com"

    /// A new email to support, with the app version added so reports can be traced.
    static func mail(subject: String, body: String = "") -> URL? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body + "\n\n—\nDesktop Buddy \(version) (\(build)), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
        ]
        return components.url
    }

    /// Reporting a chat reply: the reply is quoted so it can be looked at. Nothing is sent
    /// until the user sends the email themselves.
    static func reportReply(_ reply: String) -> URL? {
        let quoted = String(reply.prefix(1500)).split(separator: "\n", omittingEmptySubsequences: false).map { "> " + $0 }.joined(separator: "\n")
        return mail(subject: "Report a reply from \(Buddy.name)",
                    body: "What was wrong with this reply? (Offensive, harmful, wrong, other…)\n\n\n\(quoted)")
    }
}

/// Product switches. Notion was paused on 2026-10-11 and brought back on 2026-10-17; set
/// this to false to hide it again (the code stays, nothing shows or runs).
enum Features {
    static let notion = true
}
