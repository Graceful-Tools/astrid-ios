//  MacDetailFullScreenTests.swift
//  Regression tests for Task 42013da7, item 3 — "Add ability on mac and Web to open the Task
//  details in a full screen mode".
//
//  The stated goal of the redesign is to see more of the description. The pop-out's ceiling is the
//  detail column's width, so consolidating rows alone cannot get past it — full screen is what
//  removes the ceiling.

import XCTest
@testable import Astrid_Mac

final class MacDetailFullScreenTests: XCTestCase {

    /// Both full-screen affordances (this one and the board's, a34d0163) must keep their own
    /// state. Sharing a key would mean expanding a board silently expanded task details too.
    func testDetailAndBoardFullScreenAreSeparateSettings() {
        let suite = UserDefaults(suiteName: "MacDetailFullScreenTests")!
        suite.removePersistentDomain(forName: "MacDetailFullScreenTests")

        suite.set(true, forKey: "macDetailFullScreen")
        XCTAssertTrue(suite.bool(forKey: "macDetailFullScreen"))
        XCTAssertFalse(suite.bool(forKey: "iPadBoardFullScreen"),
                       "expanding the detail must not expand the board")
    }

    /// Absent means off — a fresh install opens the pop-out, not a full-screen panel.
    func testDefaultsToThePopout() {
        let suite = UserDefaults(suiteName: "MacDetailFullScreenTests.fresh")!
        suite.removePersistentDomain(forName: "MacDetailFullScreenTests.fresh")
        XCTAssertFalse(suite.bool(forKey: "macDetailFullScreen"))
    }

    /// The control reuses the board's strings rather than inventing a second pair of words for
    /// the same idea — they are one affordance in two places.
    func testFullScreenCopyIsSharedWithTheBoardControl() {
        for key in ["board.full_screen", "board.exit_full_screen"] {
            let value = NSLocalizedString(key, comment: "")
            XCTAssertNotEqual(value, key, "\(key) does not resolve")
            XCTAssertFalse(value.isEmpty)
        }
    }

    // MARK: - AITD-464: closing a full-screen task returns to the pop-out

    /// "when closing a task in full screen revert back to non-full screen for future tasks
    /// opened" (AITD-464). The flag is persisted, and closing the detail only clears the
    /// selection — so without this every later task opened full screen as well.
    func testAITD464_closingTheDetailTurnsFullScreenOff() {
        XCTAssertFalse(MacDetailPresentation.fullScreen(current: true, selectionCount: 0),
                       "with nothing selected the detail is closed; full screen must not outlive it")
    }

    /// While a task is open its full-screen choice holds — the reset is for closing, not for
    /// every selection change.
    func testAITD464_fullScreenHoldsWhileATaskIsOpen() {
        XCTAssertTrue(MacDetailPresentation.fullScreen(current: true, selectionCount: 1))
        XCTAssertFalse(MacDetailPresentation.fullScreen(current: false, selectionCount: 1))
        XCTAssertFalse(MacDetailPresentation.fullScreen(current: false, selectionCount: 0))
    }
}
