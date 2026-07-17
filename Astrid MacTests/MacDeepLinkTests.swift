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
}
