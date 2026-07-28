import XCTest
@testable import Astrid_App

/// Whitelabel (task 97208a72) — the client learns from the server which services a
/// deployment offers, because one build can point at several deployments.
///
/// The decoding behaviour is what matters here and it fails silently if wrong: Swift's
/// synthesized `init(from:)` THROWS on a missing key even when the property has a
/// default value. A server that omits a section — an older deployment, or a newer one
/// that reorganised — would fail the whole decode, and the app would fall back to
/// permissive without anyone noticing the payload was never read.
final class ServerCapabilitiesTests: XCTestCase {

    private func decode(_ json: String) throws -> ServerCapabilities {
        try JSONDecoder().decode(ServerCapabilities.self, from: Data(json.utf8))
    }

    func testDecodesAFullResponse() throws {
        let caps = try decode("""
        {
          "auth": { "google": false, "apple": true, "passkey": true },
          "sync": { "googleTasks": false, "githubIssues": true },
          "integrations": { "mcp": true, "openclaw": false, "chatgptActions": false },
          "services": { "emailToTask": false, "calendarFeed": true }
        }
        """)

        XCTAssertFalse(caps.auth.google)
        XCTAssertTrue(caps.auth.passkey)
        XCTAssertFalse(caps.sync.googleTasks)
        XCTAssertTrue(caps.sync.githubIssues)
        XCTAssertFalse(caps.integrations.openclaw)
        XCTAssertFalse(caps.services.emailToTask)
    }

    /// A newer server may add sections; an older one may omit them.
    func testMissingSectionsDefaultToAvailable() throws {
        let caps = try decode(#"{ "sync": { "googleTasks": false } }"#)

        XCTAssertFalse(caps.sync.googleTasks, "present key should be honoured")
        XCTAssertTrue(caps.sync.githubIssues, "missing key in a present section defaults on")
        XCTAssertTrue(caps.auth.google, "missing section defaults on")
        XCTAssertTrue(caps.integrations.mcp)
        XCTAssertTrue(caps.services.calendarFeed)
    }

    func testEmptyObjectDecodesToFullyPermissive() throws {
        XCTAssertEqual(try decode("{}"), ServerCapabilities.permissive)
    }

    /// Extra keys from a newer server must not break an older client.
    func testUnknownKeysAreIgnored() throws {
        let caps = try decode("""
        { "sync": { "googleTasks": true, "somethingNew": false }, "brandNewSection": { "x": 1 } }
        """)

        XCTAssertEqual(caps, ServerCapabilities.permissive)
    }

    func testPermissiveEnablesEverything() {
        let caps = ServerCapabilities.permissive

        XCTAssertTrue(caps.auth.google)
        XCTAssertTrue(caps.auth.apple)
        XCTAssertTrue(caps.auth.passkey)
        XCTAssertTrue(caps.sync.googleTasks)
        XCTAssertTrue(caps.sync.githubIssues)
        XCTAssertTrue(caps.integrations.mcp)
        XCTAssertTrue(caps.integrations.openclaw)
        XCTAssertTrue(caps.integrations.chatgptActions)
        XCTAssertTrue(caps.services.emailToTask)
        XCTAssertTrue(caps.services.calendarFeed)
    }
}
