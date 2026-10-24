//  TaskInProjectTests.swift
//  `isTaskInProject` (Core/Board/ProjectStatus.swift) — shared code, tested only in the Mac suite
//  until AITD-539 moved it here.

import XCTest
@testable import Astrid_App

/// The shared rule the row asks. Both ways of being in a project matter — see the doc comment on
/// `isTaskInProject`.
final class TaskInProjectTests: XCTestCase {

    private func list(_ id: String, projectId: String?) -> TaskList {
        TaskList(id: id, name: id, projectId: projectId)
    }

    private func task(listIds: [String], statusRole: String? = nil) -> Task {
        var t = Task(id: "t1", title: "t", completed: false)
        t.listIds = listIds
        t.statusRole = statusRole
        return t
    }

    func testATaskInAProjectListIsInAProject() {
        XCTAssertTrue(isTaskInProject(task(listIds: ["l1"]), lists: [list("l1", projectId: "p1")]))
    }

    func testATaskInAnOrdinaryListIsNot() {
        XCTAssertFalse(isTaskInProject(task(listIds: ["l1"]), lists: [list("l1", projectId: nil)]))
    }

    func testAStatusRoleIsEnoughOnItsOwn() {
        // The lists may not have loaded, or the project list may not be in this client's cache.
        // A task sitting in a Doing column is in a project whatever the list array says.
        XCTAssertTrue(isTaskInProject(task(listIds: [], statusRole: "doing"), lists: []))
    }

    func testAnEmptyStatusRoleIsNotAStatusRole() {
        // "" is the value Inbox and Done carry — it means "no status", not "in a project".
        XCTAssertFalse(isTaskInProject(task(listIds: ["l1"], statusRole: ""),
                                       lists: [list("l1", projectId: nil)]))
    }

    func testATaskInNoListsAtAllIsNot() {
        XCTAssertFalse(isTaskInProject(task(listIds: []), lists: [list("l1", projectId: "p1")]))
    }
}
