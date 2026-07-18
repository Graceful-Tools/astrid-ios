//  MacListTaskFilteringTests.swift
//  Regression for the SHARED per-list filtering/sorting business logic (Core/Filters/
//  ListTaskFiltering) — the single implementation iOS and Mac both call, so their lists match.

import XCTest
@testable import Astrid_Mac

final class MacListTaskFilteringTests: XCTestCase {

    private func task(_ id: String, priority: Task.Priority = .none, completed: Bool = false,
                      due: Date? = nil, created: Date? = nil) -> Task {
        var t = Task(id: id, title: id, completed: completed)
        t.priority = priority
        t.dueDateTime = due
        t.isAllDay = false
        t.createdAt = created
        return t
    }

    // MARK: due-date filter

    func testOverdueFilterKeepsOnlyPastIncomplete() {
        let overdue = task("od", due: Date().addingTimeInterval(-2 * 86_400))
        let today = task("td", due: Date())
        let doneOverdue = task("do", completed: true, due: Date().addingTimeInterval(-2 * 86_400))
        let ids = applyListDueDateFilter([overdue, today, doneOverdue], filter: "overdue").map { $0.id }
        XCTAssertEqual(ids, ["od"])
    }

    func testTodayFilterIncludesTodayAndOverdueIncomplete() {
        let overdue = task("od", due: Date().addingTimeInterval(-2 * 86_400))
        let today = task("td", due: Date())
        let future = task("ft", due: Date().addingTimeInterval(5 * 86_400))
        let ids = Set(applyListDueDateFilter([overdue, today, future], filter: "today").map { $0.id })
        XCTAssertEqual(ids, ["od", "td"])
    }

    func testNoDateFilter() {
        let dated = task("d", due: Date())
        let undated = task("u", due: nil)
        XCTAssertEqual(applyListDueDateFilter([dated, undated], filter: "no_date").map { $0.id }, ["u"])
    }

    // MARK: sort

    func testPrioritySortHighFirstCompletedLast() {
        let low = task("low", priority: .low)
        let high = task("high", priority: .high)
        let doneHigh = task("done", priority: .high, completed: true)
        let ids = sortTasksByListSetting([low, doneHigh, high], sortBy: "priority", manualOrder: nil).map { $0.id }
        XCTAssertEqual(ids, ["high", "low", "done"])
    }

    func testManualSortHonorsOrderThenNewestForRest() {
        let a = task("a", created: Date(timeIntervalSince1970: 100))
        let b = task("b", created: Date(timeIntervalSince1970: 200))
        let c = task("c", created: Date(timeIntervalSince1970: 300))   // not in manual order
        let ids = sortTasksByListSetting([a, b, c], sortBy: "manual", manualOrder: ["b", "a"]).map { $0.id }
        XCTAssertEqual(ids, ["b", "a", "c"])   // manual order first, then unlisted (newest) last
    }
}
