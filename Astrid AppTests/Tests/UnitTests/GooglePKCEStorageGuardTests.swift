import XCTest

final class GooglePKCEStorageGuardTests: XCTestCase {
    /// Regression for Astrid task 968463ad-14a0-42d9-9ad2-a37ff317aaa2.
    func testPKCEVerifierIsNeverPersisted() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Authentication/GoogleSignInManager.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("UserDefaults.standard.set(codeVerifier"))
        XCTAssertTrue(source.contains("UserDefaults.standard.removeObject(forKey: \"GoogleOAuthCodeVerifier\")"))
        XCTAssertTrue(source.contains("codeVerifier: codeVerifier"), "Verifier must remain available to the in-memory callback")
    }
}
