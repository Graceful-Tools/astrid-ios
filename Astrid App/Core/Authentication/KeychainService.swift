import Security
@preconcurrency import Foundation

final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()
    
    private init() {}
    
    // MARK: - Session Cookie Management

    func saveSessionCookie(_ cookie: String) throws {
        try save(key: Constants.Keychain.sessionCookieKey, value: cookie)
    }

    func getSessionCookie() throws -> String {
        try get(key: Constants.Keychain.sessionCookieKey)
    }

    func deleteSessionCookie() throws {
        try delete(key: Constants.Keychain.sessionCookieKey)
    }


    func getMCPToken() -> String? {
        return try? get(key: Constants.Keychain.mcpTokenKey)
    }

    func deleteMCPToken() {
        try? delete(key: Constants.Keychain.mcpTokenKey)
    }

    // MARK: - OAuth Token Management

    func saveOAuthClientSecret(_ secret: String) {
        try? save(key: "oauth_client_secret", value: secret)
    }

    func getOAuthClientSecret() -> String? {
        return try? get(key: "oauth_client_secret")
    }

    func deleteOAuthClientSecret() {
        try? delete(key: "oauth_client_secret")
    }

    func saveOAuthAccessToken(_ token: String) throws {
        try save(key: "oauth_access_token", value: token)
    }

    func getOAuthAccessToken() throws -> String {
        try get(key: "oauth_access_token")
    }

    func deleteOAuthAccessToken() throws {
        try delete(key: "oauth_access_token")
    }

    // MARK: - Generic Keychain Operations
    
    /// Base query shared by every operation.
    ///
    /// `kSecUseDataProtectionKeychain` matters on macOS (security audit 2026-07-25): without it,
    /// SecItem uses the legacy file-based login keychain, where `kSecAttrAccessible` is IGNORED
    /// and items are protected only by keychain ACLs. With it, the Mac app gets the same
    /// per-app, sandbox-isolated, accessibility-honoring storage the iOS app already has.
    /// On iOS the flag is the default, so this is a no-op there.
    private func baseQuery(key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key
        ]
        #if os(macOS)
        query[kSecUseDataProtectionKeychain as String] = true
        #endif
        return query
    }

    private func save(key: String, value: String) throws {
        // Never persist test credentials into the user's real keychain.
        if Self.isUITesting { return }
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        var query = baseQuery(key: key)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        // Delete any existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// UI tests must NEVER reach the real account. They run against the shipping bundle id, so
    /// the app would otherwise restore the user's real session from the keychain and create lists
    /// on the server — which is exactly what happened once a UI test stopped forcing offline mode.
    /// Under the UI-test flag the credential store reads as EMPTY, so the user's own session is
    /// unreachable however the test behaves.
    ///
    /// The flag check moved to `UITestSession` (task b7fd8f70): this file spelled it
    /// `-uiTesting` while every test passed `--uitesting`, so the guard never actually ran.
    ///
    /// EXCEPTION, and the only one: a session cookie handed to the run explicitly. That is the
    /// dedicated `uitest@astrid.cc` account, which exists so the suite can be signed in at all
    /// (task 44a9cea5) — without it every test that needs an account skips itself. Nothing is
    /// inherited; a run is signed in only when someone passed it a credential.
    private static let isUITesting = UITestSession.isUITesting

    private func get(key: String) throws -> String {
        if Self.isUITesting {
            if key == Constants.Keychain.sessionCookieKey,
               let injected = UITestSession.injectedCookie {
                return injected
            }
            throw KeychainError.notFound
        }
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)

        #if os(macOS)
        // Migration: builds before the audit wrote to the legacy keychain. Read the old item
        // once, re-save it into the data-protection keychain, and delete the legacy copy — so
        // existing Mac users are not silently signed out by the hardening above.
        if status == errSecItemNotFound {
            var legacy: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: Constants.Keychain.service,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            legacy[kSecUseDataProtectionKeychain as String] = false
            var legacyResult: AnyObject?
            if SecItemCopyMatching(legacy as CFDictionary, &legacyResult) == errSecSuccess,
               let data = legacyResult as? Data,
               let value = String(data: data, encoding: .utf8) {
                try? save(key: key, value: value)
                legacy.removeValue(forKey: kSecReturnData as String)
                legacy.removeValue(forKey: kSecMatchLimit as String)
                SecItemDelete(legacy as CFDictionary)
                result = data as AnyObject
                status = errSecSuccess
            }
        }
        #endif
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        
        return value
    }
    
    private func delete(key: String) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)

        #if os(macOS)
        // Sign-out must also clear anything left in the legacy keychain by an older build,
        // otherwise a stale session cookie survives on disk after the user signs out.
        var legacy: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key
        ]
        legacy[kSecUseDataProtectionKeychain as String] = false
        SecItemDelete(legacy as CFDictionary)
        #endif

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Errors

enum KeychainError: LocalizedError {
    case encodingFailed
    case saveFailed(OSStatus)
    case notFound
    case deleteFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode value for keychain"
        case .saveFailed(let status):
            return "Failed to save to keychain: \(status)"
        case .notFound:
            return "Item not found in keychain"
        case .deleteFailed(let status):
            return "Failed to delete from keychain: \(status)"
        }
    }
}
