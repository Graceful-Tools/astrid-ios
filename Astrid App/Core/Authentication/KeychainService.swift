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
    
    private func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        // Delete any existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    private func get(key: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        
        return value
    }
    
    private func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.Keychain.service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
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
