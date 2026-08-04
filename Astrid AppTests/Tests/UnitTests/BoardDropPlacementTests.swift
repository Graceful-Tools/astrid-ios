//  BoardDropPlacementTests.swift
//  Regression tests for Task 2b2c9ee2-3b2a-4cc7-9278-bae2bcdda5bd —
//  "[ios] dropping task anywhere on board should move it. Currently it is finiky"
//
//  The column used to stack three competing drop targets: one per card, one
//  append slot at the bottom, and a column-wide fallback that ALWAYS inserted at
//  index 0. Everything the card targets didn't cover — the 6pt gaps between
//  cards, the column header, the add-task footer — fell through to that fallback,
//  so releasing a card there sent it to the top of the column instead of where
//  the user let go. That is the "finicky".
//
//  The fix resolves the release point against the cards' measured frames, so
//  EVERY point in the column maps to a slot. These tests pin that mapping.

import XCTest
import CoreGraphics
@testable import Astrid_App

final class BoardDropPlacementTests: XCTestCase {

    /// Three 60pt cards with 6pt gaps, laid out from y = 100 (below a header).
    private let slots: [BoardCardSlot] = [
        BoardCardSlot(taskId: "a", minY: 100, maxY: 160),
        BoardCardSlot(taskId: "b", minY: 166, maxY: 226),
        BoardCardSlot(taskId: "c", minY: 232, maxY: 292),
    ]

    // MARK: - THE BUG: the gaps between cards were dead zones

    /// A release in the 6pt gap between card A and card B is unambiguous: the
    /// user wants it between them. It used to fall through to the column
    /// fallback and land at index 0.
    func testDropInTheGapBetweenTwoCardsLandsBetweenThem() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 163, slots: slots), 1,
                       "a release in the gap under card A must insert after A, not jump to the top")
    }

    /// The header is the other dead zone, but there the old index-0 answer was
    /// the right one — above every card.
    func testDropOnTheHeaderLandsAtTheTop() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 12, slots: slots), 0)
    }

    /// The add-task footer sits below the last card, so a release there appends.
    /// This used to send the card to the TOP — the most confusing outcome of all.
    func testDropOnTheFooterAppendsAtTheEnd() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 420, slots: slots), slots.count,
                       "releasing below the last card must append, not jump to the top")
    }

    // MARK: - Within a card: which half decides the side

    func testDropOnTheTopHalfOfACardInsertsAboveIt() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 110, slots: slots), 0)
        XCTAssertEqual(boardDropInsertionIndex(dropY: 176, slots: slots), 1)
    }

    func testDropOnTheBottomHalfOfACardInsertsBelowIt() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 155, slots: slots), 1)
        XCTAssertEqual(boardDropInsertionIndex(dropY: 221, slots: slots), 2)
    }

    func testDropOnTheLastCardsBottomHalfAppends() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 288, slots: slots), 3)
    }

    // MARK: - Degenerate geometry still resolves

    /// An empty column has one slot: the only one.
    func testEmptyColumnAlwaysResolvesToZero() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: 0, slots: []), 0)
        XCTAssertEqual(boardDropInsertionIndex(dropY: 900, slots: []), 0)
    }

    /// Frames are measured in the column's own coordinate space, so a drag that
    /// starts above the column's origin can report a negative y.
    func testNegativeYResolvesToTheTop() {
        XCTAssertEqual(boardDropInsertionIndex(dropY: -40, slots: slots), 0)
    }

    /// The answer is always a usable insertion index — never out of bounds for
    /// `Array.insert(_:at:)`, whatever the geometry.
    func testResultIsAlwaysAValidInsertionIndex() {
        for y in stride(from: CGFloat(-200), through: 1000, by: 7) {
            let index = boardDropInsertionIndex(dropY: y, slots: slots)
            XCTAssertTrue((0...slots.count).contains(index),
                          "y=\(y) produced out-of-range index \(index)")
        }
    }

    // MARK: - The indicator must not move the targets under the pointer

    /// The second half of "finicky": the hover indicator used to be a SIBLING in
    /// the card's VStack, so showing it pushed the card down, out from under the
    /// pointer — which ended the hover, which hid the indicator, which moved the
    /// card back. An overlay indicator leaves the slot geometry untouched, so
    /// the index the user sees is the index they get.
    func testIndicatorDoesNotChangeTheSlotGeometryItPointsAt() {
        let hovering = boardDropInsertionIndex(dropY: 163, slots: slots)
        let offsetForIndicator = boardDropIndicatorOffset(forInsertionIndex: hovering, slots: slots)

        // The indicator is positioned from the existing frames; it never asks the
        // stack for space of its own.
        XCTAssertEqual(offsetForIndicator, 163, accuracy: 4,
                       "the indicator should sit in the gap it represents")
        XCTAssertEqual(boardDropInsertionIndex(dropY: 163, slots: slots), hovering,
                       "showing the indicator must not change where the drop would land")
    }

    func testIndicatorSitsAboveTheFirstCardForIndexZero() {
        XCTAssertEqual(boardDropIndicatorOffset(forInsertionIndex: 0, slots: slots), 100,
                       accuracy: 0.01)
    }

    func testIndicatorSitsBelowTheLastCardForTheAppendIndex() {
        XCTAssertEqual(boardDropIndicatorOffset(forInsertionIndex: 3, slots: slots), 292,
                       accuracy: 0.01)
    }
}
