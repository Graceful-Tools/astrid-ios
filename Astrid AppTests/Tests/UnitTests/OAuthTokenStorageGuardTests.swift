import XCTest

final class OAuthTokenStorageGuardTests: XCTestCase {
    /// Regression for Astrid task 562f3d02-9efd-4d0e-b961-7a1dabcbe05d.
    func testOAuthAccessTokenUsesKeychainAndSignOutClearsLegacyStorage() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manager = try String(contentsOf: root.appendingPathComponent("Astrid App/Core/Authentication/OAuthManager.swift"), encoding: .utf8)
        let keychain = try String(contentsOf: root.appendingPathComponent("Astrid App/Core/Authentication/KeychainService.swift"), encoding: .utf8)
        let authManager = try String(contentsOf: root.appendingPathComponent("Astrid App/Core/Authentication/AuthManager.swift"), encoding: .utf8)

        XCTAssertTrue(keychain.contains("saveOAuthAccessToken"))
        XCTAssertTrue(keychain.contains("deleteOAuthAccessToken"))
        XCTAssertTrue(manager.contains("saveOAuthAccessToken"))
        XCTAssertFalse(manager.contains("UserDefaults.standard.set(data, forKey: \"oauth_token_cache\")"))
        XCTAssertTrue(manager.contains("removeObject(forKey: CacheKey.legacyToken)"))
        XCTAssertTrue(authManager.contains("deleteOAuthAccessToken"))
        XCTAssertTrue(authManager.contains("removeObject(forKey: \"oauth_token_cache\")"))
    }
}
