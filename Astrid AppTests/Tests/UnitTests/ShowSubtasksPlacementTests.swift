//  ShowSubtasksPlacementTests.swift
//  Regression guard for Task ba1deb9d, REOPENED — "I don't see this in iOS list filter settings.
//  This should show in the / sort, filter section not the admin advanced section."
//
//  The toggle first shipped in the Admin tab because the task said "matching where web put it
//  (next to Board View)", and on iOS the board controls live in Admin. Where a setting sits on
//  web does not decide where it belongs on iOS: this is a question about what the list RENDERS,
//  which is what every other control in Sort & Filters answers.
//
//  The second test is the one with teeth. Sort & Filters persists through `saveSettings()`, which
//  posts EVERY filter field on each change. Folding showSubtasks into that payload would send it
//  on every unrelated edit and defeat ListSubtaskVisibility.payloadValue — the guard that stops a
//  sort change from quietly hiding a list's subtasks.

import XCTest
@testable import Astrid_App

final class ShowSubtasksPlacementTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(relative), encoding: .utf8)
    }

    /// It belongs in Sort & Filters, where the rest of "what this list shows" lives.
    func testTheToggleIsInTheSortAndFiltersTab() throws {
        let filters = try source("Astrid App/Views/Lists/ListSortFiltersTab.swift")
        XCTAssertTrue(filters.contains("lists.show_subtasks"),
                      "The show-subtasks toggle belongs in Sort & Filters (task ba1deb9d)")
    }

    /// …and not in Admin, where it was first shipped and where Jon could not find it.
    func testTheToggleIsNotInTheAdminTab() throws {
        let admin = try source("Astrid App/Views/Lists/ListAdminTab.swift")
        XCTAssertFalse(admin.contains("showSubtasks"),
                       "Admin is the advanced section; this is a display setting")
    }

    /// It must write on its own, not ride along in the bulk filter payload.
    func testItIsNotFoldedIntoTheBulkFilterSave() throws {
        let filters = try source("Astrid App/Views/Lists/ListSortFiltersTab.swift")
        let save = try XCTUnwrap(filters.components(separatedBy: "private func saveSettings()").last)
        XCTAssertFalse(save.contains("showSubtasks"),
                       """
                       saveSettings() posts every filter field on each change. Including \
                       showSubtasks there would send it on unrelated edits, which is exactly what \
                       ListSubtaskVisibility.payloadValue prevents.
                       """)
    }

    /// The write path still goes through the payload guard rather than sending a bare value.
    func testTheWritePathStillUsesThePayloadGuard() throws {
        let filters = try source("Astrid App/Views/Lists/ListSortFiltersTab.swift")
        XCTAssertTrue(filters.contains("ListSubtaskVisibility.payloadValue"),
                      "Only an actual change may be sent")
    }
}
