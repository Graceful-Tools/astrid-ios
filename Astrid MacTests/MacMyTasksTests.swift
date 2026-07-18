//  MacMyTasksTests.swift
//  Regression for task d0306aab — the virtual "My Tasks" entry shows only my incomplete tasks,
//  de-duplicated across lists.

import XCTest
@testable import Astrid_Mac

final class MacMyTasksTests: XCTestCase {

    private func task(_ id: String, assignee: String?, completed: Bool = false) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.assigneeId = assignee
        return t
    }

    func testFiltersToAssigneeAndIncomplete() {
        let tasks = [
            task("1", assignee: "me"),
            task("2", assignee: "you"),
            task("3", assignee: "me", completed: true),
        ]
        let mine = MacMyTasks.filter(tasks, userId: "me")
        XCTAssertEqual(mine.map { $0.id }, ["1"])
    }

    func testDeduplicatesAcrossLists() {
        let tasks = [task("1", assignee: "me"), task("1", assignee: "me")]
        XCTAssertEqual(MacMyTasks.filter(tasks, userId: "me").count, 1)
    }

    func testNilUserReturnsEmpty() {
        XCTAssertTrue(MacMyTasks.filter([task("1", assignee: "me")], userId: nil).isEmpty)
    }
}
