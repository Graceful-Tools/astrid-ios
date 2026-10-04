//  MacSubtaskSplicingTests.swift
//  Astrid for Mac — Task 3c945236: the SHARED subtask splice (indented vs under-parent) + depth.
//  The splice is astrid-core's since AITD-460 (`rowsForList`, as iOS draws it): these ask it for a
//  saved filter over the given tasks, whose completion setting is what decides a subtask.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSubtaskSplicingTests: XCTestCase {

    private func task(_ id: String, parent: String? = nil, completed: Bool = false, created: TimeInterval = 0) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.parentTaskId = parent
        t.createdAt = Date(timeIntervalSince1970: created)
        return t
    }

    /// The rows a saved filter over `tasks` draws, subtasks spliced or not.
    private func rows(_ tasks: [Task], indented: Bool, completion: String) throws -> [String] {
        var shape = TaskList(id: "all", name: "")
        shape.isVirtual = true
        shape.filterCompletion = completion
        shape.sortBy = "auto"
        return try CoreRowsFixture.rows(tasks, list: shape, subtaskDisplay: indented ? "indented" : "under_parent")
    }

    func testIndentedSplicesSubtasksUnderParent() throws {
        let a = task("a"); let b = task("b")
        let a1 = task("a1", parent: "a", created: 1); let a2 = task("a2", parent: "a", created: 2)
        XCTAssertEqual(try rows([a, b, a1, a2], indented: true, completion: "incomplete"), ["a", "a1", "a2", "b"])
    }

    func testUnderParentHidesSubtasks() throws {
        let a = task("a"); let a1 = task("a1", parent: "a")
        XCTAssertEqual(try rows([a, a1], indented: false, completion: "all"), ["a"])
    }

    func testSubtaskVisibilityFilter() throws {
        let a = task("a"); let a1 = task("a1", parent: "a", completed: true)
        // Completed subtask hidden when the filter excludes completed.
        XCTAssertEqual(try rows([a, a1], indented: true, completion: "incomplete"), ["a"])
        // Shown when the filter includes completed.
        XCTAssertEqual(try rows([a, a1], indented: true, completion: "all"), ["a", "a1"])
    }

    func testDepth() {
        let a = task("a"); let a1 = task("a1", parent: "a"); let a1x = task("a1x", parent: "a1")
        let byId = ["a": a, "a1": a1, "a1x": a1x]
        XCTAssertEqual(subtaskDepth(a, byId: byId), 0)
        XCTAssertEqual(subtaskDepth(a1, byId: byId), 1)
        XCTAssertEqual(subtaskDepth(a1x, byId: byId), 2)
    }
}
#endif
