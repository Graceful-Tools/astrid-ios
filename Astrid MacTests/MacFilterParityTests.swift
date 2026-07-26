//  MacFilterParityTests.swift
//  Regression for task 2b886104 — "[mac] the list filters and sort should exactly match the iOS
//  and sync!". Mac was missing whole dimensions (Assigned By, Repeating) and kept sort in a
//  scene-local override that never wrote `sortBy` to the list, so it never synced.
//
//  These pin the option VALUES against the ones iOS writes (ListSortFiltersTab) and the ones the
//  shared filter engine understands (ListTaskFiltering / RecentlyCompletedPresets) — the values
//  are the cross-platform contract; only labels are presentation.

import XCTest
@testable import Astrid_Mac

final class MacFilterParityTests: XCTestCase {

    private func values(_ options: [MacListFilter.Option]) -> [String] { options.map(\.value) }

    func testSortOptionsMatchIOS() {
        XCTAssertEqual(Set(values(MacListFilter.sort)),
                       ["auto", "manual", "when", "priority", "createdAt"],
                       "Mac must offer exactly the sort keys iOS writes to list.sortBy")
    }

    func testCompletionOptionsMatchTheSharedFilterEngine() {
        XCTAssertEqual(Set(values(MacListFilter.completion)),
                       ["default", "all", "completed", "incomplete"])
    }

    func testAssigneeOptionsMatchIOS() {
        XCTAssertEqual(Set(values(MacListFilter.assignee)),
                       ["all", "current_user", "not_current_user", "unassigned"])
    }

    func testAssignedByExistsAndMatchesIOS() {
        XCTAssertEqual(Set(values(MacListFilter.assignedBy)),
                       ["all", "current_user", "not_current_user"],
                       "Assigned By was missing on Mac entirely")
    }

    func testRepeatingExistsAndMatchesIOS() {
        XCTAssertEqual(Set(values(MacListFilter.repeating)),
                       ["all", "repeating", "not_repeating"],
                       "Repeating filter was missing on Mac entirely")
    }

    func testDueDateOptionsMatchTheSharedFilterEngine() {
        XCTAssertEqual(Set(values(MacListFilter.dueDate)),
                       ["all", "overdue", "today", "this_week", "this_month", "no_date"])
    }

    /// Every dimension must offer its inactive sentinel, or a filter could not be cleared.
    func testEveryDimensionCanBeCleared() {
        for options in [MacListFilter.completion, MacListFilter.priority, MacListFilter.dueDate,
                        MacListFilter.assignee, MacListFilter.assignedBy, MacListFilter.repeating] {
            XCTAssertTrue(values(options).contains { $0 == "all" || $0 == "default" },
                          "Missing a clear/all option in \(values(options))")
        }
    }
}
