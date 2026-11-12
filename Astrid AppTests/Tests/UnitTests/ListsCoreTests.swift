//  ListsCoreTests.swift
//  Share links, resolving them, and list insights go through astrid-core (AITD-620, sixth slice):
//  the commands sent, and the core's answers read into the shapes the screens already use.
//
//  The unit host runs an in-memory core with no network, so the round trips are the core's own
//  tests (`services/share.rs`, `services/list.rs`); what is pinned here is the Swift half.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class ListsCoreTests: XCTestCase {
    private func json(_ command: CoreCommand) throws -> [String: Any] {
        let data = Data(try CoreJSON.encode(command).utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: Share links

    func testATaskLinkIsTheCoresShareTaskCommand_AITD620() throws {
        let sent = try json(try ShortcodeCommands.link(targetType: "task", targetId: "t-1"))
        XCTAssertEqual(sent["kind"] as? String, "shareTask")
        XCTAssertEqual(sent["taskId"] as? String, "t-1")
    }

    func testAListLinkIsTheCoresShareListCommand_AITD620() throws {
        let sent = try json(try ShortcodeCommands.link(targetType: "list", targetId: "l-9"))
        XCTAssertEqual(sent["kind"] as? String, "shareList")
        XCTAssertEqual(sent["listId"] as? String, "l-9")
    }

    /// The server mints links only for tasks and lists; anything else is refused before sending,
    /// never quietly turned into a task link.
    func testAnUnknownTargetIsRefusedBeforeSending_AITD620() {
        XCTAssertThrowsError(try ShortcodeCommands.link(targetType: "comment", targetId: "c-1"))
    }

    /// The core answers `{ url }`; the share screens read `.url` from it as before.
    func testTheCoresLinkAnswerDecodes_AITD620() throws {
        let answer = try JSONDecoder().decode(ShortcodeResponse.self,
                                              from: Data(#"{"url":"https://astrid.cc/s/xyz"}"#.utf8))
        XCTAssertEqual(answer.url, "https://astrid.cc/s/xyz")
    }

    // MARK: Resolving a link

    func testResolvingIsTheCoresResolveShortcodeCommand_AITD620() throws {
        let sent = try json(ShortcodeCommands.resolve(code: "abc123"))
        XCTAssertEqual(sent["kind"] as? String, "resolveShortcode")
        XCTAssertEqual(sent["code"] as? String, "abc123")
    }

    func testTheCoresResolutionDecodes_AITD620() throws {
        let resolved = try JSONDecoder().decode(ShortcodeResolution.self,
                                                from: Data(#"{"targetType":"list","targetId":"l-9"}"#.utf8))
        XCTAssertEqual(resolved.targetType, "list")
        XCTAssertEqual(resolved.targetId, "l-9")
    }

    // MARK: Insights

    func testInsightsAreTheCoresListInsightsCommand_AITD620() throws {
        let sent = try json(ListInsightsCommands.insights(listId: "list-1", days: 7,
                                                          timeZone: "America/Los_Angeles"))
        XCTAssertEqual(sent["kind"] as? String, "listInsights")
        XCTAssertEqual(sent["listId"] as? String, "list-1")
        XCTAssertEqual(sent["days"] as? Int, 7)
        XCTAssertEqual(sent["timeZone"] as? String, "America/Los_Angeles")
    }

    /// The service hands its fetch the window and the caller's zone, and keeps the TTL cache it
    /// had on the HTTP client (AITD-554).
    func testTheServiceFetchesTheWindowInTheCallersZone_AITD620() async throws {
        var asked: [(String, Int, String)] = []
        let service = ListInsightsService(fetch: { listId, days, zone in
            asked.append((listId, days, zone))
            throw URLError(.notConnectedToInternet)
        })
        _ = try? await service.insights(listId: "list-1", days: 90,
                                        timeZone: TimeZone(identifier: "Europe/Berlin")!)
        XCTAssertEqual(asked.count, 1)
        XCTAssertEqual(asked.first?.0, "list-1")
        XCTAssertEqual(asked.first?.1, 90)
        XCTAssertEqual(asked.first?.2, "Europe/Berlin")
    }
}
