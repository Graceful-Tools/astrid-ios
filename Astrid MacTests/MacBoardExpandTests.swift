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

    // MARK: AITD-575 — the rails under the control and the caret close the card

    func testAITD575_aRailClosesTheOpenCard() {
        XCTAssertNil(MacBoardExpand.railTap(current: "a", tapped: "a"))
    }

    func testAITD575_aRailDoesWhatTheCaretDoes() {
        for (current, tapped) in [(nil, "a"), ("a", "a"), ("a", "b")] as [(String?, String)] {
            XCTAssertEqual(MacBoardExpand.railTap(current: current, tapped: tapped),
                           MacBoardExpand.toggle(current: current, tapped: tapped))
        }
    }

}
#endif
