//  MacBoardMoveTests.swift
//  Regression for task 196d482a — board drops plan the right service ops, and completion
//  transitions (Done / un-Done) are split out so they go through completeTask, not updateTask.

import XCTest
@testable import Astrid_Mac

final class MacBoardMoveTests: XCTestCase {

    private let inbox = ProjectBoardColumn(id: VIRTUAL_INBOX_COLUMN_ID, name: "Inbox",
                                           description: "", kind: .inbox, statusList: nil)
    private let done = ProjectBoardColumn(id: VIRTUAL_DONE_COLUMN_ID, name: "Done",
                                          description: "", kind: .done, statusList: nil)

    private func task(_ id: String, completed: Bool, lists: [String]) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.listIds = lists
        return t
    }

    func testMoveToDonePlansComplete() {
        let t = task("1", completed: false, lists: ["L1"])
        XCTAssertEqual(MacBoardMove.plan(task: t, column: done, lists: []), .complete(["L1"]))
    }

    func testMoveOutOfDonePlansUncomplete() {
        let t = task("1", completed: true, lists: ["L1"])
        XCTAssertEqual(MacBoardMove.plan(task: t, column: inbox, lists: []), .uncomplete(["L1"]))
    }

    func testDropOntoCurrentColumnIsNoOp() {
        // A non-completed task with no status list already lives in Inbox.
        let t = task("1", completed: false, lists: ["L1"])
        XCTAssertEqual(MacBoardMove.plan(task: t, column: inbox, lists: []), .none)
        // A completed task already lives in Done.
        let d = task("2", completed: true, lists: ["L1"])
        XCTAssertEqual(MacBoardMove.plan(task: d, column: done, lists: []), .none)
    }
}
