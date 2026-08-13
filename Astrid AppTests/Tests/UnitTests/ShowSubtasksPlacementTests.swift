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
    ///
    /// iOS has TWO screens by that name — the settings-modal tab, and the one under a list's
    /// Configuration — and shipping the toggle on only one of them is exactly what happened
    /// (task 67552e15): "works on iOS" and "missing on iOS" were both true depending on which
    /// door you came through. Both, or neither.
    func testTheToggleIsInBothSortAndFiltersSurfaces() throws {
        for file in ["Astrid App/Views/Lists/ListSortFiltersTab.swift",
                     "Astrid App/Views/Lists/ListFiltersView.swift"] {
            XCTAssertTrue(try source(file).contains("lists.show_subtasks"),
                          "\(file) is a Sort & Filters surface and must carry the toggle")
        }
    }

    /// The second surface saves through its own bulk `saveFilters()`, with the same hazard.
    func testTheSecondSurfaceKeepsItOutOfTheBulkSave() throws {
        let view = try source("Astrid App/Views/Lists/ListFiltersView.swift")
        let save = try XCTUnwrap(view.components(separatedBy: "private func saveFilters()").last)
        XCTAssertFalse(save.contains("showSubtasks"),
                       "saveFilters() posts every filter field; including this would reset it")
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
