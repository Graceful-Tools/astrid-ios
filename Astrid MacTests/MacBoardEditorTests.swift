//  MacBoardEditorTests.swift
//  Astrid for Mac — Task 8e09d3c9: the board inline editor labels must match Astrid Web.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardEditorTests: XCTestCase {

    func testFieldLabelsMatchWeb() {
        XCTAssertEqual(MacBoardExpand.fieldLabels, ["Who", "Date", "Priority", "Lists", "Description"])
    }
}
#endif
