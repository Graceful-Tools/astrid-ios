//  CapabilitiesCoreTests.swift
//  What the deployment offers comes through astrid-core (AITD-620, seventh slice): the command
//  sent, the core's unwrapped answer read into `ServerCapabilities`, and the service keeping its
//  fail-open behaviour around an injected fetch.
//
//  The unit host runs an in-memory core with no network, so the round trip is the core's own test
//  (`services/account.rs`, `an_unknown_capability_is_read_as_unsupported`); this pins the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class CapabilitiesCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testRefreshingIsTheCoresRefreshCapabilitiesCommand_AITD620() throws {
        let sent = try json(ServerCapabilityCommands.refresh())
        XCTAssertEqual(sent["kind"] as? String, "refreshCapabilities")
        XCTAssertEqual(sent.count, 1, "the command carries nothing but its kind")
    }

    /// The core answers the route's `capabilities` object unwrapped; it decodes into the same
    /// shape the screens read, with the brand block and the voice intact.
    func testTheCoresAnswerDecodes_AITD620() throws {
        let answer = #"""
        {"auth":{"google":false,"apple":true,"github":true},
         "sync":{"googleTasks":false},
         "brand":{"appName":"Acme Tasks","feedbackListId":"list-acme"},
         "copy":{"reminders":{"general":["Hey"]}}}
        """#
        let capabilities = try JSONDecoder().decode(ServerCapabilities.self, from: Data(answer.utf8))
        XCTAssertFalse(capabilities.auth.google)
        XCTAssertTrue(capabilities.auth.github)
        XCTAssertFalse(capabilities.sync.googleTasks)
        XCTAssertEqual(capabilities.brand.appName, "Acme Tasks")
        XCTAssertEqual(capabilities.copy?.reminders?.general, ["Hey"])
    }

    func testTheServiceShowsWhatTheFetchAnswered_AITD620() async {
        var stored: [ServerCapabilities.BrandCopy?] = []
        var fetched = ServerCapabilities()
        fetched.auth.google = false
        let service = ServerCapabilityService(fetch: { fetched }, storeCopy: { stored.append($0) })

        await service.refresh()

        XCTAssertFalse(service.capabilities.auth.google)
        XCTAssertEqual(stored.count, 1, "a successful fetch caches the brand's voice")
    }

    /// Fail open: a failed fetch leaves the previous value, and must not overwrite the cached voice.
    func testAFailedFetchKeepsThePreviousAnswer_AITD620() async {
        struct Offline: Error {}
        var stored = 0
        let service = ServerCapabilityService(fetch: { throw Offline() }, storeCopy: { _ in stored += 1 })

        await service.refresh()

        XCTAssertEqual(service.capabilities, .permissive)
        XCTAssertEqual(stored, 0)
    }
}
