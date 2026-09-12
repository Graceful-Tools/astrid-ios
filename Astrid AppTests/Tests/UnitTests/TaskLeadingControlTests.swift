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
            TaskLeadingControl.action(surface: .boardCard, kind: .checkbox, displayMode: .list, currentUserId: "me"),
            .openPicker,
            "A board card's checkbox must open the picker, not complete the task outright")
    }

    /// Every face is the same control. A card is a card whichever one it wears, in either mode.
    func testEveryFaceOnACardOpensThePicker() {
        for kind: TaskLeadingControl in [.checkbox, .unassigned, .avatar("someone-else")] {
            for mode in TaskDisplayMode.allCases {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: .boardCard, kind: kind, displayMode: mode, currentUserId: "me"),
                    .openPicker,
                    "\(kind) in \(mode) must open the picker on a board card")
            }
        }
    }

    // MARK: - "In List mode, not part of a board, tapping the checkbox should complete the task"

    func testListRowCheckboxCompletesInListMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, displayMode: .list, currentUserId: "me"),
            .complete,
            "In list mode a row's checkbox completes the task — that is what a checkbox means")
    }

    /// Project mode still turns the row's control into the quick changer, which is what task
    /// 132d7b3f asked for. This change narrows the board, not the row.
    func testListRowOpensTheQuickChangerInProjectMode() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox, displayMode: .project, currentUserId: "me"),
            .openPicker)
    }

    // MARK: - The detail screen is untouched (task 729a190e)

    func testDetailCompletesOnlyWhenTheFaceIsACheckbox() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .list, currentUserId: "me"),
            .complete)
        // Someone else's photo is not a checkbox and must never finish their task on a tap.
        // AITD-363 read that as "confirm on the tap"; AITD-375 settled it as the options
        // popover on every surface, with the confirmation on its Complete button — so the
        // detail screen stopped being the one place with a bespoke gesture.
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .avatar("someone-else"), displayMode: .list, currentUserId: "me"),
            .openPicker,
            "Someone else's photo offers the choices; completing from there asks first")
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox, displayMode: .project, currentUserId: "me"),
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
            for mode in TaskDisplayMode.allCases {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: surface, kind: theirs(),
                                              displayMode: mode, currentUserId: me),
                    .openPicker,
                    "\(surface) in \(mode) must offer the choices, never finish someone else's task on a tap")
            }
        }
    }

    /// The row is the case AITD-375 was filed for: it used to complete outright in list mode.
    func testAListRowNoLongerCompletesSomeoneElsesTaskOutright() {
        XCTAssertNotEqual(
            TaskLeadingControl.action(surface: .listRow, kind: theirs(),
                                      displayMode: .list, currentUserId: me),
            .complete,
            "a stray tap on a small photo in a dense list must not finish that person's work")
    }

    // MARK: - Your own task is untouched

    func testYourOwnCheckboxStillCompletesOnTap() {
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: .checkbox,
                                      displayMode: .list, currentUserId: me),
            .complete)
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .detail, kind: .checkbox,
                                      displayMode: .list, currentUserId: me),
            .complete)
    }

    /// In PROJECT mode your own task wears your photo too (task 132d7b3f). "Is it an avatar" and
    /// "is it theirs" are different questions, and conflating them would make you confirm your
    /// own completions.
    func testYourOwnAvatarInProjectModeIsNotSomeoneElses() {
        XCTAssertFalse(TaskLeadingControl.avatar(me).isSomeoneElses(currentUserId: me))
        XCTAssertTrue(TaskLeadingControl.avatar(them).isSomeoneElses(currentUserId: me))
        XCTAssertFalse(TaskLeadingControl.checkbox.isSomeoneElses(currentUserId: me))
        XCTAssertFalse(TaskLeadingControl.unassigned.isSomeoneElses(currentUserId: me))
    }

    /// An unknown current user cannot be shown to own anything, so the safe answer is "ask".
    func testAnUnknownViewerIsTreatedAsNotTheOwner() {
        XCTAssertTrue(TaskLeadingControl.avatar(them).isSomeoneElses(currentUserId: nil))
        XCTAssertEqual(
            TaskLeadingControl.action(surface: .listRow, kind: theirs(),
                                      displayMode: .list, currentUserId: nil),
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
        XCTAssertTrue(TaskLeadingControl.pickerShowsProjectState(displayMode: .list,
                                                                 surface: .detail,
                                                                 isSomeoneElses: true),
                      "when the popover is the only thing a tap gives you, it carries the full set")
    }

    /// List mode's omission still stands for your OWN task in the detail panel — there, priority
    /// and assignee are rows of their own and a board column is a project idea.
    func testYourOwnTaskInListModeDetailStillOmitsBoardState() {
        XCTAssertFalse(TaskLeadingControl.pickerShowsProjectState(displayMode: .list,
                                                                  surface: .detail,
                                                                  isSomeoneElses: false))
    }

    func testProjectModeAndBoardCardsAreUnchanged() {
        XCTAssertTrue(TaskLeadingControl.pickerShowsProjectState(displayMode: .project,
                                                                 surface: .detail,
                                                                 isSomeoneElses: false))
        XCTAssertTrue(TaskLeadingControl.pickerShowsProjectState(displayMode: .list,
                                                                 surface: .boardCard,
                                                                 isSomeoneElses: false))
    }

    // MARK: - The popover IS the confirmation (AITD-381)

    /// Jon, AITD-381: "Remove second confirm bubble when completing other users tasks."
    ///
    /// Someone else's task opens the popover on every surface — `action()` above returns
    /// `.openPicker` for it — so its Complete button can only ever be reached deliberately:
    /// open the popover, then press the one blue button in it. AITD-375 kept the AITD-363
    /// confirmation anyway and moved it onto that button, which put a second sheet asking the
    /// same question on top of an answer already given twice. The popover is the protection;
    /// the bubble behind it was spending a tap to repeat it.
    ///
    /// A source guard, because this is a fact about three view files and nothing a pure
    /// function can hold: the previous guard here asserted the OPPOSITE, and a guard is exactly
    /// what would put the bubble back on whichever platform was edited last.
    func testNoSurfacePresentsASecondConfirmationOverThePopover() throws {
        for path in Self.surfacesThatCompleteFromTheLeadingControl {
            let source = try Self.source(of: path)
            XCTAssertFalse(source.contains("tasks.confirm_complete_title"),
                           "\(path): the popover's Complete button completes (AITD-381) — "
                           + "a confirmation sheet on top of it is the second bubble")
            XCTAssertFalse(source.contains("confirmationDialog"),
                           "\(path): no confirmation sheet between the Complete button and "
                           + "completing the task (AITD-381)")
        }
    }

    /// The protection that REPLACED the bubble, asserted where the bubble's guard used to be:
    /// a tap on someone else's control opens the popover rather than completing outright, on
    /// every surface and in both modes. Removing the sheet is only safe while this holds.
    func testSomeoneElsesTaskStillNeverCompletesOnASingleTap() {
        for surface in [TaskLeadingControlSurface.listRow, .boardCard, .detail] {
            for mode in [TaskDisplayMode.list, .project] {
                XCTAssertEqual(
                    TaskLeadingControl.action(surface: surface, kind: theirs(),
                                              displayMode: mode, currentUserId: me),
                    .openPicker,
                    "\(surface)/\(mode): one tap must not finish another person's task")
            }
        }
    }

    /// The predicate outlived the confirmation it was named for: it now only decides whether the
    /// popover carries the board-state section. No screen may still read it as "ask first".
    ///
    /// The rule's own file is exempt — the old name belongs in its history, which is where a
    /// reader goes to find out why the sheet is gone.
    func testNoScreenStillReadsThePredicateAsAskFirst() throws {
        for path in Self.surfacesThatCompleteFromTheLeadingControl {
            XCTAssertFalse(try Self.source(of: path).contains("NeedsConfirmation"),
                           "\(path): renamed to isSomeoneElsesTask (AITD-381)")
        }
    }

    private static let surfacesThatCompleteFromTheLeadingControl = [
        "Astrid App/Views/Tasks/TaskDetailLeadingControl.swift",
        "Astrid App/Views/Components/TaskQuickChanger.swift",
        "Astrid Mac/Views/MacLeadingControlButton.swift",
    ]

    private static func source(of path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
