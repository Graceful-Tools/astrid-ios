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
        // Someone else's photo is not a checkbox, and it still must not finish their task on a
        // tap — but "must not complete" turned out to mean "must not complete SILENTLY", not
        // "must do nothing". Details is the only completion affordance a task has, so inertness
        // there left the task uncompletable from its own screen; it asks first instead (AITD-363).
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .avatar("someone-else"), displayMode: .list),
            .confirmCompletion,
            "Someone else's photo must ask before completing — never complete on the tap alone")
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

/// "Complete someone else's task from task details in list mode" (AITD-363).
///
/// The mark for someone else's task is their photo, and on a ROW that photo deliberately
/// carries no completion — finishing another person's work with a stray tap on their face is
/// not an affordance anyone asked for (task 2bb1b196). In TASK DETAILS the leading control is
/// the ONLY completion affordance, so the same rule left the task uncompletable from its own
/// detail view — on web outright, and here by routing the tap into a popover whose other two
/// sections are already rows of their own in list mode.
///
/// Details therefore CONFIRM rather than complete. The row's objection is still real; the
/// confirmation is what lets details offer the action without becoming that hazard.
///
/// Mirrors `astrid-web`'s `leadingControlConfirmsCompletion({ kind, opensOptions, surface })`,
/// where `opensOptions` wins — which here is `checkboxCompletesTask` being false.
final class TaskLeadingControlConfirmationTests: XCTestCase {

    // MARK: - The bug

    func testDetailAsksToConfirmBeforeCompletingSomeoneElsesTask() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail,
                                      kind: .avatar("someone-else"),
                                      displayMode: .list),
            .confirmCompletion,
            "In list mode, task details must offer to complete someone else's task — behind a confirmation")
    }

    // MARK: - It YIELDS to the options sheet

    /// Project mode already routes the tap to the quick changer, which carries complete/reopen
    /// itself. Two popovers competing for one tap is a new bug, not a fix.
    func testProjectModeKeepsTheOptionsSheetAndNeverConfirms() {
        for kind: TaskLeadingControl in [.checkbox, .unassigned, .avatar("someone-else")] {
            XCTAssertEqual(
                TaskLeadingControl.action(surface: .detail, kind: kind, displayMode: .project),
                .openPicker,
                "\(kind) in project mode must still open the options sheet")
        }
    }

    /// A board card opens the status picker in both modes (task f9d7ed42). The confirmation is
    /// a DETAIL affordance and must not leak onto the board.
    func testNoSurfaceButDetailEverConfirms() {
        for surface: TaskLeadingControlSurface in [.boardCard, .listRow] {
            for kind: TaskLeadingControl in [.checkbox, .unassigned, .avatar("someone-else")] {
                for mode in TaskDisplayMode.allCases {
                    XCTAssertNotEqual(
                        TaskLeadingControl.action(surface: surface, kind: kind, displayMode: mode),
                        .confirmCompletion,
                        "\(kind) on \(surface) in \(mode) must not raise a completion confirmation")
                }
            }
        }
    }

    // MARK: - What the confirmation must NOT change

    /// Your own task is the checkbox, and a checkbox completes on tap. Making people confirm
    /// their own completions would be a tax on the most common gesture in the app.
    func testYourOwnTaskStillCompletesWithoutConfirming() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .list),
            .complete)
    }

    /// The row is untouched by this task: someone else's avatar in a list row keeps whatever it
    /// did before, decided by the mode alone.
    func testTheListRowIsUnchanged() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .avatar("someone-else"), displayMode: .list),
            .complete)
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .avatar("someone-else"), displayMode: .project),
            .openPicker)
    }

    // MARK: - The call sites must actually ASK

    /// The rule is only as good as its call sites. Both detail surfaces — the phone's
    /// `TaskDetailLeadingControl` and the Mac's `MacLeadingControlButton` — used to decide with a
    /// comparison against ONE action, so a new third action they never mention would be a rule
    /// that changed with nothing changing on screen. Same guard, and same reason, as
    /// `testTheBoardCardDeclaresItsSurface`.
    func testBothDetailSurfacesHandleTheConfirmation() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
        for path in ["Astrid App/Views/Tasks/TaskDetailLeadingControl.swift",
                     "Astrid Mac/Views/MacLeadingControlButton.swift"] {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            XCTAssertTrue(source.contains(".confirmCompletion"),
                          "\(path) must branch on .confirmCompletion, or the shared rule says confirm and the screen does not")
        }
    }

    /// The confirmation names the assignee. A dialog asking about "this task" over an unlabelled
    /// photo is the blind confirm that teaches people to accept without reading.
    func testTheConfirmationCopyIsRegisteredInEveryLanguage() throws {
        let localizations = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Resources/Localizations")
        let languages = try FileManager.default
            .contentsOfDirectory(atPath: localizations.path)
            .filter { $0.hasSuffix(".lproj") }
        XCTAssertFalse(languages.isEmpty, "no .lproj directories found")
        for language in languages {
            let strings = try String(
                contentsOf: localizations.appendingPathComponent(language)
                    .appendingPathComponent("Localizable.strings"), encoding: .utf8)
            for key in ["tasks.confirm_complete_title", "tasks.confirm_complete_assigned"] {
                XCTAssertTrue(strings.contains("\"\(key)\""), "\(language) is missing \(key)")
            }
        }
    }
}
