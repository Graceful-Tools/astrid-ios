//  MacBoardScrollSnapTests.swift
//  ADEV-315: "for mac we should make the left to right scroll on the board view snap to boards
//  like we do on ipad".
//
//  On iPad a sideways swipe moves the board one column and settles on that column's leading
//  edge. The Mac board scrolled freely and stopped wherever the trackpad fling ran out —
//  half a column showing on each side.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardScrollSnapTests: XCTestCase {

    /// The Mac board snaps one column at a time, the rule iPad's multi-column board uses.
    func testMacBoardSnapsColumnByColumn_ADEV315() {
        XCTAssertEqual(MacBoardView.scrollSnap, .byColumn)
        XCTAssertEqual(MacBoardView.scrollSnap, BoardScrollSnap(multiColumn: true),
                       "the Mac shows several columns, so it takes iPad's several-columns rule")
    }

    /// The shared rule itself: several columns on screen → one column per swipe; one column
    /// filling the screen → a page, which is the same distance.
    func testSharedRulePicksColumnOrPage_ADEV315() {
        XCTAssertEqual(BoardScrollSnap(multiColumn: true), .byColumn)
        XCTAssertEqual(BoardScrollSnap(multiColumn: false), .page)
    }
}
#endif
