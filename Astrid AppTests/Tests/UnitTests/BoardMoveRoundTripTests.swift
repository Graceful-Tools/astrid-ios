//  BoardMoveRoundTripTests.swift
//  "Moving tasks from Ready to Inbox doesn't always work."
//
//  AWTD-566 made the board PREFER `Task.statusRole` when resolving a card's column, and made
//  `resolveProjectColumnMove` compute the role the move should write. Nothing ever wrote it:
//  the board's drop handler calls `updateTask(taskId:completed:listIds:)`, and `statusRole`
//  is not a parameter it has. The computed role was dropped on the floor.
//
//  So dragging a task out of Ready removed the Ready LIST membership but left
//  `statusRole == "ready"` on the task, and the column resolver — which prefers the field —
//  put the card straight back in Ready.
//
//  "Doesn't ALWAYS work" is the tell: it fails only for tasks that HAVE a role. Older tasks
//  with a nil role still resolve by membership, and those moved fine.
//
//  Every previous test here checked one half — what the move computes, or how a column
//  resolves. Neither could see the gap between them. These tests close the loop: apply the
//  move to the task, then ask which column that task is now in. That round trip is the thing
//  the user actually experiences.

import XCTest
@testable import Astrid_App

final class BoardMoveRoundTripTests: XCTestCase {

    // MARK: - Fixtures

    private func statusList(_ id: String, _ name: String, role: String, order: Int) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.privacy = .PRIVATE
        list.ownerId = "user-1"
        list.projectId = nil
        list.listType = "status"
        list.statusRole = role
        list.statusOrder = order
        return list
    }

    private func domainList(_ id: String, projectId: String) -> TaskList {
        var list = TaskList(id: id, name: "Project")
        list.privacy = .PRIVATE
        list.ownerId = "user-1"
        list.projectId = projectId
        return list
    }

    private func task(lists: [TaskList], statusRole: String?, completed: Bool = false) -> Task {
        Task(id: "task-1", title: "Task", description: "", isAllDay: false, priority: .none,
             lists: lists, isPrivate: true, completed: completed, statusRole: statusRole)
    }

    private var ready: TaskList { statusList("ready-list", "Ready", role: "ready", order: 0) }
    private var doing: TaskList { statusList("doing-list", "Doing", role: "doing", order: 1) }
    private var project: TaskList { domainList("project-list", projectId: "p1") }
    private var allLists: [TaskList] { [ready, doing, project] }

    private func column(_ id: String) -> ProjectBoardColumn {
        getProjectBoardColumns(allLists).first { $0.id == id }!
    }

    /// Drop the card, write what the move says, then ask where the card ended up.
    private func columnAfterMoving(_ start: Task, to target: ProjectBoardColumn) -> String {
        let move = resolveProjectColumnMove(start, targetColumn: target, lists: allLists)
        let moved = start.applyingBoardMove(move)
        return getTaskProjectColumnId(moved, lists: allLists)
    }

    // MARK: - The bug

    /// THE REPORTED BUG: Ready → Inbox, for a task that carries a status role.
    func testMovingFromReadyToInboxLandsInInbox() {
        let start = task(lists: [project, ready], statusRole: "ready")

        XCTAssertEqual(columnAfterMoving(start, to: column(VIRTUAL_INBOX_COLUMN_ID)),
                       VIRTUAL_INBOX_COLUMN_ID,
                       "the card went back to Ready: the move cleared the list membership but "
                       + "left statusRole, and the resolver prefers statusRole")
    }

    /// The same failure reaches Done, which also carries no status.
    func testMovingFromReadyToDoneLandsInDone() {
        let start = task(lists: [project, ready], statusRole: "ready")
        let move = resolveProjectColumnMove(start, targetColumn: column(VIRTUAL_DONE_COLUMN_ID),
                                            lists: allLists)
        let moved = start.applyingBoardMove(move)

        XCTAssertTrue(moved.completed)
        XCTAssertEqual(getTaskProjectColumnId(moved, lists: allLists), VIRTUAL_DONE_COLUMN_ID)
    }

    // MARK: - Moves that already worked must keep working

    func testMovingBetweenTwoStatusColumnsLandsInTheTarget() {
        let start = task(lists: [project, ready], statusRole: "ready")

        XCTAssertEqual(columnAfterMoving(start, to: column("doing-list")), "doing-list")
    }

    func testMovingFromInboxIntoAStatusColumnLandsThere() {
        let start = task(lists: [project], statusRole: nil)

        XCTAssertEqual(columnAfterMoving(start, to: column("ready-list")), "ready-list")
    }

    /// The old model: a task with no role at all still moves by membership alone.
    func testATaskWithNoRoleStillMovesToInbox() {
        let start = task(lists: [project, ready], statusRole: nil)

        XCTAssertEqual(columnAfterMoving(start, to: column(VIRTUAL_INBOX_COLUMN_ID)),
                       VIRTUAL_INBOX_COLUMN_ID)
    }

    // MARK: - What the move must not damage

    /// Moving between columns must never drop the task out of its project.
    func testAMoveKeepsTheProjectMembership() {
        let start = task(lists: [project, ready], statusRole: "ready")
        let move = resolveProjectColumnMove(start, targetColumn: column(VIRTUAL_INBOX_COLUMN_ID),
                                            lists: allLists)
        let moved = start.applyingBoardMove(move)

        XCTAssertTrue(moved.listIds?.contains("project-list") == true,
                      "a board move must not evict the task from its own project")
    }

    /// Leaving Done clears completion, so a card dragged back out is genuinely reopened.
    func testMovingOutOfDoneClearsCompletion() {
        let start = task(lists: [project], statusRole: nil, completed: true)

        let move = resolveProjectColumnMove(start, targetColumn: column("ready-list"), lists: allLists)
        let moved = start.applyingBoardMove(move)

        XCTAssertFalse(moved.completed)
        XCTAssertEqual(getTaskProjectColumnId(moved, lists: allLists), "ready-list")
    }

    /// Round-tripping every column must be stable — drop it anywhere, it lands there.
    func testEveryColumnIsReachableFromEveryOtherColumn() {
        let columns = getProjectBoardColumns(allLists)

        for origin in columns {
            for target in columns {
                // Build a task that currently sits in `origin`.
                let originMove = resolveProjectColumnMove(
                    task(lists: [project], statusRole: nil), targetColumn: origin, lists: allLists)
                let sittingInOrigin = task(lists: [project], statusRole: nil)
                    .applyingBoardMove(originMove)
                XCTAssertEqual(getTaskProjectColumnId(sittingInOrigin, lists: allLists), origin.id,
                               "fixture is wrong: task did not start in \(origin.name)")

                XCTAssertEqual(columnAfterMoving(sittingInOrigin, to: target), target.id,
                               "\(origin.name) → \(target.name) did not land in \(target.name)")
            }
        }
    }
}
