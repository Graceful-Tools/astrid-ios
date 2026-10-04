//  MacBoardGroupingTests.swift
//  Astrid for Mac — Task 6042bde0: every card lands in exactly one column.
//
//  Since AITD-461 the Mac board groups nothing itself: its columns and cards are astrid-core's
//  `board`, the board iOS draws (CONTRACTS D43) — so these ask a seeded in-memory core, and the
//  last one pins what the Mac took from iOS: subtasks are not cards, Done holds recent work, and
//  a column is in the list's manual order.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardGroupingTests: XCTestCase {

    private func task(_ id: String, completed: Bool = false, role: String? = nil,
                      updatedAt: Date? = Date()) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.listIds = ["L1"]
        t.statusRole = role
        t.updatedAt = updatedAt
        return t
    }

    private func board(_ tasks: [Task], customStates: [ProjectCustomState]? = nil,
                       manualOrder: [String]? = nil) throws -> [BoardModel.Column] {
        var list = TaskList(id: "L1", name: "Board")
        list.projectId = "p1"
        list.manualSortOrder = manualOrder
        let session = try CoreBoardFixture.session(
            tasks: tasks, lists: [list], projects: [Project(id: "p1", name: "Board", customStates: customStates)])
        return try CoreBoardFixture.drawn(session, listId: "L1")
    }

    private func ids(_ columns: [BoardModel.Column], _ id: String) -> [String] {
        columns.first { $0.id == id }?.ids ?? []
    }

    func testACustomColumnHoldsItsCards() throws {
        let columns = try board([task("blocked-card", role: "blocked")],
                                customStates: [ProjectCustomState(role: "blocked", name: "Blocked", order: 0)])
        XCTAssertEqual(ids(columns, "blocked"), ["blocked-card"])
    }

    func testVirtualColumnAssignment() throws {
        let columns = try board([task("d", completed: true), task("i")])
        XCTAssertEqual(ids(columns, VIRTUAL_DONE_COLUMN_ID), ["d"])
        XCTAssertEqual(ids(columns, VIRTUAL_INBOX_COLUMN_ID), ["i"])
    }

    /// Every card must land in exactly one column.
    func testGroupingCoversAllTasks() throws {
        let tasks = [task("a"), task("b", completed: true), task("c", role: "doing")]
        let columns = try board(tasks)
        let placed = columns.flatMap(\.ids)
        XCTAssertEqual(placed.count, tasks.count)
        XCTAssertEqual(Set(placed), ["a", "b", "c"])
    }

    /// The Mac follows iOS (AITD-461): no subtask cards, Done holds recent work only, and a
    /// column is in the list's manual order.
    func testTheMacBoardIsIOSBoard() throws {
        var child = task("child")
        child.parentTaskId = "a"
        let stale = task("stale", completed: true, updatedAt: Date().addingTimeInterval(-3 * 86_400))
        let columns = try board([task("a"), task("b"), child, stale], manualOrder: ["b", "a"])
        XCTAssertEqual(ids(columns, VIRTUAL_INBOX_COLUMN_ID), ["b", "a"])
        XCTAssertTrue(ids(columns, VIRTUAL_DONE_COLUMN_ID).isEmpty,
                      "a task finished three days ago has left Done, as on iOS")
    }
}
#endif
