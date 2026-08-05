//  BoardDragEdgeAutoAdvanceTests.swift
//  Regression tests for Task 233ec244-cf0e-4960-b7d2-dd6906a901aa —
//  "[iphone] in boards it is hard to move tasks from board to board. Let's move
//   the board (left or right) after some meaningful movement to right or left
//   when dragging a task. Currently it doesn't respond quickly"
//
//  On iPhone one column fills the screen, so the column you want to drop into is
//  almost never on screen when you pick a card up. The drag session owns the
//  gesture, so the carousel's swipe can't help — the user has to drop the card,
//  swipe, and pick it up again.
//
//  The fix: hot zones at the board's leading and trailing edges. Holding a
//  dragged card over one advances the board a column, and keeps advancing while
//  the card stays there. These tests pin the hot-zone size and the advance
//  policy — the two places where "doesn't respond quickly" and "flies across the
//  whole board" live.

import XCTest
import CoreGraphics
@testable import Astrid_App

final class BoardDragEdgeAutoAdvanceTests: XCTestCase {

    // MARK: - Hot zone size
    //
    // The three assertions below originally required a 44pt *minimum*, reasoning
    // that a smaller zone would be an unhittable touch target. That was wrong,
    // and task 84595f3c is the bill for it: an edge zone is a region you drag
    // THROUGH, not one you tap, and the 44pt floor made 36% of a 390pt phone a
    // scroll trigger. The numbers were revised deliberately — see
    // BoardAutoAdvanceRunawayTests.

    /// Reachable while dragging one-handed, without eating the card area you're
    /// trying to drop into.
    func testEdgeZoneIsAReachableFractionOfAPhoneWidth() {
        let zone = boardAutoAdvanceEdgeWidth(containerWidth: 390)
        XCTAssertGreaterThanOrEqual(zone, 32, "too narrow to reach mid-drag")
        XCTAssertLessThanOrEqual(zone, 390 * 0.125, "the zone must not swallow the drop area")
    }

    /// On an iPad the same fraction would be a huge strip, so it's capped.
    func testEdgeZoneIsCappedOnWideBoards() {
        XCTAssertLessThanOrEqual(boardAutoAdvanceEdgeWidth(containerWidth: 1366), 64)
    }

    /// Degenerate widths still leave a usable target rather than a zero-width one.
    func testEdgeZoneNeverCollapses() {
        XCTAssertGreaterThanOrEqual(boardAutoAdvanceEdgeWidth(containerWidth: 0), 32)
        XCTAssertGreaterThanOrEqual(boardAutoAdvanceEdgeWidth(containerWidth: -10), 32)
    }

    // MARK: - Which edge a drag point is in

    func testPointNearTheLeadingEdgeIsTheLeadingZone() {
        XCTAssertEqual(boardAutoAdvanceEdge(dragX: 10, containerWidth: 390), .leading)
    }

    func testPointNearTheTrailingEdgeIsTheTrailingZone() {
        XCTAssertEqual(boardAutoAdvanceEdge(dragX: 384, containerWidth: 390), .trailing)
    }

    func testPointInTheMiddleIsNotAnEdgeZone() {
        XCTAssertNil(boardAutoAdvanceEdge(dragX: 195, containerWidth: 390),
                     "dragging over the cards must not scroll the board out from under you")
    }

    // MARK: - Advance policy

    func testTrailingEdgeAdvancesOneColumnAtATime() {
        XCTAssertEqual(boardAutoAdvanceTarget(currentIndex: 0, edge: .trailing, columnCount: 4), 1,
                       "one dwell moves one column — not a fling across the board")
        XCTAssertEqual(boardAutoAdvanceTarget(currentIndex: 2, edge: .trailing, columnCount: 4), 3)
    }

    func testLeadingEdgeGoesBackOneColumn() {
        XCTAssertEqual(boardAutoAdvanceTarget(currentIndex: 2, edge: .leading, columnCount: 4), 1)
    }

    /// THE BUG this guards against on the other side: the board must stop at the
    /// ends instead of wrapping around, or a held card would loop the carousel.
    func testStopsAtTheLastColumn() {
        XCTAssertNil(boardAutoAdvanceTarget(currentIndex: 3, edge: .trailing, columnCount: 4))
    }

    func testStopsAtTheFirstColumn() {
        XCTAssertNil(boardAutoAdvanceTarget(currentIndex: 0, edge: .leading, columnCount: 4))
    }

    func testEmptyOrSingleColumnBoardNeverAdvances() {
        XCTAssertNil(boardAutoAdvanceTarget(currentIndex: 0, edge: .trailing, columnCount: 1))
        XCTAssertNil(boardAutoAdvanceTarget(currentIndex: 0, edge: .leading, columnCount: 0))
    }

    /// The current column comes from a scroll-position binding that can lag or
    /// hold a stale id; an out-of-range index must not crash or wrap.
    func testOutOfRangeCurrentIndexIsClamped() {
        XCTAssertNil(boardAutoAdvanceTarget(currentIndex: 99, edge: .trailing, columnCount: 4))
        XCTAssertEqual(boardAutoAdvanceTarget(currentIndex: 99, edge: .leading, columnCount: 4), 2)
        XCTAssertEqual(boardAutoAdvanceTarget(currentIndex: -5, edge: .trailing, columnCount: 4), 1)
    }

    // MARK: - Dwell

    /// "Currently it doesn't respond quickly" — so the first advance has to come
    /// fast enough to feel like a response, while still being long enough that
    /// crossing the edge on the way to a card doesn't trigger it.
    func testFirstAdvanceIsQuickButNotInstant() {
        XCTAssertGreaterThan(boardAutoAdvanceDwell, 0.1,
                             "instant would fire while merely passing the edge")
        XCTAssertLessThanOrEqual(boardAutoAdvanceDwell, 0.5,
                                 "longer than half a second reads as the board ignoring you")
    }
}
