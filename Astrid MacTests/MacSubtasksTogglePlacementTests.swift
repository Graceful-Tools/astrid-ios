//  MacSubtasksTogglePlacementTests.swift
//  Regression guard for Task ba1deb9d, second correction — "confirmed works on iOS. but not on
//  Mac apps. Need to update sort and list settings on Mac."
//
//  The same placement mistake, one platform later: on iOS the toggle first shipped in the Admin
//  tab and had to move to Sort & Filters; on Mac it first shipped in the list Edit sheet and has
//  to move to the Filter sheet. Both times the reason is the same one web states in
//  list-sort-and-filters.tsx — it decides what the list VIEW renders.
//
//  The second test is the one that matters long-term: the Mac filter sheet has a `save()` that
//  posts every filter field at once, so showSubtasks must NOT be folded into it, or an unrelated
//  sort change would carry a value and reset someone's toggle.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacSubtasksTogglePlacementTests: XCTestCase {

    private func macSource(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac").appendingPathComponent(relative), encoding: .utf8)
    }

    func testTheToggleIsInTheFilterSheet() throws {
        XCTAssertTrue(try macSource("Views/MacFilterSheet.swift").contains("lists.show_subtasks"),
                      "Sort & filters is where it belongs on Mac too (task ba1deb9d)")
    }

    func testTheToggleIsNotInTheEditSheet() throws {
        XCTAssertFalse(try macSource("Views/MacListEditSheet.swift").contains("showSubtasks"),
                       "The edit sheet is the Mac's admin surface; this is a display setting")
    }

    /// It writes on its own, guarded — never as part of the bulk filter payload.
    func testItIsNotFoldedIntoTheBulkFilterSave() throws {
        let sheet = try macSource("Views/MacFilterSheet.swift")
        let save = try XCTUnwrap(sheet.components(separatedBy: "private func save()").last)
        XCTAssertFalse(save.contains("showSubtasks"),
                       "save() posts every filter field; including this would reset the toggle")
    }

    func testTheWriteUsesTheSharedPayloadGuard() throws {
        XCTAssertTrue(try macSource("Views/MacFilterSheet.swift")
            .contains("ListSubtaskVisibility.payloadValue"),
                      "Only an actual change may be sent — same guard as iOS")
    }
}
#endif
