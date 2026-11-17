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


    /// Your own task is the checkbox — it is how you complete it (ADEV-70 removed the Project
    /// layout, where it showed your photo).
    func testYourOwnTaskIsTheCheckbox() {
        XCTAssertEqual(TaskLeadingControl.kind(assigneeId: me, currentUserId: me),
                       .checkbox)
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
            TaskLeadingControl.action(surface: .boardCard, kind: .checkbox, currentUserId: "me"),
            .openPicker,
            "A board card's checkbox must open the picker, not complete the task outright")
    }

    /// Every face is the same control. A card is a card whichever one it wears, in either mode.
    func testEveryFaceOnACardOpensThePicker() {
        for kind: TaskLeadingControl in [.checkbox, .unassigned, .avatar("someone-else")] {
            do {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: .boardCard, kind: kind, currentUserId: "me"),
                    .openPicker,
                    "\(kind) must open the picker on a board card")
            }
        }
    }

    // MARK: - "In List mode, not part of a board, tapping the checkbox should complete the task"

    func testListRowCheckboxCompletesInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, currentUserId: "me"),
            .complete,
            "In list mode a row's checkbox completes the task — that is what a checkbox means")
    }


    // MARK: - The detail screen is untouched (task 729a190e)

    func testDetailCompletesOnlyWhenTheFaceIsACheckbox() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, currentUserId: "me"),
            .complete)
        // Someone else's photo is not a checkbox and must never finish their task on a tap.
        // AITD-363 read that as "confirm on the tap"; AITD-375 settled it as the options
        // popover on every surface, with the confirmation on its Complete button — so the
        // detail screen stopped being the one place with a bespoke gesture.
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .avatar("someone-else"), currentUserId: "me"),
            .openPicker,
            "Someone else's photo offers the choices; completing from there asks first")
    }

}

/// Someone else's task: the popover, everywhere — and a confirmation on Complete (AITD-375).
///
/// Jon: "when not yours, always confirm before completing ... on web and iOS it should give the
/// popover to show assignment, complete, priority and status options just like in project mode."
///
/// This settles two surfaces that had drifted apart and were BOTH wrong. A list ROW completed
/// another person's task outright on a tap — one stray touch on a small photo in a dense list.
/// Task DETAILS offered no way to complete it at all, then briefly (AITD-363) a bespoke
/// confirm-on-tap that existed nowhere else. Now both open the same popover, and the
/// confirmation lives on its Complete button.
final class TaskLeadingControlOthersTaskTests: XCTestCase {

    private let me = "me"
    private let them = "them"

    private func theirs() -> TaskLeadingControl { .avatar("them") }

    // MARK: - The popover, on every surface

    func testSomeoneElsesTaskOpensThePopoverOnEverySurface() {
        for surface in [TaskLeadingControlSurface.listRow, .detail, .boardCard] {
            do {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: surface, kind: theirs(), currentUserId: me),
                    .openPicker,
                    "\(surface) must offer the choices, never finish someone else's task on a tap")
            }
        }
    }

    /// The row is the case AITD-375 was filed for: it used to complete outright in list mode.
    func testAListRowNoLongerCompletesSomeoneElsesTaskOutright() {
        XCTAssertNotEqual(
            TaskLeadingControl.action(surface: .listRow, kind: theirs(), currentUserId: me),
            .complete,
            "a stray tap on a small photo in a dense list must not finish that person's work")
    }

    // MARK: - Your own task is untouched

    func testYourOwnCheckboxStillCompletesOnTap() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, currentUserId: me),
            .complete)
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, currentUserId: me),
            .complete)
    }

    /// "Is it an avatar" and "is it theirs" are different questions; the kind carries whose face
    /// it is.
    func testAnAvatarIsSomeoneElsesOnlyWhenTheIdIsNotYours() {
        XCTAssertFalse(TaskLeadingControl.avatar(me).isSomeoneElses(currentUserId: me))
        XCTAssertTrue(TaskLeadingControl.avatar(them).isSomeoneElses(currentUserId: me))
        XCTAssertFalse(TaskLeadingControl.checkbox.isSomeoneElses(currentUserId: me))
        XCTAssertFalse(TaskLeadingControl.unassigned.isSomeoneElses(currentUserId: me))
    }

    /// An unknown current user cannot be shown to own anything, so the safe answer is "ask".
    func testAnUnknownViewerIsTreatedAsNotTheOwner() {
        XCTAssertTrue(TaskLeadingControl.avatar(them).isSomeoneElses(currentUserId: nil))
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: theirs(), currentUserId: nil),
            .openPicker)
    }

    // MARK: - "Is this somebody else's?" — the raw-id question

    /// The predicate the popover asks about its own contents. It was
    /// `completionNeedsConfirmation` until AITD-381 removed the confirmation; the ANSWERS are
    /// unchanged, only what reads them.
    func testSomeoneElsesTaskIsRecognisedFromTheRawIds() {
        XCTAssertTrue(TaskLeadingControl.isSomeoneElsesTask(assigneeId: them, currentUserId: me))
    }

    func testYourOwnTaskIsNotSomeoneElses() {
        XCTAssertFalse(TaskLeadingControl.isSomeoneElsesTask(assigneeId: me, currentUserId: me))
    }

    /// Nobody is assigned, so there is nobody else whose task this could be.
    func testAnUnassignedTaskBelongsToNobodyElse() {
        XCTAssertFalse(TaskLeadingControl.isSomeoneElsesTask(assigneeId: nil, currentUserId: me))
        XCTAssertFalse(TaskLeadingControl.isSomeoneElsesTask(assigneeId: "", currentUserId: me),
                       "empty string is how the API says unassigned")
    }

    // MARK: - "...priority and status options just like in project mode"

    func testSomeoneElsesTaskGetsTheBoardStateSectionEvenInListMode() {
        XCTAssertTrue(TaskLeadingControl.pickerShowsProjectState(surface: .detail,
                                                                 assigneeId: them, currentUserId: me),
                      "when the popover is the only thing a tap gives you, it carries the full set")
    }

    /// List mode's omission still stands for your OWN task in the detail panel — there, priority
    /// and assignee are rows of their own and a board column is a project idea.
    func testYourOwnTaskInListModeDetailStillOmitsBoardState() {
        XCTAssertFalse(TaskLeadingControl.pickerShowsProjectState(surface: .detail,
                                                                  assigneeId: me, currentUserId: me))
    }

    func testBoardCardsAreUnchanged() {
        XCTAssertTrue(TaskLeadingControl.pickerShowsProjectState(surface: .boardCard,
                                                                 assigneeId: me, currentUserId: me))
    }

    // MARK: - The popover, then the confirmation (AITD-381, ADEV-70)

    /// The protection that REPLACED the bubble, asserted where the bubble's guard used to be:
    /// a tap on someone else's control opens the popover rather than completing outright, on
    /// every surface.
    func testSomeoneElsesTaskStillNeverCompletesOnASingleTap() {
        for surface in [TaskLeadingControlSurface.listRow, .boardCard, .detail] {
            do {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: surface, kind: theirs(), currentUserId: me),
                    .openPicker,
                    "\(surface): one tap must not finish another person's task")
            }
        }
    }

}

/// Regression tests for AITD-382 — "tapping on unassigned checkbox, agents, and tasks assigned
/// to others should all behave the same in iOS. Currently unassigned is wrong (it
/// completes/uncompletes) ... List view is where we see this bug".
///
/// Three kinds of task that are all "not yours to tick off in one tap", and only two of them
/// behaved that way. Someone else's task and an agent's task are both `.avatar(id)` with an id
/// that is not yours, so `action`'s opening `isSomeoneElses` guard sent them to the popover.
/// Nobody's task is `.unassigned` — deliberately NOT someone else's — so it fell past that guard
/// into the surface switch, where the list row completed it.
///
/// The row was also disagreeing with the detail screen about the very same task: `.detail` had
/// always required `kind == .checkbox` before completing, while `.listRow` asked only about the
/// display mode and never looked at the mark it was drawing. So an unassigned task opened the
/// popover on one screen and was finished outright on the other.
///
/// What makes the row's old answer indefensible rather than merely inconsistent: since task
/// 42013da7 an unassigned task does not draw a checkbox at all — it draws the "U" glyph, because
/// a task nobody owns was being depicted exactly like a task you own. Completing on a tap is what
/// a checkbox means. It is not what an unassigned mark means.
final class TaskLeadingControlUnassignedTapTests: XCTestCase {

    private let me = "me"

    // MARK: - The bug as reported: the list row

    func testUnassignedListRowOpensThePickerInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .unassigned, currentUserId: me),
            .openPicker,
            "AITD-382: nobody's task must offer the choices, not complete on one tap")
    }

    // MARK: - The property the task actually asks for

    /// "unassigned ... agents, and tasks assigned to others should all behave the same".
    ///
    /// Asserted as one loop rather than three separate expectations, because the thing being
    /// fixed is that they AGREE — three tests that happen to expect the same value would still
    /// pass if only two of them moved.
    func testUnassignedAgentsAndOtherPeopleAllBehaveTheSameOnAListRow() {
        let notYours: [(TaskLeadingControl, String)] = [
            (.unassigned, "nobody's"),
            (.avatar("ai-agent-claude"), "an agent's"),
            (.avatar("someone-else"), "another person's"),
        ]

        do {
            for (kind, label) in notYours {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: .listRow, kind: kind, currentUserId: me),
                    .openPicker,
                    "AITD-382: \(label) task must open the picker from a list row")
            }
        }
    }

    /// The same three, on the screen that was already right — so the fix to the row is checked
    /// against the answer it is being brought into line with, not just against itself.
    func testTheDetailScreenGivesTheSameAnswerForAllThree() {
        for kind: TaskLeadingControl in [.unassigned, .avatar("ai-agent-claude"), .avatar("someone-else")] {
            XCTAssertEqual(
                TaskLeadingControl.action(surface: .detail, kind: kind, currentUserId: me),
                TaskLeadingControl.action(surface: .listRow, kind: kind, currentUserId: me),
                "AITD-382: \(kind) must mean the same thing on a row as in task details")
        }
    }

    // MARK: - What must NOT change

    /// The narrow fix, pinned. A checkbox is still a checkbox: this task is about the marks that
    /// are not one, and a fix that also stopped your own tasks completing would take the
    /// list's whole point with it.
    func testYourOwnCheckboxStillCompletesOnAListRow() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, currentUserId: me),
            .complete,
            "AITD-382 must not disturb the one tap that is supposed to finish a task")
    }

    /// `.unassigned` is still not "someone else's" — the predicate keeps its meaning, and the
    /// fix does not smuggle nobody's task into the avatar case to get the answer it wanted.
    func testNobodysTaskIsStillNotSomebodyElses() {
        XCTAssertFalse(TaskLeadingControl.unassigned.isSomeoneElses(currentUserId: me))
        XCTAssertFalse(TaskLeadingControl.isSomeoneElsesTask(assigneeId: nil, currentUserId: me))
    }
}
