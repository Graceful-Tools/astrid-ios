//  MacBoardExpandTests.swift
//  Astrid for Mac — Task efaf8120: board card inline expand/collapse toggle.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardExpandTests: XCTestCase {

    func testTappingClosedCardOpensIt() {
        XCTAssertEqual(MacBoardExpand.toggle(current: nil, tapped: "a"), "a")
    }

    func testTappingOpenCardCollapsesIt() {
        XCTAssertNil(MacBoardExpand.toggle(current: "a", tapped: "a"))
    }

    func testTappingAnotherCardSwitches() {
        XCTAssertEqual(MacBoardExpand.toggle(current: "a", tapped: "b"), "b")
    }
}
#endif
