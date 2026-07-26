//  MacAddTaskBarTests.swift
//  Astrid for Mac — Task bf998f4e: the bottom Add-task bar shows only for a real list.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAddTaskBarTests: XCTestCase {

    func testVisibleForRealList() {
        XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: true))
    }

    /// My Tasks now has a quick-add too (iOS parity) — the task is created with no list and
    /// appears there because My Tasks shows what is mine or unassigned.
    func testVisibleForMyTasks() {
        XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: true,
                                              isMyTasks: true))
    }

    /// Search and saved-filter lists own no real tasks, so they still have no quick-add.
    func testHiddenForSearchAndSavedFilters() {
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: true))
    }

    func testHiddenWithNoSelection() {
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: false))
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: false,
                                               isMyTasks: true), "Not even My Tasks without a selection")
    }
}
#endif
