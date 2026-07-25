//  MacBoardGroupingTests.swift
//  Astrid for Mac — Task 6042bde0: the hoisted-statusLists column-id variant must be equivalent
//  to the original (the board's one-pass grouping relies on it), and grouping covers every task.

import XCTest
@testable import Astrid_Mac

final class MacBoardGroupingTests: XCTestCase {

    private func task(_ id: String, completed: Bool = false, lists: [String] = []) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.listIds = lists
        return t
    }

    /// The fast variant (precomputed status lists) matches the original list-scanning variant.
    func testHoistedVariantEquivalence() {
        let tasks = [task("open", lists: ["L1"]), task("done", completed: true, lists: ["L1"]),
                     task("bare")]
        for t in tasks {
            XCTAssertEqual(getTaskProjectColumnId(t, statusLists: getProjectStatusLists([])),
                           getTaskProjectColumnId(t, lists: []),
                           "fast and original variants must agree for \(t.id)")
        }
    }

    func testVirtualColumnAssignment() {
        XCTAssertEqual(getTaskProjectColumnId(task("d", completed: true), statusLists: []), VIRTUAL_DONE_COLUMN_ID)
        XCTAssertEqual(getTaskProjectColumnId(task("i"), statusLists: []), VIRTUAL_INBOX_COLUMN_ID)
    }

    /// One-pass grouping must place every task in exactly one bucket.
    func testGroupingCoversAllTasks() {
        let tasks = [task("a"), task("b", completed: true), task("c", lists: ["L2"])]
        var buckets: [String: [Task]] = [:]
        let statusLists = getProjectStatusLists([])
        for t in tasks { buckets[getTaskProjectColumnId(t, statusLists: statusLists), default: []].append(t) }
        XCTAssertEqual(buckets.values.map(\.count).reduce(0, +), tasks.count)
        XCTAssertEqual(Set(buckets[VIRTUAL_DONE_COLUMN_ID]?.map(\.id) ?? []), ["b"])
        XCTAssertEqual(Set(buckets[VIRTUAL_INBOX_COLUMN_ID]?.map(\.id) ?? []), ["a", "c"])
    }
}
