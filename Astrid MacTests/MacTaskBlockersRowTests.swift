//  MacTaskBlockersRowTests.swift
//  Regression guard for AITD-430 — "[Mac] Waiting on: show the row in task details for tasks on
//  project boards". The rule itself (`TaskBlockers`) is shared with iOS and pinned by iOS's
//  TaskBlockersTests; these hold where the Mac puts the row.

import XCTest
@testable import Astrid_Mac

final class MacTaskBlockersRowTests: XCTestCase {

    private func rows(inProject: Bool) -> [MacTaskFieldRow] {
        MacTaskFields.rows(showsTitle: true, isInProject: inProject)
    }

    func testShownForATaskOnABoard() {
        XCTAssertTrue(rows(inProject: true).contains(.blockers))
    }

    func testHiddenForATaskNotOnABoard() {
        XCTAssertFalse(rows(inProject: false).contains(.blockers))
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true).contains(.blockers))
    }

    /// After Lists and the board-state row, before the description — exactly where iOS puts it.
    func testSitsAfterListsAndBoardStateAndBeforeTheDescription() throws {
        let ordered = rows(inProject: true)
        let lists = try XCTUnwrap(ordered.firstIndex(of: .lists))
        let state = try XCTUnwrap(ordered.firstIndex(of: .projectState))
        let blockers = try XCTUnwrap(ordered.firstIndex(of: .blockers))
        let description = try XCTUnwrap(ordered.firstIndex(of: .description))
        XCTAssertLessThan(lists, blockers)
        XCTAssertLessThan(state, blockers)
        XCTAssertLessThan(blockers, description)
    }

    func testItIsEditableLikeEveryOtherRow() {
        XCTAssertTrue(MacTaskFields.isEditable(.blockers))
    }
}
