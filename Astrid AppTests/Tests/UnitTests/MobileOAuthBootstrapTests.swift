import XCTest

final class MobileOAuthBootstrapTests: XCTestCase {
    /// Regression for Astrid task a403bcc6-991d-49c4-9600-8cc60dd0bcf9.
    func testAppEntryPointDoesNotEmbedOrBootstrapOAuthClientSecret() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("AstridApp.swift"),
            encoding: .utf8
        )

        XCTAssertFalse(source.contains("configureOAuth()"))
        XCTAssertFalse(source.contains("OAuthManager.shared.configure(clientSecret:"))
        XCTAssertNil(
            source.range(of: #"let clientSecret\s*=\s*\"[0-9a-fA-F]{32,}\""#, options: .regularExpression),
            "The mobile app must not contain a static OAuth client secret"
        )
    }
}
