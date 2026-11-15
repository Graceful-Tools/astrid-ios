//  BoardCardCalloutTests.swift
//  AITD-679: "Stop opening board task details by expanding the board task. Open, just like task
//  details from a task row, but pick the left or right side based on the spacing on screen."
//  A board card on iPad opens the row's details panel, docked on the side with more room, with its
//  arrow on the card. The side and the arrow are astrid-core's `calloutPlacement` (AITD-678).

import XCTest
@testable import Astrid_App

final class BoardCardCalloutTests: XCTestCase {

    // MARK: - Where a tap goes

    func testOnIPadACardTapOpensThePanelNotTheCardInline_AITD679() {
        XCTAssertEqual(BoardCardCallout.route(splitLayout: true, forcePush: false), .panel)
    }

    func testOnIPhoneACardTapPushesTheFullDetails_AITD642() {
        XCTAssertEqual(BoardCardCallout.route(splitLayout: false, forcePush: false), .push)
        XCTAssertEqual(BoardCardCallout.route(splitLayout: true, forcePush: true), .push)
    }

    func testTappingTheOpenCardClosesItAndAnotherCardMovesIt_AITD679() {
        XCTAssertEqual(BoardCardCallout.toggle(current: nil, tapped: "a"), "a")
        XCTAssertNil(BoardCardCallout.toggle(current: "a", tapped: "a"))
        XCTAssertEqual(BoardCardCallout.toggle(current: "a", tapped: "b"), "b")
    }

    // MARK: - Which side (the core's rule)

    private let board = CGRect(x: 0, y: 0, width: 1180, height: 820)

    func testACardInALeftColumnOpensThePanelOnTheRight_AITD679() {
        let card = CGRect(x: 16, y: 200, width: 280, height: 72)
        XCTAssertEqual(BoardCardCallout.side(card: card, viewport: board, panelWidth: 480), .trailing)
    }

    func testACardInARightColumnOpensThePanelOnTheLeft_AITD679() {
        let card = CGRect(x: 884, y: 200, width: 280, height: 72)
        XCTAssertEqual(BoardCardCallout.side(card: card, viewport: board, panelWidth: 480), .leading,
                       "the right-hand column is as likely to be tapped as the left; it must not end up under the panel")
    }

    func testEqualRoomOpensOnTheRight_AITD679() {
        let card = CGRect(x: 450, y: 200, width: 280, height: 72)
        XCTAssertEqual(BoardCardCallout.side(card: card, viewport: board, panelWidth: 480), .trailing)
    }

    // MARK: - The panel touches the card (the core's rule)

    /// Jon, on the iPad build: "the arrow doesn't touch the task row. It looks like the task
    /// details is aligned to the left or right of the screen, but doesn't touch the task row."
    func testThePanelsNearEdgeTouchesTheCardOnTheRight_AITD679() throws {
        let card = CGRect(x: 16, y: 200, width: 280, height: 72)
        let placed = try XCTUnwrap(BoardCardCallout.placement(card: card, viewport: board, panelWidth: 480))
        XCTAssertEqual(placed.side, .trailing)
        XCTAssertEqual(placed.frame.minX, card.maxX, accuracy: 0.001, "not docked at the screen's edge")
    }

    func testThePanelsNearEdgeTouchesTheCardOnTheLeft_AITD679() throws {
        let card = CGRect(x: 884, y: 200, width: 280, height: 72)
        let placed = try XCTUnwrap(BoardCardCallout.placement(card: card, viewport: board, panelWidth: 480))
        XCTAssertEqual(placed.side, .leading)
        XCTAssertEqual(placed.frame.maxX, card.minX, accuracy: 0.001)
    }

    func testThePanelIsAsTallAsTheBoardAllowsAndKeepsOffItsEdges_AITD679() throws {
        let card = CGRect(x: 16, y: 200, width: 280, height: 72)
        let placed = try XCTUnwrap(BoardCardCallout.placement(card: card, viewport: board, panelWidth: 480))
        XCTAssertEqual(placed.frame.minY, board.minY + BoardCardCallout.gutter, accuracy: 0.001)
        XCTAssertEqual(placed.frame.maxY, board.maxY - BoardCardCallout.gutter, accuracy: 0.001)
    }

    /// The arrow's tip lands on the panel's near edge, so on the card.
    func testTheArrowsTipLandsOnThePanelsEdge_AITD679() {
        let room = BoardCardCallout.arrowRoom(arrowWidth: 12, overlap: 1)
        // face starts `room` in; the arrow spans [face - width + overlap, face + overlap].
        XCTAssertEqual(room - 12 + 1, 0, accuracy: 0.001)
    }

    // MARK: - Where the arrow points (the core's rule)

    private let panel = CGRect(x: 600, y: 8, width: 480, height: 800)

    func testTheArrowPointsAtTheCardsMiddle_AITD679() {
        let card = CGRect(x: 16, y: 300, width: 280, height: 64)   // middle at 332
        XCTAssertEqual(BoardCardCallout.arrowY(card: card, panel: panel), 332 - 8, accuracy: 0.001)
    }

    func testTheArrowStaysOffTheRoundedCorners_AITD679() {
        let top = CGRect(x: 16, y: -40, width: 280, height: 40)
        XCTAssertEqual(BoardCardCallout.arrowY(card: top, panel: panel), 20, accuracy: 0.001,
                       "core ARROW_MARGIN")
        let bottom = CGRect(x: 16, y: 900, width: 280, height: 40)
        XCTAssertEqual(BoardCardCallout.arrowY(card: bottom, panel: panel), 800 - 20, accuracy: 0.001)
    }

    func testACardThatScrolledAwayCentresTheArrow_AITD679() {
        XCTAssertEqual(BoardCardCallout.arrowY(card: nil, panel: panel), 400, accuracy: 0.001)
    }
}
