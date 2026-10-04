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
//
//  Since AITD-461 the move is astrid-core's (`setTaskStatus`, through
//  `TaskService.moveToBoardColumn`), which answers with the task it produced; these run against a
//  seeded in-memory core. The ORDER of the writes (un-complete before leaving Done, the column
//  before completing) is pinned by the core's own tests (CONTRACTS D45).

import AstridCore
import XCTest
@testable import Astrid_App

final class ProjectStateMoveTests: XCTestCase {

    private func task(id: String = "t1", statusRole: String? = nil, completed: Bool = false) -> Task {
        var t = TestHelpers.createTestTask(id: id, completed: completed)
        t.statusRole = statusRole
        t.listIds = ["board-list"]
        t.lists = nil
        return t
    }

    private var lists: [TaskList] {
        var board = TaskList(id: "board-list", name: "Board")
        board.projectId = "p1"
        return [board]
    }

    /// What the state menu's move answers with, for `task` moved to `columnId`.
    private func moved(_ task: Task, to columnId: String) throws -> Task {
        let session = try CoreBoardFixture.session(tasks: [task], lists: lists,
                                                   projects: [Project(id: "p1", name: "Board")])
        var command = CoreCommand(kind: "setTaskStatus")
        command.set("taskId", task.id)
        command.set("columnId", columnId)
        return try CoreRowsFixture.wait(session, command, as: Task.self)
    }

    // MARK: - The hand-back (the actual bug)

    func testAStatusMoveReturnsTheTaskItProduced() throws {
        let result = try moved(task(statusRole: "ready"), to: "doing")
        XCTAssertEqual(result.statusRole, "doing",
                       "the moved task must come back so the view can redraw — discarding it is "
                       + "what made the chips look dead (AITD-352)")
        XCTAssertFalse(result.completed, "a status move must not touch completion")
    }

    func testTheRenderedColumnFollowsTheMove() throws {
        // The user-visible symptom, stated in the board's own vocabulary: the chip that lights up
        // is the column of whatever task the view is holding. Hold the old one and it keeps
        // lighting the old chip no matter how many times you tap.
        let before = task(statusRole: "ready")
        let after = try moved(before, to: "doing")

        XCTAssertEqual(CoreBoardFixture.columnId(before, lists: lists), "ready")
        XCTAssertEqual(CoreBoardFixture.columnId(after, lists: lists), "doing")
    }

    func testNothingIsWrittenWhenThereIsNothingToDo() {
        let ready = ProjectBoardColumn(id: "ready", name: "Ready", description: "", kind: .status)
        XCTAssertEqual(CoreBoardFixture.plan(task: task(statusRole: "ready"), column: ready, lists: lists),
                       .none, "tapping the chip you are already on must not write anything")
    }

    // MARK: - What the move hands back at each end

    func testMovingToDoneReturnsTheCompletedTask() throws {
        let result = try moved(task(statusRole: "doing"), to: VIRTUAL_DONE_COLUMN_ID)
        XCTAssertTrue(result.completed, "the task handed back is the completed one")
        XCTAssertNil(result.statusRole, "Done carries no status")
    }

    func testMovingOutOfDoneReturnsTheReopenedTask() throws {
        let result = try moved(task(completed: true), to: "ready")
        XCTAssertFalse(result.completed, "leaving Done reopens the task")
        XCTAssertEqual(result.statusRole, "ready", "and the task handed back is in its new column")
    }

    // MARK: - The call sites

    private func source(_ path: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path), encoding: .utf8)
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
        XCTAssertTrue(picker.contains("moveToBoardColumn"),
                      "the move is the core's, through the service — not re-spelled in the view")
    }
}
