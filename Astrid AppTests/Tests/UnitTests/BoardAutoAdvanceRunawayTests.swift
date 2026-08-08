//  BoardAutoAdvanceRunawayTests.swift
//  Regression tests for Task 84595f3c-faa1-4c09-87b7-4d5f7a2edbc6 —
//  "iOS Board tasks jumps around way too much on drag. I now cannot move a task
//   to another board without it immediately jumping to the next board"
//
//  A regression from the edge auto-advance added for task 233ec244. Three
//  compounding faults made it fire almost constantly:
//
//  1. The advance loop repeated every 0.3s for as long as the drag point stayed
//     in an edge zone, so one entry walked the board across every column.
//  2. The zone was 18% of the width floored at 44pt — ~70pt per side on a 390pt
//     phone, i.e. 36% of the screen. On iPhone a column IS the screen, so a card
//     dragged anywhere near a side was inside a zone.
//  3. It fired on dwell alone. The feature was asked for as "move the board
//     after some meaningful movement to right or left"; a card picked up near an
//     edge and held still fired without the user having moved at all.
//
//  These tests pin the gate that replaces all three.

import XCTest
import CoreGraphics
@testable import Astrid_App

final class BoardAutoAdvanceRunawayTests: XCTestCase {

    private let past = boardAutoAdvanceTravelThreshold + 10
    private let short = boardAutoAdvanceTravelThreshold - 10

    // MARK: - THE BUG: one entry advanced the board forever

    /// The heart of the report. Having advanced once, sitting in the same edge
    /// zone must NOT advance again — the drag has to leave and come back. The
    /// old loop just kept going every 0.3s.
    func testDoesNotAdvanceTwiceWithoutLeavingTheEdgeZone() {
        XCTAssertFalse(boardShouldAutoAdvance(edge: .trailing,
                                              travelSincePickup: past,
                                              hasFiredForThisEntry: true),
                       "holding at the edge must move the board ONE column, not walk it across the board")
    }

    /// Leaving the zone resets the entry, so a deliberate second gesture works.
    /// Multi-column moves stay possible — they just cost one gesture each.
    func testAdvancesAgainAfterLeavingAndReenteringTheZone() {
        XCTAssertTrue(boardShouldAutoAdvance(edge: .trailing,
                                             travelSincePickup: past,
                                             hasFiredForThisEntry: false))
    }

    // MARK: - THE BUG: it fired without the user moving

    /// A card picked up near the right edge and held still has travelled
    /// nothing. It must not fire — this is "meaningful movement", the thing the
    /// feature was actually asked for.
    func testDoesNotFireWhenTheCardWasMerelyPickedUpNearAnEdge() {
        XCTAssertFalse(boardShouldAutoAdvance(edge: .trailing,
                                              travelSincePickup: 0,
                                              hasFiredForThisEntry: false),
                       "picking a card up inside an edge zone is not a request to scroll")
    }

    func testDoesNotFireOnMovementShorterThanTheThreshold() {
        XCTAssertFalse(boardShouldAutoAdvance(edge: .trailing,
                                              travelSincePickup: short,
                                              hasFiredForThisEntry: false))
    }

    func testFiresAfterMeaningfulMovementTowardTheEdge() {
        XCTAssertTrue(boardShouldAutoAdvance(edge: .trailing,
                                             travelSincePickup: past,
                                             hasFiredForThisEntry: false))
        XCTAssertTrue(boardShouldAutoAdvance(edge: .leading,
                                             travelSincePickup: -past,
                                             hasFiredForThisEntry: false))
    }

    /// Travel is signed and must match the edge. Drifting left into the leading
    /// zone is not a request to advance rightward, and vice versa.
    func testMovementAwayFromTheEdgeNeverFiresIt() {
        XCTAssertFalse(boardShouldAutoAdvance(edge: .trailing,
                                              travelSincePickup: -past,
                                              hasFiredForThisEntry: false))
        XCTAssertFalse(boardShouldAutoAdvance(edge: .leading,
                                              travelSincePickup: past,
                                              hasFiredForThisEntry: false))
    }

    /// Over the cards — the great majority of any drag — nothing fires.
    func testNeverFiresOutsideAnEdgeZone() {
        XCTAssertFalse(boardShouldAutoAdvance(edge: nil,
                                              travelSincePickup: past * 3,
                                              hasFiredForThisEntry: false))
    }

    // MARK: - THE BUG: the hot zone covered a third of the screen

    /// 44pt per side was a *floor*, chosen as a touch target — but this is a
    /// region you drag through, not one you tap, and the floor is what made a
    /// 390pt phone 36% hot. The middle of the column must stay a safe place to
    /// drag a card without the board moving.
    func testEdgeZonesLeaveMostOfAPhoneColumnSafeToDragIn() {
        let zone = boardAutoAdvanceEdgeWidth(containerWidth: 390)
        XCTAssertLessThanOrEqual(zone * 2, 390 * 0.25,
                                 "both zones together must stay under a quarter of the screen; "
                                 + "they used to cover 36% of it")
        XCTAssertGreaterThanOrEqual(zone, 32, "still has to be reachable mid-drag")
    }

    /// The middle of a phone column is nowhere near an edge zone.
    func testTheCardAreaOfAPhoneColumnIsNotAnEdgeZone() {
        for x in stride(from: CGFloat(80), through: 310, by: 10) {
            XCTAssertNil(boardAutoAdvanceEdge(dragX: x, containerWidth: 390),
                         "x=\(x) should be safe drop area, not a scroll trigger")
        }
    }
}
