import Foundation
import Security

/// Credentials live in the user's login Keychain, readable only by this app's signature —
/// never in files, UserDefaults or logs.
enum Keychain {
    nonisolated private static let service = "com.keefer.DesktopBuddy"
    /// Result of the last write, for diagnostics (never includes the secret).
    private(set) static var lastStatus: OSStatus = errSecSuccess

    /// Reads off the main thread. Keychain lookups wait on the lower-priority security
    /// daemon, which blocks (and flags as a hang risk) when done on the main thread.
    nonisolated static func dataInBackground(for account: String) async -> Data? {
        await Task.detached(priority: .utility) { data(for: account) }.value
    }

    nonisolated static func stringInBackground(for account: String) async -> String? {
        await dataInBackground(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    nonisolated static func data(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    @discardableResult
    static func set(_ data: Data, for account: String) -> Bool {
        let match: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        lastStatus = SecItemUpdate(match as CFDictionary, attributes as CFDictionary)
        if lastStatus == errSecSuccess { return true }
        lastStatus = SecItemAdd(match.merging(attributes) { $1 } as CFDictionary, nil)
        return lastStatus == errSecSuccess
    }

    static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func string(for account: String) -> String? {
        data(for: account).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func set(_ string: String, for account: String) {
        set(Data(string.utf8), for: account)
    }
}
