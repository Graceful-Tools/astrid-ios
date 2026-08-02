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
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: nil, currentUserId: me), .unassigned)
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "", currentUserId: me), .unassigned,
                       "an empty id is unassigned, not a user whose id is empty")
    }

    /// Mine keeps the checkbox — it is the one case where the leading control is also the thing
    /// you tap to finish the task.
    func testMineIsTheCheckbox() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: me, currentUserId: me), .checkbox)
    }

    /// Someone else keeps their photo.
    func testSomeoneElseIsTheirAvatar() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "u2", currentUserId: me), .avatar("u2"))
    }

    /// Signed out, an assigned task still shows that person rather than pretending it is yours.
    func testNoCurrentUserStillDistinguishesAssignedFromUnassigned() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: "u2", currentUserId: nil), .avatar("u2"))
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: nil, currentUserId: nil), .unassigned)
    }

    /// The three states are mutually exclusive — the whole point is that they stop looking alike.
    func testTheThreeStatesAreDistinct() {
        let mine = TaskLeadingControl.kind(assigneeId: me, currentUserId: me)
        let theirs = TaskLeadingControl.kind(assigneeId: "u2", currentUserId: me)
        let nobody = TaskLeadingControl.kind(assigneeId: nil, currentUserId: me)
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
