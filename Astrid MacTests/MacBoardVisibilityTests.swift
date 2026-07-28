//  MacBoardVisibilityTests.swift
//  Regression tests for Task 8b71bc24 — "[mac] hide the board option unless project boards are
//  enabled for the user/list".
//
//  iOS skips the board step in its view rotator when the list has no projectId. The Mac's
//  segmented picker always offered it, so choosing board landed you on an empty pane.

import XCTest
@testable import Astrid_Mac

final class MacBoardVisibilityTests: XCTestCase {

    func testPickerOffersBoardOnlyForAListThatHasOne() {
        XCTAssertTrue(MacViewMode.offersBoard(projectId: "proj_1", isRealList: true))
        XCTAssertFalse(MacViewMode.offersBoard(projectId: nil, isRealList: true))
        XCTAssertFalse(MacViewMode.offersBoard(projectId: "", isRealList: true),
                       "An empty projectId is not a board")
    }

    /// My Tasks and Search are not lists and can never have a board.
    func testVirtualSelectionsNeverOfferBoard() {
        XCTAssertFalse(MacViewMode.offersBoard(projectId: "proj_1", isRealList: false))
    }

    /// Switching to a list without a board while the board is showing must fall back, or the
    /// picker hides the option while the pane still shows a board.
    func testBoardModeFallsBackWhenTheListHasNoBoard() {
        XCTAssertEqual(MacViewMode.resolve(requested: .board, isRealList: true, projectId: nil), .list)
        XCTAssertEqual(MacViewMode.resolve(requested: .board, isRealList: true, projectId: "p"), .board)
    }

    /// ⌘2 on a list without a board behaves the same way — one rule for both paths.
    func testKeyboardShortcutFollowsTheSameRule() {
        XCTAssertEqual(MacViewMode.resolve(requested: .board, isRealList: false, projectId: "p"), .list)
        XCTAssertEqual(MacViewMode.resolve(requested: .chat, isRealList: true, projectId: nil), .chat,
                       "Chat does not depend on a board")
    }

    /// Enabling a board stays reachable from the sidebar once the board pane is hidden.
    func testEnableIsOfferedForAListWithoutABoard() {
        XCTAssertTrue(MacViewMode.offersEnableBoard(projectId: nil))
        XCTAssertFalse(MacViewMode.offersEnableBoard(projectId: "p"))
    }
}
