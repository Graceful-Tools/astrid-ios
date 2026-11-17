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

    private func isVisible(inProject: Bool, readOnly: Bool = false) -> Bool {
        TaskDetailProjectStateRow.isVisible(isInProject: inProject, isReadOnly: readOnly)
    }

    // MARK: - When the row appears

    func testShowsTheStateRowForATaskInAProject() {
        XCTAssertTrue(isVisible(inProject: true))
    }

    func testHasNoStateRowForATaskWithNoBoardColumn() {
        XCTAssertFalse(isVisible(inProject: false))
    }

    func testTheReadOnlyViewHasNoStateRow() {
        // The row is a MOVER, not a label — its chips write. It follows Who and Priority, which
        // are hidden rather than shown as controls a public-list viewer cannot use.
        XCTAssertFalse(isVisible(inProject: true, readOnly: true))
    }

    // MARK: - The rule is one rule

    func testEveryStateAgreesWithTheConjunction() {
        // Stated as the conjunction it is, so a later "just one more condition" at a call site
        // shows up here as a failure rather than as a platform that quietly differs.
        for inProject in [true, false] {
            for readOnly in [true, false] {
                XCTAssertEqual(isVisible(inProject: inProject, readOnly: readOnly),
                               inProject && !readOnly,
                               "inProject: \(inProject), readOnly: \(readOnly)")
            }
        }
    }
}
