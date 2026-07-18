//  MacErrorCenterTests.swift
//  Regression for task 8a5f3066 — write failures must surface (not be swallowed) and clear.

import XCTest
@testable import Astrid_Mac

@MainActor
final class MacErrorCenterTests: XCTestCase {

    func testShowSetsCurrentBanner() {
        let center = MacErrorCenter.shared
        center.clear()
        center.show("Something failed")
        XCTAssertEqual(center.current?.text, "Something failed")
        center.clear()
        XCTAssertNil(center.current)
    }

    func testReportFormatsContextAndError() {
        struct E: LocalizedError { var errorDescription: String? { "network down" } }
        let center = MacErrorCenter.shared
        center.clear()
        center.report("Invite user", E())
        XCTAssertEqual(center.current?.text, "Invite user: network down")
        center.clear()
    }
}
