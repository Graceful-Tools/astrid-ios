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

    private func rows(_ mode: TaskDisplayMode, inProject: Bool) -> [MacTaskFieldRow] {
        MacTaskFields.rows(showsTitle: true, displayMode: mode, isInProject: inProject)
    }

    // MARK: - When the row appears

    func testTheDefaultIsNoStateRow() {
        // A call site that has not been taught about projects must not sprout the row by accident.
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true, displayMode: .list).contains(.projectState))
    }

    // MARK: - Where it appears

    func testTheStateRowSitsAfterListsAndBeforeTheDescription() {
        let ordered = rows(.list, inProject: true)

        guard let lists = ordered.firstIndex(of: .lists),
              let state = ordered.firstIndex(of: .projectState),
              let description = ordered.firstIndex(of: .description) else {
            return XCTFail("Expected lists, state and description rows, got \(ordered)")
        }
        XCTAssertLessThan(lists, state, "State belongs with where the task lives, not above it")
        XCTAssertLessThan(state, description)
    }

    func testTheSharedListModeOrderIsUntouched() {
        // The Who/Date/Priority/Lists order is a cross-platform contract (task c8a1ff51). The new
        // row is appended after it, never interleaved.
        let ordered = rows(.list, inProject: true)
            .filter { ![.title, .projectState, .blockers, .description].contains($0) }

        XCTAssertEqual(ordered, TaskDetailFieldOrder.listMode.map(MacTaskFieldRow.init))
    }

    func testAddingTheRowChangesNothingElseAboutListMode() {
        // `.blockers` is the other project-only row (AITD-430), pinned in MacTaskBlockersRowTests.
        let withState = rows(.list, inProject: true).filter { $0 != .projectState && $0 != .blockers }

        XCTAssertEqual(withState, rows(.list, inProject: false))
    }

    func testProjectModeShowsTheStateRowAfterLists_AITD555() {
        // "[mac] board status is not in task details should be." The project-mode detail left
        // state to the leading control's popover, so nothing on the pane said which column the
        // task was in.
        let ordered = rows(.project, inProject: true)

        guard let lists = ordered.firstIndex(of: .lists),
              let state = ordered.firstIndex(of: .projectState),
              let description = ordered.firstIndex(of: .description) else {
            return XCTFail("Expected lists, state and description rows, got \(ordered)")
        }
        XCTAssertLessThan(lists, state)
        XCTAssertLessThan(state, description)
    }

    func testProjectModeHasNoStateRowOffABoard_AITD555() {
        XCTAssertFalse(rows(.project, inProject: false).contains(.projectState))
    }

    func testTheBoardCardEditorDoesNotRepeatTheColumnItIsDrawnIn_AITD555() {
        // The inline card editor sits inside the column; a row naming that column says it twice.
        XCTAssertFalse(MacTaskFields.rows(showsTitle: false, displayMode: .project, isInProject: true)
            .contains(.projectState))
    }

    func testTheStateRowIsEditableLikeEveryOtherRow() {
        // The Lists row shipped read-only once; a field the user can see and not change is the bug.
        XCTAssertTrue(MacTaskFields.isEditable(.projectState))
    }
}
