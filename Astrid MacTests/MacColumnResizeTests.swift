//  MacColumnResizeTests.swift
//  Regression guard for AITD-329 — "[mac] add ability to update the width of the columns with some
//  reasonable minimum widths".
//
//  The brief that shapes every assertion here: "current column width a fine minimum". Both side
//  columns become draggable, and the widths they ship at become the FLOOR — the resize can only
//  ever give a column more room than it has today, never less.

import XCTest
@testable import Astrid_Mac

final class MacColumnResizeTests: XCTestCase {

    /// A content area with room to spare, so the clamp under test is the floor, not the fit.
    private let roomy: CGFloat = 1_600

    // MARK: - The floors

    func testTheSidebarCannotBeDraggedBelowTheWidthItShipsAt() {
        XCTAssertEqual(MacLayout.sidebarMinWidth, MacLayout.sidebarIdealWidth,
                       "The shipped width IS the minimum — that is the whole brief")
    }

    func testTheSidebarFloorRoseToTheShippedWidth() {
        // It was min: 200 / ideal: 240, so a drag could take the rail 40pt below what it ships at.
        XCTAssertGreaterThanOrEqual(MacLayout.sidebarMinWidth, 240)
    }

    func testASidebarDragIsStillCappedSoTheRailStaysARail() {
        XCTAssertGreaterThan(MacLayout.sidebarMaxWidth, MacLayout.sidebarMinWidth)
    }

    func testTheChatColumnCannotBeDraggedBelowTheWidthItShipsAt() {
        let narrowed = MacLayout.resolvedChatColumnWidth(requested: 100, contentWidth: roomy)

        XCTAssertEqual(narrowed, MacLayout.chatColumnMinWidth,
                       "Below this the pop-out's arrow would run through the rows it points at")
    }

    func testTheChatColumnFloorIsTheDerivedWidthThatMakesTheArrowMeetTheRows() {
        XCTAssertEqual(MacLayout.chatColumnMinWidth, MacLayout.chatColumnWidth)
    }

    func testAnUnsetPreferenceLandsOnTheShippedWidth() {
        // @AppStorage starts at 0 on a fresh install; that must resolve to today's layout.
        XCTAssertEqual(MacLayout.resolvedChatColumnWidth(requested: 0, contentWidth: roomy),
                       MacLayout.chatColumnMinWidth)
    }

    // MARK: - The ceiling

    func testWideningTheChatColumnIsAllowed() {
        XCTAssertEqual(MacLayout.resolvedChatColumnWidth(requested: 520, contentWidth: roomy), 520)
    }

    func testTheChatColumnStopsBeforeTheRowsBecomeUnreadable() {
        let resolved = MacLayout.resolvedChatColumnWidth(requested: 5_000, contentWidth: roomy)

        let rowsLeft = roomy - resolved - MacLayout.columnDividerWidth
        XCTAssertEqual(rowsLeft, MacLayout.listColumnMinWidth, accuracy: 0.001,
                       "A drag to the far edge must leave the task rows their minimum, not zero")
    }

    func testInAContentAreaTooNarrowForBothTheFloorWins() {
        // No width satisfies the rows' minimum AND the chat floor. Shrinking the chat column below
        // its floor would break the pop-out geometry; narrow rows are the lesser harm.
        let cramped = MacLayout.chatColumnMinWidth + 50

        XCTAssertEqual(MacLayout.resolvedChatColumnWidth(requested: 800, contentWidth: cramped),
                       MacLayout.chatColumnMinWidth)
    }

    // MARK: - The arrow geometry survives the resize

    /// AITD-302 derived the chat column width so the pop-out's arrow TIP clears the row's trailing
    /// edge by exactly `detailArrowRowGap`. That derivation assumed one fixed width. Making the
    /// column draggable would have left the arrow pointing at empty space where the rows used to
    /// end — unless the pop-out gives back exactly what the column gained, which is what this pins.
    ///
    /// WHERE it gives those points back changed in AITD-334: they were the pop-out's trailing
    /// PADDING and are the card's WIDTH now, so the card fills the message pane instead of being
    /// pushed left of a growing gutter. The clearance this test exists for is unaffected — that is
    /// the point of taking the width at the trailing edge — so the invariant is unchanged and only
    /// the expression of the card's leading edge moved.
    func testTheArrowKeepsTheSameClearanceAtEveryColumnWidth() {
        let contentRight: CGFloat = 1_000

        for width in [MacLayout.chatColumnMinWidth, 450, 520, 640] as [CGFloat] {
            let panel = MacLayout.resolvedDetailPanelWidth(chatColumnWidth: width)
            let cardLeft = contentRight - MacLayout.detailPopoutTrailingPadding - panel
            let arrowTip = cardLeft - (MacLayout.detailArrowWidth - MacLayout.arrowOverlap)
            let rowRight = contentRight - width - MacLayout.columnDividerWidth - MacLayout.rowTrailingGap

            XCTAssertEqual(arrowTip - rowRight, MacLayout.detailArrowRowGap, accuracy: 0.001,
                           "Clearance drifted at a chat column width of \(width)")
        }
    }

    func testAtTheDefaultWidthThePopoutPaddingIsUnchanged() {
        // The resize must not move anything for a user who never drags.
        XCTAssertEqual(MacLayout.detailPopoutTrailingPadding, MacLayout.detailPanelMargin)
    }

    func testTheRowsNeverGiveUpWidthTwice() {
        // The card takes back exactly what the column gained — no more, or it would drift off the
        // trailing edge; no less, and the gutter AITD-334 removed comes back. It arrives as WIDTH
        // now rather than as padding, so this is asserted on the width.
        let gained: CGFloat = 90

        XCTAssertEqual(
            MacLayout.resolvedDetailPanelWidth(chatColumnWidth: MacLayout.chatColumnMinWidth + gained)
                - MacLayout.resolvedDetailPanelWidth(chatColumnWidth: MacLayout.chatColumnMinWidth),
            gained, accuracy: 0.001)
    }
}
