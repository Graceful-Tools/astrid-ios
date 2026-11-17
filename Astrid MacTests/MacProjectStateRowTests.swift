//  MacProjectStateRowTests.swift
//  Regression guard for AITD-327 — "[mac] when task is part of a project AND task details view is
//  [list] add a row for 'task state' in the task details."
//
//  This NARROWS an older rule rather than reversing it. `MacLeadingPicker` reasoned that "a board
//  column is a project idea, and a row for it in the list layout rebuilds the hybrid" that the
//  display-mode setting exists to end — sound for a task with no board column, where a row for a
//  state it cannot have IS the hybrid. For a task that is on a board, its column is real
//  information the list layout was hiding, and switching display modes was the only way to reach
//  it. The `isInProject` condition is the whole difference, so it is what these tests hold.

import XCTest
@testable import Astrid_Mac

final class MacProjectStateRowTests: XCTestCase {

    private func rows(inProject: Bool) -> [MacTaskFieldRow] {
        MacTaskFields.rows(showsTitle: true, isInProject: inProject)
    }

    // MARK: - When the row appears

    func testTheDefaultIsNoStateRow() {
        // A call site that has not been taught about projects must not sprout the row by accident.
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true).contains(.projectState))
    }

    // MARK: - Where it appears

    func testTheStateRowSitsAfterListsAndBeforeTheDescription() {
        let ordered = rows(inProject: true)

        guard let lists = ordered.firstIndex(of: .lists),
              let state = ordered.firstIndex(of: .projectState),
              let description = ordered.firstIndex(of: .description) else {
            return XCTFail("Expected lists, state and description rows, got \(ordered)")
        }
        XCTAssertLessThan(lists, state, "State belongs with where the task lives, not above it")
        XCTAssertLessThan(state, description)
    }

    func testTheSharedOrderIsUntouched() {
        // The Who/Date/Priority/Lists order is a cross-platform contract (task c8a1ff51). The new
        // row is appended after it, never interleaved.
        let ordered = rows(inProject: true)
            .filter { ![.title, .projectState, .blockers, .description].contains($0) }

        XCTAssertEqual(ordered, TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init))
    }

    func testAddingTheRowChangesNothingElse() {
        // `.blockers` is the other project-only row (AITD-430), pinned in MacTaskBlockersRowTests.
        let withState = rows(inProject: true).filter { $0 != .projectState && $0 != .blockers }

        XCTAssertEqual(withState, rows(inProject: false))
    }




    func testTheStateRowIsEditableLikeEveryOtherRow() {
        // The Lists row shipped read-only once; a field the user can see and not change is the bug.
        XCTAssertTrue(MacTaskFields.isEditable(.projectState))
    }
}
