//  MacListEditSaveOnChangeTests.swift
//  Regression guard for Task da56d096 — "make sure all the editable defaults are (a) saved to the
//  web on change and (b) are applied".
//
//  Most of (a) already held: image, default priority/due date/repeating, default due time and the
//  recently-completed window each write through updateListAdvanced as they change. One did not.
//
//  Picking a placeholder image also sets the list's colour, because each placeholder carries its
//  own pastel — but only `imageUrl` was sent. The colour changed on screen and then reverted on
//  the next fetch, unless you happened to press Save afterwards. Both go in one write now.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListEditSaveOnChangeTests: XCTestCase {

    private func sheet() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/Views/MacListEditSheet.swift"), encoding: .utf8)
    }

    /// The bug: the colour that comes with the image has to be persisted with it.
    func testPickingAnImageSavesItsColourToo() throws {
        let source = try sheet()
        let picker = try XCTUnwrap(source.components(separatedBy: "func choosePlaceholder").last)
        let write = try XCTUnwrap(picker.components(separatedBy: "updateListAdvanced").dropFirst().first)
        XCTAssertTrue(write.contains("imageUrl"), "the image must be sent")
        XCTAssertTrue(write.contains("color"),
                      "…and so must the colour it sets, or it reverts on the next fetch")
    }

    /// Every default the sheet offers writes as it changes, rather than waiting for Save.
    func testEachDefaultWritesOnChange() throws {
        let source = try sheet()
        for (control, handler) in [("defPriority", "saveDefaults"),
                                   ("defDueDate", "saveDefaults"),
                                   ("defRepeating", "saveDefaults"),
                                   ("defDueTime", "saveDueTime"),
                                   ("recentlyCompleted", "saveRecentlyCompleted")] {
            XCTAssertTrue(source.contains("onChange(of: \(control)) { \(handler)"),
                          "\(control) should persist on change via \(handler)()")
        }
    }

    /// The defaults payload carries all three of the fields it claims to.
    func testTheDefaultsPayloadIsComplete() {
        let u = MacListDefaults.updates(priority: 3, dueDate: "today", repeating: "weekly")
        XCTAssertEqual(u["defaultPriority"] as? Int, 3)
        XCTAssertEqual(u["defaultDueDate"] as? String, "today")
        XCTAssertEqual(u["defaultRepeating"] as? String, "weekly")
    }
}
#endif
