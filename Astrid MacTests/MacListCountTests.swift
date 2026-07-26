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
        XCTAssertEqual(MacListCount.count(tasks, list: list(), currentUserId: nil), 2)
    }

    /// Tasks in OTHER lists must not inflate the count.
    func testIgnoresTasksInOtherLists() {
        let tasks = [task("a", listIds: ["list-1"]), task("b", listIds: ["other"])]
        XCTAssertEqual(MacListCount.count(tasks, list: list(), currentUserId: nil), 1)
    }

    /// Membership arrives in two shapes depending on where the task came from; counting only one
    /// of them under-reports.
    func testCountsMembershipInEitherRepresentation() {
        let hydrated = task("b", lists: [TaskList(id: "list-1", name: "Work")])
        XCTAssertEqual(MacListCount.count([task("a", listIds: ["list-1"]), hydrated],
                                          list: list(), currentUserId: nil), 2)
    }

    /// A public list's membership is not fully local — trust the server's number.
    func testPublicListUsesTheApiCount() {
        var l = list()
        l.privacy = .PUBLIC
        l.taskCount = 42
        XCTAssertEqual(MacListCount.count([], list: l, currentUserId: nil), 42)
    }

    /// A saved-filter list counts what its FILTERS admit, via the shared engine.
    func testVirtualListCountsThroughItsFilters() {
        var smart = list("smart-1", virtual: true)
        smart.filterCompletion = "incomplete"
        let tasks = [task("a", listIds: ["anything"]),
                     task("done", listIds: ["anything"], completed: true)]
        XCTAssertEqual(MacListCount.count(tasks, list: smart, currentUserId: nil), 1,
                       "The filter, not list membership, decides for a smart list")
    }

    func testEmptyListCountsZero() {
        XCTAssertEqual(MacListCount.count([], list: list(), currentUserId: nil), 0)
    }
}
#endif
