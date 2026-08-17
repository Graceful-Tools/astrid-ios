//  TaskLeadingControlTests.swift
//  Regression tests for Task 42013da7 — "unassigned tasks should have a U on them rather than a
//  regular checkbox in the task row, task details, essentially everywhere".
//
//  The leading control answers WHO this task belongs to. It already had two answers — someone
//  else's photo, or a checkbox — and "unassigned" was quietly folded in with "mine", so a task
//  nobody owns looked exactly like a task you own.
//
//  One rule, so the row, the detail and quick add cannot disagree about the same task.

import XCTest
@testable import Astrid_App

final class TaskLeadingControlTests: XCTestCase {

    private let me = "me"

    /// THE BUG: nobody assigned is its own state and gets its own mark.
    func testUnassignedIsItsOwnControl() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: nil, currentUserId: me, displayMode: .list), .unassigned)
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "", currentUserId: me, displayMode: .list), .unassigned,
                       "an empty id is unassigned, not a user whose id is empty")
    }

    // MARK: - Project mode shows YOUR face too (task 132d7b3f)

    /// THE ASK. In project mode a task assigned to you shows your photo, exactly as someone
    /// else's shows theirs. The mode's own documentation has promised this since it was added.
    ///
    /// It costs nothing there: project mode's control opens the quick changer rather than
    /// completing, so it was never a checkbox in the "click to finish" sense. A board where
    /// every card you own is a bare checkbox and everyone else's is a face makes your own
    /// work the only thing you cannot pick out at a glance.
    func testProjectModeShowsYourOwnFace() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: me, currentUserId: me, displayMode: .project),
                       .avatar(me))
    }

    /// And list mode does not — there the checkbox is how you complete the task, so replacing
    /// it with a photo would take the completion gesture away.
    func testListModeKeepsYourOwnTaskAsTheCheckbox() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: me, currentUserId: me, displayMode: .list),
                       .checkbox)
    }

    /// The mode changes exactly ONE case. Unassigned and someone-else's must be identical in
    /// both, or the two layouts start disagreeing about who a task belongs to.
    func testTheModeChangesOnlyYourOwnTask() {
        for (assignee, label) in [(nil as String?, "unassigned"), ("u2", "someone else")] {
            XCTAssertEqual(TaskLeadingControl.kind(assigneeId: assignee, currentUserId: me, displayMode: .list),
                           TaskLeadingControl.kind(assigneeId: assignee, currentUserId: me, displayMode: .project),
                           "\(label) must look the same in both modes")
        }
    }

    /// Signed out, project mode has no "you" to show a face for — it must not invent one.
    func testProjectModeWithNoCurrentUserStillShowsTheAssignee() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "u2", currentUserId: nil, displayMode: .project),
                       .avatar("u2"))
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: nil, currentUserId: nil, displayMode: .project),
                       .unassigned)
    }

    /// Mine keeps the checkbox — it is the one case where the leading control is also the thing
    /// you tap to finish the task.
    func testMineIsTheCheckbox() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: me, currentUserId: me, displayMode: .list), .checkbox)
    }

    /// Someone else keeps their photo.
    func testSomeoneElseIsTheirAvatar() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "u2", currentUserId: me, displayMode: .list), .avatar("u2"))
    }

    /// Signed out, an assigned task still shows that person rather than pretending it is yours.
    func testNoCurrentUserStillDistinguishesAssignedFromUnassigned() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "u2", currentUserId: nil, displayMode: .list), .avatar("u2"))
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: nil, currentUserId: nil, displayMode: .list), .unassigned)
    }

    /// The three states are mutually exclusive — the whole point is that they stop looking alike.
    func testTheThreeStatesAreDistinct() {
        let mine = TaskLeadingControl.kind(assigneeId: me, currentUserId: me, displayMode: .list)
        let theirs = TaskLeadingControl.kind(assigneeId: "u2", currentUserId: me, displayMode: .list)
        let nobody = TaskLeadingControl.kind(assigneeId: nil, currentUserId: me, displayMode: .list)
        XCTAssertNotEqual(mine, theirs)
        XCTAssertNotEqual(mine, nobody)
        XCTAssertNotEqual(theirs, nobody)
    }

    /// The glyph is shared with the assignee picker, so the mark you pick is the mark you see.
    func testGlyphMatchesTheAssigneePicker() {
        XCTAssertEqual(TaskLeadingControl.unassignedGlyph, AssigneeResolver.unassignedGlyph)
        XCTAssertEqual(TaskLeadingControl.unassignedGlyph, "U")
    }
}
