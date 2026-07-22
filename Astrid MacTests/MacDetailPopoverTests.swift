//  MacDetailPopoverTests.swift
//  Astrid for Mac — Task 2766d9a4: the detail pop-out shows only for a single selection.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacDetailPopoverTests: XCTestCase {

    func testVisibleOnlyForSingleSelection() {
        XCTAssertFalse(MacDetailPopover.isVisible(selectionCount: 0), "No selection → no pop-out (full-width list)")
        XCTAssertTrue(MacDetailPopover.isVisible(selectionCount: 1))
        XCTAssertFalse(MacDetailPopover.isVisible(selectionCount: 3), "Multi-select → no single-task detail")
    }
}
#endif
