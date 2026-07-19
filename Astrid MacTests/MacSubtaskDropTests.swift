//  MacSubtaskDropTests.swift
//  Astrid for Mac — drag-to-indent guard: no self-parenting, no cycles.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSubtaskDropTests: XCTestCase {

    private func task(_ id: String, parent: String? = nil) -> Task {
        var t = Task(id: id, title: id, completed: false); t.parentTaskId = parent; return t
    }

    func testAllowsNormalReparent() {
        let tasks = [task("a"), task("b")]
        XCTAssertTrue(MacSubtaskDrop.canParent(childId: "a", parentId: "b", allTasks: tasks))
    }

    func testRejectsSelf() {
        XCTAssertFalse(MacSubtaskDrop.canParent(childId: "a", parentId: "a", allTasks: [task("a")]))
    }

    func testRejectsCycle() {
        // b is a child of a → making a a child of b would create a cycle.
        let tasks = [task("a"), task("b", parent: "a")]
        XCTAssertFalse(MacSubtaskDrop.canParent(childId: "a", parentId: "b", allTasks: tasks))
    }

    func testRejectsDeepCycle() {
        // a → b → c ; dropping a under c is a cycle.
        let tasks = [task("a"), task("b", parent: "a"), task("c", parent: "b")]
        XCTAssertFalse(MacSubtaskDrop.canParent(childId: "a", parentId: "c", allTasks: tasks))
        // But dropping c under a (its existing ancestor, different node) is allowed (not a cycle).
        XCTAssertTrue(MacSubtaskDrop.canParent(childId: "c", parentId: "a", allTasks: tasks))
    }
}
#endif
