//  MacAddTaskBarTests.swift
//  Astrid for Mac — Task bf998f4e: the bottom Add-task bar shows only for a real list.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAddTaskBarTests: XCTestCase {

    func testVisibleOnlyForRealList() {
        XCTAssertTrue(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: true))
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: true, hasSelection: true))   // My Tasks/Search/Smart
        XCTAssertFalse(MacAddTaskBar.isVisible(isVirtualSelection: false, hasSelection: false)) // nothing selected
    }
}
#endif
