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

    func testRepeatingExistsAtAll() {
        // Superseded by testRepeatingOffersTheSameCadencesAsIOS for the exact set; this only pins
        // that the dimension exists (it was missing from Mac entirely).
        XCTAssertFalse(MacListFilter.repeating.isEmpty)
        XCTAssertTrue(values(MacListFilter.repeating).contains("all"))
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

// MARK: - Label parity with iOS (reported: "the filter names aren't the same as on the iOS app")

extension MacFilterParityTests {

    /// Mac must use iOS's OWN localized strings, not invented wording. Comparing the rendered
    /// labels catches both a wrong key and a Mac-only synonym like "Show" / "Any priority".
    func testFieldOptionLabelsMatchTheIOSStrings() {
        let expected: [(String, String)] = [
            ("default", NSLocalizedString("lists.incomplete_completed_recently", comment: "")),
            ("all", NSLocalizedString("lists.all", comment: "")),
            ("completed", NSLocalizedString("tasks.completed", comment: "")),
            ("incomplete", NSLocalizedString("tasks.incomplete", comment: "")),
        ]
        for (value, label) in expected {
            let option = MacListFilter.completion.first { $0.value == value }
            XCTAssertEqual(option?.label, label, "Completion '\(value)' must use iOS's wording")
        }
    }

    func testPriorityLabelsMatchIOSIncludingWhatZeroMeans() {
        let byValue = Dictionary(uniqueKeysWithValues: MacListFilter.priority.map { ($0.value, $0.label) })
        XCTAssertEqual(byValue["3"], NSLocalizedString("lists.highest_priority", comment: ""))
        XCTAssertEqual(byValue["2"], NSLocalizedString("lists.high_priority", comment: ""))
        XCTAssertEqual(byValue["1"], NSLocalizedString("lists.medium_priority", comment: ""))
        // Mac used to call 0 "None"; iOS calls it Low. Same value, so the wording must agree.
        XCTAssertEqual(byValue["0"], NSLocalizedString("lists.low_priority", comment: ""))
    }

    func testAssigneeAndSortLabelsMatchIOS() {
        let assignee = Dictionary(uniqueKeysWithValues: MacListFilter.assignee.map { ($0.value, $0.label) })
        XCTAssertEqual(assignee["current_user"], NSLocalizedString("lists.me", comment: ""))
        XCTAssertEqual(assignee["not_current_user"], NSLocalizedString("lists.not_me", comment: ""))
        XCTAssertEqual(assignee["unassigned"], NSLocalizedString("assignee.unassigned", comment: ""))

        let sort = Dictionary(uniqueKeysWithValues: MacListFilter.sort.map { ($0.value, $0.label) })
        XCTAssertEqual(sort["when"], NSLocalizedString("lists.due_date", comment: ""),
                       "iOS tags Due Date as 'when'")
        XCTAssertEqual(sort["auto"], NSLocalizedString("lists.auto", comment: ""))
        XCTAssertEqual(sort["createdAt"], NSLocalizedString("lists.created_date", comment: ""))
    }

    /// No label may be a raw English literal used as a key — a bug that renders the key itself.
    func testNoOptionLabelIsAnUnresolvedKey() {
        let all = MacListFilter.completion + MacListFilter.priority + MacListFilter.dueDate
            + MacListFilter.assignee + MacListFilter.assignedBy + MacListFilter.repeating + MacListFilter.sort
        for option in all {
            XCTAssertFalse(option.label.contains("."),
                           "'\(option.label)' looks like an unresolved localization key")
            XCTAssertFalse(option.label.isEmpty)
        }
    }

    /// Repeating offers iOS's cadences, not a Mac-only yes/no.
    func testRepeatingOffersTheSameCadencesAsIOS() {
        XCTAssertEqual(Set(MacListFilter.repeating.map(\.value)),
                       ["all", "not_repeating", "daily", "weekly", "monthly", "yearly", "custom"])
    }
}
