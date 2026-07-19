//  MacSubtaskSplicingTests.swift
//  Astrid for Mac — Task 3c945236: the SHARED subtask splice (indented vs under-parent) + depth.

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

    func testIndentedSplicesSubtasksUnderParent() {
        let a = task("a"); let b = task("b")
        let a1 = task("a1", parent: "a", created: 1); let a2 = task("a2", parent: "a", created: 2)
        let out = spliceSubtasks(topLevel: [a, b], allTasks: [a, b, a1, a2],
                                 indented: true, subtaskVisible: { !$0.completed })
        XCTAssertEqual(out.map(\.id), ["a", "a1", "a2", "b"])
    }

    func testUnderParentHidesSubtasks() {
        let a = task("a"); let a1 = task("a1", parent: "a")
        let out = spliceSubtasks(topLevel: [a], allTasks: [a, a1], indented: false, subtaskVisible: { _ in true })
        XCTAssertEqual(out.map(\.id), ["a"])
    }

    func testSubtaskVisibilityFilter() {
        let a = task("a"); let a1 = task("a1", parent: "a", completed: true)
        // Completed subtask hidden when the filter excludes completed.
        let hidden = spliceSubtasks(topLevel: [a], allTasks: [a, a1], indented: true, subtaskVisible: { !$0.completed })
        XCTAssertEqual(hidden.map(\.id), ["a"])
        // Shown when the filter includes completed.
        let shown = spliceSubtasks(topLevel: [a], allTasks: [a, a1], indented: true, subtaskVisible: { _ in true })
        XCTAssertEqual(shown.map(\.id), ["a", "a1"])
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
