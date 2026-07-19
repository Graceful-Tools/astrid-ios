//  MacBoardControlTests.swift
//  Astrid for Mac — Task 9e7f37d4: a list has a board iff attached to a project.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardControlTests: XCTestCase {

    func testIsEnabled() {
        XCTAssertTrue(MacBoardControl.isEnabled(projectId: "proj-1"))
        XCTAssertFalse(MacBoardControl.isEnabled(projectId: nil))
        XCTAssertFalse(MacBoardControl.isEnabled(projectId: ""))
    }
}
#endif
