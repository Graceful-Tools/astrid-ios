//  TaskDetailProjectStateRowTests.swift
//  Regression guard for AITD-332 — "[ios] add project state to task details when in lists with
//  projects AND on List view (appearance setting)."
//
//  The iOS half of AITD-327. The rule the Mac shipped is the rule the phone needs, so it is now
//  asked of one shared place rather than spelled in each view: two platforms deciding the same
//  layout question for themselves is how Priority-before-Who happened on both at once
//  (task c8a1ff51). These tests hold the rule; `MacProjectStateRowTests` holds the Mac's use of
//  it, and between them a change on either platform cannot quietly diverge from the other.

import XCTest
@testable import Astrid_App

final class TaskDetailProjectStateRowTests: XCTestCase {

    private func isVisible(_ mode: TaskDisplayMode,
                           inProject: Bool,
                           readOnly: Bool = false) -> Bool {
        TaskDetailProjectStateRow.isVisible(displayMode: mode,
                                            isInProject: inProject,
                                            isReadOnly: readOnly)
    }

    // MARK: - When the row appears

    func testListModeShowsTheStateRowForATaskInAProject() {
        XCTAssertTrue(isVisible(.list, inProject: true))
    }

    func testListModeHasNoStateRowForATaskWithNoBoardColumn() {
        // A row for a state the task cannot have IS the hybrid layout the setting exists to end.
        XCTAssertFalse(isVisible(.list, inProject: false))
    }

    func testProjectModeStillHasNoStateRow() {
        // Board state already lives in the leading control's quick changer there (task 729a190e);
        // a row would say it twice, and the compact detail is compact on purpose.
        XCTAssertFalse(isVisible(.project, inProject: true))
    }

    func testTheReadOnlyViewHasNoStateRow() {
        // The row is a MOVER, not a label — its chips write. It follows Who and Priority, which
        // are hidden rather than shown as controls a public-list viewer cannot use.
        XCTAssertFalse(isVisible(.list, inProject: true, readOnly: true))
    }

    // MARK: - The rule is one rule

    func testEveryModeAndStateAgreesWithTheConjunction() {
        // Stated as the conjunction it is, so a later "just one more condition" at a call site
        // shows up here as a failure rather than as a platform that quietly differs.
        for mode in TaskDisplayMode.allCases {
            for inProject in [true, false] {
                for readOnly in [true, false] {
                    let expected = mode.showsSeparateAssigneeAndPriorityRows && inProject && !readOnly
                    XCTAssertEqual(isVisible(mode, inProject: inProject, readOnly: readOnly),
                                   expected,
                                   "mode: \(mode), inProject: \(inProject), readOnly: \(readOnly)")
                }
            }
        }
    }

    func testTheRowTracksTheOtherListModeRowsRatherThanTheModeName() {
        // It appears exactly where Who and Priority appear. Asked of the named question, not of
        // `== .list`, so a third display mode arrives at all three rows together or at none.
        for mode in TaskDisplayMode.allCases {
            XCTAssertEqual(isVisible(mode, inProject: true),
                           mode.showsSeparateAssigneeAndPriorityRows)
        }
    }
}
