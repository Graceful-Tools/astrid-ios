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

// MARK: - Batch counting (memoized: per-row counting is O(lists × tasks) per render)

extension MacListCountTests {

    /// The batch pass must agree with the single-list rule — otherwise memoizing changes behaviour.
    func testBatchAgreesWithSingleListCounting() {
        let work = TaskList(id: "work", name: "Work")
        let home = TaskList(id: "home", name: "Home")
        let tasks = [task("a", listIds: ["work"]),
                     task("b", listIds: ["work"]),
                     task("c", listIds: ["home"]),
                     task("done", listIds: ["work"], completed: true)]
        let batch = MacListCount.counts(tasks, lists: [work, home], currentUserId: nil)
        XCTAssertEqual(batch["work"], MacListCount.count(tasks, list: work, currentUserId: nil))
        XCTAssertEqual(batch["home"], MacListCount.count(tasks, list: home, currentUserId: nil))
        XCTAssertEqual(batch["work"], 2)
        XCTAssertEqual(batch["home"], 1)
    }

    /// A task in BOTH representations of the same list must be counted once, not twice.
    func testBatchDoesNotDoubleCountDualMembership() {
        let work = TaskList(id: "work", name: "Work")
        var t = task("a", listIds: ["work"])
        t.lists = [work]
        XCTAssertEqual(MacListCount.counts([t], lists: [work], currentUserId: nil)["work"], 1)
    }

    /// Every list gets an entry, so a list with nothing in it shows 0 rather than a blank badge.
    func testEveryListGetsAnEntry() {
        let empty = TaskList(id: "empty", name: "Empty")
        XCTAssertEqual(MacListCount.counts([], lists: [empty], currentUserId: nil)["empty"], 0)
    }

    func testBatchHonoursPublicAndVirtualExceptions() {
        var pub = TaskList(id: "pub", name: "Public")
        pub.privacy = .PUBLIC
        pub.taskCount = 7
        var smart = TaskList(id: "smart", name: "Smart")
        smart.isVirtual = true
        smart.filterCompletion = "incomplete"
        let tasks = [task("a", listIds: ["x"]), task("done", listIds: ["x"], completed: true)]
        let batch = MacListCount.counts(tasks, lists: [pub, smart], currentUserId: nil)
        XCTAssertEqual(batch["pub"], 7)
        XCTAssertEqual(batch["smart"], 1)
    }
}
