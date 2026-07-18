//  MacMyTasksTests.swift
//  Regression for task d0306aab — the universal "My Tasks" set: incomplete tasks that are mine
//  or unassigned (not assigned to other people), de-duplicated across lists.

import XCTest
@testable import Astrid_Mac

final class MacMyTasksTests: XCTestCase {

    private func task(_ id: String, assignee: String?, completed: Bool = false) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.assigneeId = assignee
        return t
    }

    func testIncludesMineAndUnassignedExcludesOthersAndCompleted() {
        let tasks = [
            task("mine", assignee: "me"),
            task("unassigned", assignee: nil),
            task("theirs", assignee: "you"),
            task("mineDone", assignee: "me", completed: true),
        ]
        let ids = Set(MacMyTasks.filter(tasks, userId: "me").map { $0.id })
        XCTAssertEqual(ids, ["mine", "unassigned"])
    }

    func testDeduplicatesAcrossLists() {
        let tasks = [task("1", assignee: "me"), task("1", assignee: "me")]
        XCTAssertEqual(MacMyTasks.filter(tasks, userId: "me").count, 1)
    }

    func testExcludesTasksAssignedToOthers() {
        let tasks = [task("a", assignee: "other1"), task("b", assignee: "other2")]
        XCTAssertTrue(MacMyTasks.filter(tasks, userId: "me").isEmpty)
    }
}
