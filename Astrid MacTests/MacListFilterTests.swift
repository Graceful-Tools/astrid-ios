//  MacListFilterTests.swift
//  Astrid for Mac — Task a2bf6ccb: the filter editor's option VALUES must be the exact strings
//  the shared reader understands, and the active-count must drive the toolbar badge / Clear button.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListFilterTests: XCTestCase {

    /// Option values must match the shared Core/Filters vocabulary (else Mac filters differently).
    func testOptionValuesMatchSharedVocabulary() {
        XCTAssertEqual(MacListFilter.completion.map(\.value), ["default", "all", "incomplete", "completed"])
        XCTAssertEqual(MacListFilter.priority.map(\.value), ["all", "3", "2", "1", "0"])
        XCTAssertEqual(MacListFilter.dueDate.map(\.value), ["all", "overdue", "today", "this_week", "this_month", "no_date"])
        XCTAssertEqual(MacListFilter.assignee.map(\.value), ["all", "current_user", "not_current_user", "unassigned"])
    }

    /// Defaults ("default" for completion, "all" elsewhere, or nil/empty) count as inactive.
    func testActiveCountIgnoresDefaults() {
        XCTAssertEqual(MacListFilter.activeCount(completion: nil, priority: nil, dueDate: nil, assignee: nil), 0)
        XCTAssertEqual(MacListFilter.activeCount(completion: "default", priority: "all",
                                                 dueDate: "all", assignee: "all"), 0)
        XCTAssertEqual(MacListFilter.activeCount(completion: "", priority: "", dueDate: "", assignee: ""), 0)
    }

    /// Each non-default dimension increments the active count.
    func testActiveCountCountsNonDefaults() {
        XCTAssertEqual(MacListFilter.activeCount(completion: "completed", priority: "all",
                                                 dueDate: "all", assignee: "all"), 1)
        XCTAssertEqual(MacListFilter.activeCount(completion: "default", priority: "3",
                                                 dueDate: "today", assignee: "current_user"), 3)
        XCTAssertEqual(MacListFilter.activeCount(completion: "all", priority: "2",
                                                 dueDate: "overdue", assignee: "unassigned"), 4)
    }
}
#endif
