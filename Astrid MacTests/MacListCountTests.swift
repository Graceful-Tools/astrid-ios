//  MacListCountTests.swift
//  Regression for task 74d6f6aa — the sidebar's per-list count, mirroring iOS.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListCountTests: XCTestCase {

    private func task(_ id: String, listIds: [String]? = nil, lists: [TaskList]? = nil,
                      completed: Bool = false) -> Task {
        var t = Task(id: id, title: "Task \(id)", completed: completed)
        t.listIds = listIds
        t.lists = lists
        return t
    }

    private func list(_ id: String = "list-1", virtual: Bool = false) -> TaskList {
        var l = TaskList(id: id, name: "Work")
        l.isVirtual = virtual
        l.filterCompletion = "all"
        return l
    }

    /// The point of the badge: how much is LEFT, so completed tasks do not count.
    func testCountsOnlyIncompleteTasks() {
        let tasks = [task("a", listIds: ["list-1"]),
                     task("b", listIds: ["list-1"]),
                     task("done", listIds: ["list-1"], completed: true)]
        XCTAssertEqual(MacListCount.count(tasks, list: list()), 2)
    }

}
#endif

// MARK: - Batch counting (memoized: per-row counting is O(lists × tasks) per render)

extension MacListCountTests {
}
