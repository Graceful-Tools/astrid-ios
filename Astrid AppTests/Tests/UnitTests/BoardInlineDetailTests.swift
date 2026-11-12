//  BoardInlineDetailTests.swift
//  AITD-628 — "[ios board] Enable open task details inline on board, like on web and Mac app".
//  Tapping a card left the board (iPhone push, iPad panel). It now opens the details inline under
//  the card; these pin the open/close rules the board view asks.

import XCTest
@testable import Astrid_App

final class BoardInlineDetailTests: XCTestCase {

    func testTappingAClosedCardOpensIt_AITD628() {
        XCTAssertEqual(BoardCardExpansion.toggle(current: nil, tapped: "a"), "a")
    }

    func testTappingTheOpenCardClosesIt_AITD628() {
        XCTAssertNil(BoardCardExpansion.toggle(current: "a", tapped: "a"))
    }

    func testTappingAnotherCardMovesTheOpenCard_AITD628() {
        XCTAssertEqual(BoardCardExpansion.toggle(current: "a", tapped: "b"), "b",
                       "one card open at a time across the board")
    }

    func testOpenCardCollapsesWhenItLeavesTheBoard_AITD628() {
        XCTAssertNil(BoardCardExpansion.retained(current: "gone", visibleTaskIds: ["a", "b"]))
        XCTAssertEqual(BoardCardExpansion.retained(current: "a", visibleTaskIds: ["a", "b"]), "a")
        XCTAssertNil(BoardCardExpansion.retained(current: nil, visibleTaskIds: ["a"]))
    }

    func testInlineDetailsTakeABoundedShareOfTheBoard_AITD628() {
        XCTAssertEqual(BoardCardExpansion.inlineDetailHeight(boardHeight: 1000), 720, accuracy: 0.5)
        XCTAssertEqual(BoardCardExpansion.inlineDetailHeight(boardHeight: 200),
                       BoardCardExpansion.minimumInlineDetailHeight,
                       "a short board still gets usable details")
    }
}
