//  ProjectStateMoveTests.swift
//  Task AITD-352 — "task state buttons don't work. They should work like other task details
//  buttons."
//
//  They were sending the move and then showing nothing. `TaskDetailViewNew` renders the chips'
//  highlight from a `@State` snapshot of the task taken when the view opened, and the picker
//  discarded everything the move produced, so the snapshot kept the old `statusRole` and the
//  highlight never left the previous column. Every other control in that view keeps its own
//  `@State` mirror (`editedPriority`, `editedAssigneeId`, `isCompleted`) and updates on tap —
//  which is exactly the difference Jon reported.

import XCTest
@testable import Astrid_App

final class ProjectStateMoveTests: XCTestCase {

    private func task(id: String = "t1", statusRole: String? = nil, completed: Bool = false) -> Task {
        var t = TestHelpers.createTestTask(id: id, completed: completed)
        t.statusRole = statusRole
        return t
    }

    // MARK: - The hand-back (the actual bug)

    func testAStatusMoveReturnsTheTaskItProduced() async throws {
        let moved = task(statusRole: "doing")
        let result = try await ProjectStateMove.apply(
            plan: .setLists(["l1"], statusRole: "doing"),
            update: { _, _ in moved },
            complete: { _ in XCTFail("a status move must not touch completion"); return moved }
        )
        XCTAssertEqual(result?.statusRole, "doing",
                       "the moved task must come back so the view can redraw — discarding it is "
                       + "what made the chips look dead (AITD-352)")
    }

    func testTheRenderedColumnFollowsTheMove() throws {
        // The user-visible symptom, stated in the board's own vocabulary: the chip that lights up
        // is `getTaskProjectColumnId` of whatever task the view is holding. Hold the old one and
        // it keeps lighting the old chip no matter how many times you tap.
        let before = task(statusRole: "ready")
        let after = task(statusRole: "doing")

        XCTAssertEqual(getTaskProjectColumnId(before, lists: []), "ready")
        XCTAssertEqual(getTaskProjectColumnId(after, lists: []), "doing")
    }

    func testNothingComesBackWhenThereIsNothingToDo() async throws {
        let result = try await ProjectStateMove.apply(
            plan: .none,
            update: { _, _ in XCTFail("no write for an already-current column"); return self.task() },
            complete: { _ in XCTFail("no write for an already-current column"); return self.task() }
        )
        XCTAssertNil(result, "tapping the chip you are already on must not write anything")
    }

    // MARK: - Ordering, which the hand-back must not disturb

    func testMovingToDoneUpdatesThenCompletes_andReturnsTheCompletedTask() async throws {
        var calls: [String] = []
        let completed = task(statusRole: nil, completed: true)

        let result = try await ProjectStateMove.apply(
            plan: .complete(["l1"], statusRole: ""),
            update: { _, role in
                calls.append("update(\(role))")
                return self.task()
            },
            complete: { flag in
                calls.append("complete(\(flag))")
                return completed
            }
        )

        XCTAssertEqual(calls, ["update()", "complete(true)"],
                       "lists are set before the completion, as the board does it")
        XCTAssertEqual(result?.completed, true,
                       "the LAST write is the one the view should render")
    }

    func testMovingOutOfDoneUncompletesFirst_andReturnsTheUpdatedTask() async throws {
        var calls: [String] = []
        let reopened = task(statusRole: "ready")

        let result = try await ProjectStateMove.apply(
            plan: .uncomplete(["l1"], statusRole: "ready"),
            update: { _, role in
                calls.append("update(\(role))")
                return reopened
            },
            complete: { flag in
                calls.append("complete(\(flag))")
                return self.task(completed: false)
            }
        )

        XCTAssertEqual(calls, ["complete(false)", "update(ready)"],
                       "un-complete before setting lists — the reverse order re-completes it")
        XCTAssertEqual(result?.statusRole, "ready")
    }

    // MARK: - The call sites

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    func testTheDetailViewAdoptsTheMovedTask() throws {
        // The plumbing only helps if the view actually takes the value. `TaskDetailViewNew.task`
        // is `@State`, replaced nowhere except pull-to-refresh and the timer sheet — so without
        // this assignment the chips still render a snapshot from before the move.
        let view = try source("Astrid App/Views/Tasks/TaskDetailViewNew.swift")
        XCTAssertTrue(view.contains("onTaskUpdated:"),
                      "the state pickers in task details must feed the moved task back into the "
                      + "view's snapshot, or the chips keep rendering the pre-move state (AITD-352)")
    }

    func testThePickerOffersTheHandBack() throws {
        let picker = try source("Astrid App/Views/Components/ProjectStateQuickPicker.swift")
        XCTAssertTrue(picker.contains("onTaskUpdated"),
                      "ProjectStateQuickPicker must report the task its move produced")
        XCTAssertTrue(picker.contains("ProjectStateMove.apply"),
                      "the move sequence is shared, not re-spelled in the view")
    }
}
