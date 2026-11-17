//  CompletionConfirmationTests.swift
//  Regression tests for ADEV-70 — "confirm before completing a task that isn't yours", matching
//  web's `completionNeedsConfirmation` (astrid-web ADEV-56, lib/task-leading-control.ts).
//
//  Jon: "show confirmation before completing a task that isn't [assigned to me] (including
//  unassigned)." The question is "is it mine?", not "is it theirs?".

import XCTest
@testable import Astrid_App

final class CompletionConfirmationTests: XCTestCase {

    private let me = "me"

    private func asks(_ assigneeId: String?, viewer: String? = "me", completed: Bool = false) -> Bool {
        TaskLeadingControl.completionNeedsConfirmation(assigneeId: assigneeId, currentUserId: viewer,
                                                       completed: completed)
    }

    func testYourOwnTaskCompletesWithoutAsking() {
        XCTAssertFalse(asks(me))
    }

    func testSomeoneElsesTaskAsks() {
        XCTAssertTrue(asks("them"))
    }

    /// THE WIDENING (ADEV-70): nobody's task asks too. `nil` and `""` both mean unassigned.
    func testAnUnassignedTaskAsks() {
        XCTAssertTrue(asks(nil))
        XCTAssertTrue(asks(""))
    }

    /// The mark and the popover still call nobody's task nobody ELSE's — only completion asks.
    func testUnassignedIsStillNotSomeoneElsesForTheMark() {
        XCTAssertFalse(TaskLeadingControl.isSomeoneElsesTask(assigneeId: nil, currentUserId: me))
        XCTAssertTrue(asks(nil))
    }

    func testAnUnknownViewerAsks() {
        XCTAssertTrue(asks(me, viewer: nil))
        XCTAssertTrue(asks(me, viewer: ""))
    }

    func testReopeningNeverAsks() {
        XCTAssertFalse(asks("them", completed: true))
        XCTAssertFalse(asks(nil, completed: true))
        XCTAssertFalse(asks(nil, viewer: nil, completed: true))
    }

    // MARK: - What the question says

    func testTheMessageNamesTheAssignee() {
        let message = CompletionConfirmation.message(assigneeLabel: "Ada")
        XCTAssertTrue(message.contains("Ada"), message)
    }

    func testTheMessageSaysNobodyHoldsAnUnassignedTask() {
        XCTAssertEqual(CompletionConfirmation.message(assigneeLabel: nil),
                       NSLocalizedString("tasks.confirm_complete_unassigned", comment: ""))
    }

    func testTheLabelIsNilOnlyWhenUnassigned() {
        XCTAssertNil(CompletionConfirmation.assigneeLabel(assigneeId: nil, assignee: nil))
        XCTAssertNil(CompletionConfirmation.assigneeLabel(assigneeId: "", assignee: nil))
        // Assigned to someone whose name has not loaded is still assigned.
        XCTAssertEqual(CompletionConfirmation.assigneeLabel(assigneeId: "them", assignee: nil), "")
    }

    /// Every popover's Complete button asks this rule; a popover that completes without it is
    /// how the confirmation existed on one surface and nowhere else.
    func testEveryCompleteButtonAsksTheRule() throws {
        for path in [
            "Astrid App/Views/Tasks/TaskDetailLeadingControl.swift",
            "Astrid App/Views/Components/TaskQuickChanger.swift",
            "Astrid Mac/Views/MacLeadingControlButton.swift",
            "Astrid Mac/Views/MacQuickChanger.swift",
            "Astrid Mac/App/MacAppModel.swift",
        ] {
            let source = try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path),
                                    encoding: .utf8)
            XCTAssertTrue(source.contains("completionNeedsConfirmation"),
                          "\(path): completing must ask `completionNeedsConfirmation` (ADEV-70)")
        }
    }
}

/// ADEV-79: Jon — "Now there is 3 steps: tap on checkbox, tap on complete, confirm. One too
/// many." A popover for a task that is not yours opens on the question itself, so it is the
/// checkbox, then Complete. No popover keeps a "has Complete been tapped yet" state to reveal it.
final class CompletionConfirmationStepsTests: XCTestCase {
    func testThePopoverOpensOnTheQuestion_ADEV79() throws {
        for path in [
            "Astrid App/Views/Tasks/TaskDetailLeadingControl.swift",
            "Astrid App/Views/Components/TaskQuickChanger.swift",
            "Astrid Mac/Views/MacLeadingControlButton.swift",
            "Astrid Mac/Views/MacQuickChanger.swift",
        ] {
            let source = try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path),
                                    encoding: .utf8)
            XCTAssertFalse(source.contains("confirmingCompletion"),
                           "\(path): no middle step before the question (ADEV-79)")
            XCTAssertTrue(source.contains("CompletionConfirmationPrompt("), path)
            XCTAssertTrue(source.contains("completionNeedsConfirmation"), path)
        }
    }
}

/// ADEV-70: the Project task layout is gone, so settings writes stop carrying `taskDisplayMode`.
/// The server keeps the column for older builds; this build neither reads nor echoes it.
final class TaskLayoutSettingRemovedTests: XCTestCase {

    func testSettingsWritesNoLongerCarryTheLayout() throws {
        let data = try JSONEncoder().encode(UserSettings())
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("taskDisplayMode"), json)
    }

    /// A server row that still says "project" decodes, and is not sent back.
    func testAStoredProjectValueIsIgnoredNotEchoed() throws {
        let stored = #"{"subtaskDisplay":"indented","taskDisplayMode":"project"}"#
        let decoded = try JSONDecoder().decode(UserSettings.self, from: Data(stored.utf8))
        let echoed = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        XCTAssertFalse(echoed.contains("taskDisplayMode"), echoed)
    }

    func testNeitherSettingsScreenOffersTheLayoutPicker() throws {
        for path in ["Astrid App/Views/Settings/AppearanceSettingsView.swift",
                     "Astrid Mac/App/MacSettingsView.swift"] {
            let source = try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path),
                                    encoding: .utf8)
            XCTAssertFalse(source.contains("settings.taskDisplayMode"), path)
            XCTAssertFalse(source.contains("settings.task_display"), path)
        }
    }
}
