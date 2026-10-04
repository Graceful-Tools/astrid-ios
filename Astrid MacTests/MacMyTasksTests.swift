//  MacMyTasksTests.swift
//  Regression for task d0306aab — the universal "My Tasks" set: incomplete tasks assigned to me,
//  de-duplicated across lists. Unassigned tasks used to be included too; iOS never had them, and
//  Jon 2026-10-03: on disagreement follow iOS (CONTRACTS D25, `MacFollowsIOSTests`).

import XCTest
@testable import Astrid_Mac

final class MacMyTasksTests: XCTestCase {

    private func task(_ id: String, assignee: String?, completed: Bool = false) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.assigneeId = assignee
        return t
    }

    /// These predate the saved filters (task ebdf94a1) and assert the SCOPE, which the filters
    /// did not change. `MyTasksPreferences()` is the untouched default — hide completed, all
    /// priorities, all due dates — so they keep testing exactly what they used to.
    func testIncludesMineExcludesUnassignedOthersAndCompleted() {
        let tasks = [
            task("mine", assignee: "me"),
            task("unassigned", assignee: nil),
            task("theirs", assignee: "you"),
            task("mineDone", assignee: "me", completed: true),
        ]
        let ids = Set(CoreRowsFixture.myTasksTasks(tasks, userId: "me", preferences: MyTasksPreferences()).map { $0.id })
        XCTAssertEqual(ids, ["mine"], "unassigned left with D25 — iOS never showed it")
    }

    func testDeduplicatesAcrossLists() {
        let tasks = [task("1", assignee: "me"), task("1", assignee: "me")]
        XCTAssertEqual(CoreRowsFixture.myTasksTasks(tasks, userId: "me", preferences: MyTasksPreferences()).count, 1)
    }

    func testExcludesTasksAssignedToOthers() {
        let tasks = [task("a", assignee: "other1"), task("b", assignee: "other2")]
        XCTAssertTrue(CoreRowsFixture.myTasksTasks(tasks, userId: "me", preferences: MyTasksPreferences()).isEmpty)
    }
}
