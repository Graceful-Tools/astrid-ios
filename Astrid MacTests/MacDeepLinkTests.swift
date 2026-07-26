//  MacDeepLinkTests.swift
//  Regression for task 84993a68 — deep-link parsing for tasks & lists over both the custom
//  scheme (astrid://) and universal links (https://astrid.cc).

import XCTest
@testable import Astrid_Mac

final class MacDeepLinkTests: XCTestCase {

    private func parse(_ s: String) -> MacDeepLink? { MacDeepLink.parse(URL(string: s)!) }

    func testCustomSchemeTask() { XCTAssertEqual(parse("astrid://tasks/abc123"), .task("abc123")) }
    func testCustomSchemeList() { XCTAssertEqual(parse("astrid://lists/list-9"), .list("list-9")) }

    func testUniversalLinkTask() { XCTAssertEqual(parse("https://astrid.cc/tasks/t-42"), .task("t-42")) }
    func testUniversalLinkList() { XCTAssertEqual(parse("https://www.astrid.cc/lists/l-7"), .list("l-7")) }

    func testMissingIdReturnsNil() { XCTAssertNil(parse("astrid://tasks")) }
    func testUnknownHostReturnsNil() { XCTAssertNil(parse("astrid://users/u1")) }
    func testForeignURLReturnsNil() { XCTAssertNil(parse("https://example.com/tasks/x")) }

    // MARK: - Security regressions (audit 2026-07-25)
    //
    // A deep link is attacker-supplied input, and its id flowed into `/api/v1/tasks/<id>`.
    // These previously parsed successfully: `astrid://tasks/a%2F..%2Fadmin` yielded the id
    // "a/../admin", producing a request to `/api/v1/tasks/a/../admin` — which a server or CDN
    // normalizes to a different endpoint and executes with the signed-in user's session.

    func testPercentEncodedTraversalIsRejected() {
        XCTAssertNil(parse("astrid://tasks/a%2F..%2Fadmin"))
        XCTAssertNil(parse("astrid://lists/%2E%2E%2F%2E%2E%2Fapi"))
    }

    func testTraversalInUniversalLinkIsRejected() {
        XCTAssertNil(parse("https://astrid.cc/tasks/a%2F..%2Fadmin"))
    }

    func testNonHttpsSchemeClaimingOurHostIsRejected() {
        // http:// (or any other scheme) with our host must not be treated as a trusted link.
        XCTAssertNil(parse("http://astrid.cc/tasks/t-42"))
        XCTAssertNil(parse("ftp://astrid.cc/tasks/t-42"))
    }

    func testOversizedIdentifierIsRejected() {
        XCTAssertNil(parse("astrid://tasks/\(String(repeating: "a", count: 200))"))
    }

    func testOrdinaryIdsStillParse() {
        // The guard must not break real links.
        XCTAssertEqual(parse("astrid://tasks/2bdd5df3-1a2b-4c3d-9e8f-000000000000"),
                       .task("2bdd5df3-1a2b-4c3d-9e8f-000000000000"))
        XCTAssertEqual(parse("https://astrid.cc/lists/temp_123"), .list("temp_123"))
    }
}
