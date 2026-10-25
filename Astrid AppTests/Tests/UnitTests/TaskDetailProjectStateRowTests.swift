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

    func testProjectModeShowsTheStateRowToo_AITD555() {
        // "[mac] board status is not in task details should be." Project mode used to leave state
        // to the leading control's quick changer (task 729a190e) — but that popover is a MOVER you
        // have to open, and the control itself depicts who and priority, never the column. So the
        // detail never said where the task was, in the mode built for boards.
        XCTAssertTrue(isVisible(.project, inProject: true))
    }

    func testProjectModeStillHasNoStateRowOffABoard_AITD555() {
        XCTAssertFalse(isVisible(.project, inProject: false))
    }

    func testTheReadOnlyViewHasNoStateRow() {
        // The row is a MOVER, not a label — its chips write. It follows Who and Priority, which
        // are hidden rather than shown as controls a public-list viewer cannot use.
        XCTAssertFalse(isVisible(.list, inProject: true, readOnly: true))
    }

    // MARK: - The rule is one rule

    func testEveryModeAndStateAgreesWithTheConjunction() {
        // Stated as the conjunction it is, so a later "just one more condition" at a call site
        // shows up here as a failure rather than as a platform that quietly differs. The display
        // mode is not part of it since AITD-555: a task on a board shows its column in both.
        for mode in TaskDisplayMode.allCases {
            for inProject in [true, false] {
                for readOnly in [true, false] {
                    XCTAssertEqual(isVisible(mode, inProject: inProject, readOnly: readOnly),
                                   inProject && !readOnly,
                                   "mode: \(mode), inProject: \(inProject), readOnly: \(readOnly)")
                }
            }
        }
    }
}
