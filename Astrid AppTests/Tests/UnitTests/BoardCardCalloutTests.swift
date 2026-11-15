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

    // MARK: - The open card is the details (AITD-661)

    /// AITD-661: "Hide unexpanded card on open". The details opened UNDER the card face, so the
    /// open card showed its title twice: once on the face, once in the details header. The face
    /// gives way to the details, the way the Mac board's card turns into its editor.
    func testTheOpenCardHidesItsFace_AITD661() {
        XCTAssertFalse(BoardCardExpansion.showsCardFace(taskId: "a", expandedTaskId: "a"))
    }

    /// Every other card keeps its face, whether or not some card is open.
    func testClosedCardsKeepTheirFace_AITD661() {
        XCTAssertTrue(BoardCardExpansion.showsCardFace(taskId: "b", expandedTaskId: "a"))
        XCTAssertTrue(BoardCardExpansion.showsCardFace(taskId: "b", expandedTaskId: nil))
    }

    /// AITD-661: "make left arrow an up arrow to close". The inline details fold back UP into the
    /// card, so their leading control is an up chevron, the Mac board card's collapse caret,
    /// and reads "Close" rather than "Back": nothing is behind it to go back to.
    func testInlineDetailsCloseWithAnUpChevron_AITD661() {
        XCTAssertEqual(TaskDetailHeader.backSymbol(collapsesInPlace: true), "chevron.up")
        XCTAssertEqual(TaskDetailHeader.backLabelKey(collapsesInPlace: true), "actions.close")
    }

    /// The panel and the push still go back to the left.
    func testThePanelAndThePushKeepTheLeftChevron_AITD661() {
        XCTAssertEqual(TaskDetailHeader.backSymbol(collapsesInPlace: false), "chevron.left")
        XCTAssertEqual(TaskDetailHeader.backLabelKey(collapsesInPlace: false), "actions.back")
    }
}
