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

    // MARK: - The details' full-screen button (AITD-636)

    /// Jon: "full screen doesn't go directly to full screen on iPad. It should." On iPad the button
    /// opened the side panel, one more tap away from full screen. It opens the task full screen.
    func testOnIPadTheFullScreenButtonOpensTheTaskFullScreen_AITD636() {
        XCTAssertEqual(BoardCardExpansion.fullDetailsRoute(splitLayout: true, forcePush: false),
                       .panel(fullScreen: true))
    }

    /// iPhone, or an iPad that pushes, has only one way to show a task: the full-screen push.
    func testWithoutASplitLayoutItPushes_AITD636() {
        XCTAssertEqual(BoardCardExpansion.fullDetailsRoute(splitLayout: false, forcePush: false), .push)
        XCTAssertEqual(BoardCardExpansion.fullDetailsRoute(splitLayout: true, forcePush: true), .push)
    }

    // MARK: - Where a card tap goes (AITD-642)

    /// AITD-642 — "On iPhone open task details old way on board". A phone column is too narrow
    /// for the details to fit under the card, so a tap there opens the full-screen push again.
    func testOnIPhoneACardTapOpensTheFullDetails_AITD642() {
        XCTAssertFalse(BoardCardExpansion.cardTapOpensInline(splitLayout: false))
    }

    /// iPad keeps the inline details AITD-628 brought.
    func testOnIPadACardTapStillOpensInline_AITD642() {
        XCTAssertTrue(BoardCardExpansion.cardTapOpensInline(splitLayout: true))
    }
}
