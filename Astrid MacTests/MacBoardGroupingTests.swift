//  MacBoardGroupingTests.swift
//  Astrid for Mac — Task 6042bde0: the hoisted column-id variant must be equivalent to the
//  original (the board's one-pass grouping relies on it), and grouping covers every task.
//
//  AITD-379 changed what gets hoisted: the fast variant now takes the board's COLUMNS rather
//  than its status lists, because a card's column is resolved against the columns the board
//  declares. The equivalence this suite pins is unchanged.

import XCTest
@testable import Astrid_Mac

final class MacBoardGroupingTests: XCTestCase {

    private func task(_ id: String, completed: Bool = false, lists: [String] = []) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.listIds = lists
        return t
    }

    /// The fast variant (precomputed columns) matches the lists-taking variant.
    func testHoistedVariantEquivalence() {
        let tasks = [task("open", lists: ["L1"]), task("done", completed: true, lists: ["L1"]),
                     task("bare")]
        for t in tasks {
            XCTAssertEqual(getTaskProjectColumnId(t, columns: getProjectBoardColumns([])),
                           getTaskProjectColumnId(t, lists: []),
                           "fast and original variants must agree for \(t.id)")
        }
    }

    /// The same equivalence with a custom column in play (AITD-379) — the hoist must not be
    /// the reason a card in a custom column groups differently from how the board resolves it.
    func testHoistedVariantEquivalenceWithACustomColumn() {
        let customStates = [ProjectCustomState(role: "blocked", name: "Blocked", order: 0)]
        var blocked = task("blocked-card", lists: ["L1"])
        blocked.statusRole = "blocked"

        XCTAssertEqual(
            getTaskProjectColumnId(blocked, columns: getProjectBoardColumns([], customStates: customStates)),
            getTaskProjectColumnId(blocked, lists: [], customStates: customStates)
        )
        XCTAssertEqual(getTaskProjectColumnId(blocked, lists: [], customStates: customStates), "blocked")
    }

    func testVirtualColumnAssignment() {
        XCTAssertEqual(getTaskProjectColumnId(task("d", completed: true), columns: []), VIRTUAL_DONE_COLUMN_ID)
        XCTAssertEqual(getTaskProjectColumnId(task("i"), columns: []), VIRTUAL_INBOX_COLUMN_ID)
    }

    /// One-pass grouping must place every task in exactly one bucket.
    func testGroupingCoversAllTasks() {
        let tasks = [task("a"), task("b", completed: true), task("c", lists: ["L2"])]
        var buckets: [String: [Task]] = [:]
        let columns = getProjectBoardColumns([])
        for t in tasks { buckets[getTaskProjectColumnId(t, columns: columns), default: []].append(t) }
        XCTAssertEqual(buckets.values.map(\.count).reduce(0, +), tasks.count)
        XCTAssertEqual(Set(buckets[VIRTUAL_DONE_COLUMN_ID]?.map(\.id) ?? []), ["b"])
        XCTAssertEqual(Set(buckets[VIRTUAL_INBOX_COLUMN_ID]?.map(\.id) ?? []), ["a", "c"])
    }
}
