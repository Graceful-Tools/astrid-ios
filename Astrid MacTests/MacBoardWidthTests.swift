//  MacBoardWidthTests.swift
//  Regression guard for AITD-330 — "[mac] allow the board columns to fill the width when space is
//  available with current width as the minimum. add ability to show messages when there is a very
//  wide board view with a minimum message width."
//
//  Two halves, and they meet in the middle: the columns fill the room they have, and the chat
//  column is allowed to take some of that room back — but only while what is left still fits the
//  columns at their floor. Neither half can be checked without the other, so they live together.

import XCTest
@testable import Astrid_Mac

final class MacBoardWidthTests: XCTestCase {

    /// Room for `count` columns at their floor, and not a point more.
    private func exactlyEnough(for count: Int) -> CGFloat {
        MacLayout.boardMinimumWidth(columnCount: count)
    }

    // MARK: - The columns fill the width

    func testColumnsShareTheRoomWhenThereIsMoreThanTheyNeed() {
        let width = exactlyEnough(for: 3) + 600

        let each = MacLayout.boardColumnWidth(columnCount: 3, availableWidth: width)

        XCTAssertGreaterThan(each, MacLayout.boardColumnMinWidth,
                             "Three columns in a wide window used to leave half the board empty")
    }

    func testTheColumnsExactlyFillTheSpaceTheyAreGiven() {
        let width: CGFloat = 1_800
        let count = 4

        let each = MacLayout.boardColumnWidth(columnCount: count, availableWidth: width)
        let used = each * CGFloat(count)
            + MacLayout.boardColumnSpacing * CGFloat(count - 1)
            + MacLayout.boardPadding * 2

        XCTAssertEqual(used, width, accuracy: 0.001,
                       "Left over width is a gutter; overshoot clips the last column")
    }

    func testTheShippedWidthIsTheFloorAndTheBoardScrollsBelowIt() {
        let cramped = exactlyEnough(for: 5) - 400

        XCTAssertEqual(MacLayout.boardColumnWidth(columnCount: 5, availableWidth: cramped),
                       MacLayout.boardColumnMinWidth,
                       "Below the floor the board scrolls horizontally, as it always did")
    }

    func testAtExactlyTheMinimumTheColumnsAreAtTheirFloor() {
        for count in 1...6 {
            XCTAssertEqual(
                MacLayout.boardColumnWidth(columnCount: count, availableWidth: exactlyEnough(for: count)),
                MacLayout.boardColumnMinWidth, accuracy: 0.001,
                "\(count) columns")
        }
    }

    func testTheFloorIsTheWidthTheBoardShippedAt() {
        XCTAssertEqual(MacLayout.boardColumnMinWidth, 250)
    }

    func testAnEmptyBoardDoesNotDivideByZero() {
        XCTAssertEqual(MacLayout.boardColumnWidth(columnCount: 0, availableWidth: 1_200),
                       MacLayout.boardColumnMinWidth)
        XCTAssertEqual(MacLayout.boardMinimumWidth(columnCount: 0), 0)
    }

    func testAWidthOfZeroBeforeTheFirstLayoutFallsBackToTheFloor() {
        // `boardWidth` is @State starting at 0; the first body evaluation must not produce a
        // negative or zero-width column.
        XCTAssertEqual(MacLayout.boardColumnWidth(columnCount: 3, availableWidth: 0),
                       MacLayout.boardColumnMinWidth)
    }

    // MARK: - Messages beside a very wide board

    private func showsChat(boardColumns: Int, contentWidth: CGFloat, windowWidth: CGFloat = 2_400) -> Bool {
        MacLayout.showsChatColumn(windowWidth: windowWidth, isRealList: true, isBoard: true,
                                  boardColumnCount: boardColumns, contentWidth: contentWidth)
    }

    func testAVeryWideBoardShowsTheMessagesColumn() {
        // The old rule refused outright: "a board needs the full horizontal width for its columns,
        // so the two are mutually exclusive" (task f1430338). True of the window it was written
        // for; false of one this wide.
        XCTAssertTrue(showsChat(boardColumns: 3,
                                contentWidth: exactlyEnough(for: 3) + MacLayout.chatColumnMinWidth + 200))
    }

    func testABoardKeepsItsColumnsWhenThereIsNotRoomForBoth() {
        XCTAssertFalse(showsChat(boardColumns: 3, contentWidth: exactlyEnough(for: 3) + 40),
                       "The board is what the user chose to look at — the columns win")
    }

    func testTheThresholdIsExactlyBothAtTheirMinimums() {
        let count = 4
        let needed = exactlyEnough(for: count) + MacLayout.chatColumnMinWidth + MacLayout.columnDividerWidth

        XCTAssertTrue(showsChat(boardColumns: count, contentWidth: needed))
        XCTAssertFalse(showsChat(boardColumns: count, contentWidth: needed - 1))
    }

    func testMoreColumnsNeedMoreRoomBeforeMessagesAppear() {
        let width = exactlyEnough(for: 3) + MacLayout.chatColumnMinWidth + MacLayout.columnDividerWidth

        XCTAssertTrue(showsChat(boardColumns: 3, contentWidth: width))
        XCTAssertFalse(showsChat(boardColumns: 6, contentWidth: width))
    }

    func testTheMessagesColumnStillNeedsAWideWindow() {
        // The window threshold is web parity and is unchanged; a huge content area in a small
        // window is not a case, but the guard must stay first.
        XCTAssertFalse(showsChat(boardColumns: 3, contentWidth: 4_000,
                                 windowWidth: MacLayout.chatColumnWindowThreshold - 1))
    }

    func testABoardWithNoChannelStillShowsNoMessages() {
        XCTAssertFalse(MacLayout.showsChatColumn(windowWidth: 2_400, isRealList: false, isBoard: true,
                                                 boardColumnCount: 3, contentWidth: 4_000))
    }

    // MARK: - Nothing changed off a board

    func testAListIsUnaffectedByTheBoardMeasurement() {
        XCTAssertTrue(MacLayout.showsChatColumn(windowWidth: 1_200, isRealList: true))
        XCTAssertFalse(MacLayout.showsChatColumn(windowWidth: 900, isRealList: true))
    }

    func testAListNeverConsultsTheBoardColumnCount() {
        // contentWidth and boardColumnCount default to 0; a list must not be refused chat because
        // a zero-column board would not fit.
        XCTAssertTrue(MacLayout.showsChatColumn(windowWidth: 1_200, isRealList: true,
                                                isBoard: false, boardColumnCount: 0, contentWidth: 0))
    }
}
