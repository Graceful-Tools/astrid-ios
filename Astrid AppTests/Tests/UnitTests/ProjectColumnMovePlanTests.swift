//  ProjectColumnMovePlanTests.swift
//  Moving a task to a board column, planned once for both platforms (task 729a190e).
//
//  The quick changer gives task details a second way to change a task's column, on both
//  platforms. The board already had one, in `MacBoardMove.plan`, which was Mac-only — so the
//  rule moved to `planProjectColumnMove` in shared Core rather than being written again for
//  iOS. These pin the parts that fail QUIETLY if a second copy ever drifts back in.
//
//  What makes a wrong plan hard to notice: nothing throws. The task moves, and only the
//  completion or the status role is wrong — so it reappears in the column it came from, or a
//  repeating task silently stops repeating.

import XCTest
@testable import Astrid_App

final class ProjectColumnMovePlanTests: XCTestCase {

    private func statusList(_ id: String, _ name: String, role: String) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.listType = "status"
        list.statusRole = role
        return list
    }

    private var lists: [TaskList] {
        [statusList("ready-id", "Ready", role: "ready"),
         statusList("doing-id", "Doing", role: "doing")]
    }

    private func column(_ id: String, kind: ProjectBoardColumnKind, list: TaskList? = nil) -> ProjectBoardColumn {
        ProjectBoardColumn(id: id, name: id, description: "", kind: kind, statusList: list)
    }

    private func task(_ id: String = "t1",
                      completed: Bool = false,
                      listIds: [String] = [],
                      statusRole: String? = nil) -> Task {
        var t = Task(id: id, title: "Task")
        t.completed = completed
        t.listIds = listIds
        t.statusRole = statusRole
        return t
    }

    // MARK: - Moving to the column it is already in

    /// A no-op must be recognised as one. Re-writing the same membership would burn an API
    /// call and, worse, take a repeating task through completion again.
    func testMovingToItsCurrentColumnPlansNothing() {
        let t = task(listIds: ["ready-id"], statusRole: "ready")
        let ready = column("ready-id", kind: .status, list: lists[0])
        XCTAssertEqual(planProjectColumnMove(task: t, column: ready, lists: lists), .none)
    }

    // MARK: - Done

    /// THE ONE THAT MATTERS MOST. Moving to Done must plan a COMPLETION, not merely a list
    /// change — a plan that only moved lists would leave the task open in the Done column.
    func testMovingToDonePlansACompletion() {
        let t = task(listIds: ["ready-id"])
        let done = column(VIRTUAL_DONE_COLUMN_ID, kind: .done)
        guard case .complete = planProjectColumnMove(task: t, column: done, lists: lists) else {
            return XCTFail("moving to Done must complete the task, not just re-file it")
        }
    }

    /// And back out again: a completed task leaving Done must be UN-completed first. Without
    /// it the task keeps its tick and the board shows a finished task sitting in Ready.
    func testMovingOutOfDonePlansAnUncomplete() {
        let t = task(completed: true)
        let ready = column("ready-id", kind: .status, list: lists[0])
        guard case .uncomplete = planProjectColumnMove(task: t, column: ready, lists: lists) else {
            return XCTFail("a completed task leaving Done must be un-completed")
        }
    }

    // MARK: - The status role, which is what actually decides the column

    /// The board resolves a card's column from `statusRole` FIRST (AWTD-566). A plan that
    /// describes only the membership leaves the role behind and the resolver puts the card
    /// straight back where it came from — this is the "moving to Inbox doesn't always work"
    /// bug, where "not always" meant "not for any task that has a role".
    func testMovingToAStatusColumnCarriesThatRole() {
        let t = task(listIds: ["ready-id"])
        let doing = column("doing-id", kind: .status, list: lists[1])
        guard case .setLists(_, let role) = planProjectColumnMove(task: t, column: doing, lists: lists) else {
            return XCTFail("expected a plain list move")
        }
        XCTAssertEqual(role, "doing", "the role is what the board actually reads")
    }

    /// Inbox carries no status, and "" is the value that CLEARS the role rather than leaving
    /// it untouched. A nil here would read as "no change" and strand the task in its old column.
    func testMovingToInboxClearsTheRoleWithAnEmptyString() {
        let t = task(listIds: ["ready-id"], statusRole: "ready")
        let inbox = column(VIRTUAL_INBOX_COLUMN_ID, kind: .inbox)
        guard case .setLists(_, let role) = planProjectColumnMove(task: t, column: inbox, lists: lists) else {
            return XCTFail("expected a plain list move")
        }
        XCTAssertEqual(role, "", "\"\" clears the role; nil would mean leave it alone")
    }

    // MARK: - Regular list memberships survive

    /// A task in a normal list AND a status list keeps the normal one. Dropping it would
    /// remove the task from the list the user actually filed it in, which is data loss that
    /// looks like a board bug.
    func testANonStatusListMembershipIsPreserved() {
        let t = task(listIds: ["my-list", "ready-id"])
        let doing = column("doing-id", kind: .status, list: lists[1])
        guard case .setLists(let ids, _) = planProjectColumnMove(task: t, column: doing, lists: lists) else {
            return XCTFail("expected a plain list move")
        }
        XCTAssertTrue(ids.contains("my-list"), "a regular list membership is not the board's to remove")
        XCTAssertFalse(ids.contains("ready-id"), "the old status membership is replaced")
    }
}
