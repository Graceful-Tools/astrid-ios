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

/// Task f9d7ed42 — "In List mode, not part of a board, tapping the checkbox should complete the
/// task. In board view, it should bring up a 'status' picker".
///
/// The rule asked ONE question — which Appearance mode is this? — and a mode cannot tell a
/// board card from a list row. So `list` mode, whose whole point is that the checkbox finishes
/// the task, handed that behaviour to board cards as well: on the board, the click that reads
/// as "pick this one" completed the task, with no way back but finding it in the Done column.
/// That is the trapdoor task 9be8cb1b removed from the board, back again by way of a setting.
///
/// iOS is in scope even though the report was filed against the Mac: the iOS board card IS
/// `TaskRowView` in card chrome, so it asked the same single question and had the same hole.
final class TaskLeadingControlSurfaceTests: XCTestCase {

    // MARK: - "In board view, it should bring up a 'status' picker"

    func testBoardCardOpensThePickerInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .boardCard, kind: .checkbox, displayMode: .list),
            .openPicker,
            "A board card's checkbox must open the picker, not complete the task outright")
    }

    /// Every face is the same control. A card is a card whichever one it wears, in either mode.
    func testEveryFaceOnACardOpensThePicker() {
        for kind: TaskLeadingControl in [.checkbox, .unassigned, .avatar("someone-else")] {
            for mode in TaskDisplayMode.allCases {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: .boardCard, kind: kind, displayMode: mode),
                    .openPicker,
                    "\(kind) in \(mode) must open the picker on a board card")
            }
        }
    }

    // MARK: - "In List mode, not part of a board, tapping the checkbox should complete the task"

    func testListRowCheckboxCompletesInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, displayMode: .list),
            .complete,
            "In list mode a row's checkbox completes the task — that is what a checkbox means")
    }

    /// Project mode still turns the row's control into the quick changer, which is what task
    /// 132d7b3f asked for. This change narrows the board, not the row.
    func testListRowOpensTheQuickChangerInProjectMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, displayMode: .project),
            .openPicker)
    }

    // MARK: - The detail screen is untouched (task 729a190e)

    func testDetailCompletesOnlyWhenTheFaceIsACheckbox() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .list),
            .complete)
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .avatar("someone-else"), displayMode: .list),
            .openPicker,
            "Someone else's photo is not a checkbox — tapping it must not finish their task")
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .project),
            .openPicker)
    }

    // MARK: - The board card must actually ASK for the board surface

    /// The rule is only as good as the call site. `TaskRowView` draws both the list row and the
    /// board card, so if the card stops declaring itself a card it silently inherits the row's
    /// answer again — which is the whole bug.
    func testTheBoardCardDeclaresItsSurface() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid App/Views/Board/BoardTaskCardView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("surface: .boardCard"),
                      "The board card must tell TaskRowView it is a card, or it behaves like a row")
    }
}
