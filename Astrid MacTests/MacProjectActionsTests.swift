//  MacProjectActionsTests.swift
//  ADEV-27: on the Mac a project could not be created on its own or deleted from the project. The
//  sidebar's Projects section hid itself until a project existed, so there was nowhere to start
//  one, and Delete lived only behind a list's Settings ▸ board switch.

#if os(macOS)
import AstridCore
import XCTest
@testable import Astrid_Mac

final class MacProjectActionsTests: XCTestCase {

    func testTheProjectsSectionShowsWithNoProjectsSoOneCanBeCreated_ADEV27() {
        XCTAssertTrue(MacProjectActions.showsSection(offered: true))
        XCTAssertFalse(MacProjectActions.showsSection(offered: false))
    }

    func testANewProjectNeedsANameAndIsTrimmed_ADEV27() {
        XCTAssertEqual(MacProjectActions.projectName(from: "  Launch  "), "Launch")
        XCTAssertNil(MacProjectActions.projectName(from: "   \n"))
        XCTAssertNil(MacProjectActions.projectName(from: ""))
    }

    func testDeletingTheOpenBoardLeavesNothingSelected_ADEV27() {
        let open = MacProjectSelection.tag(projectId: "p1")
        XCTAssertNil(MacProjectActions.selection(afterDeleting: "p1", current: open))
        XCTAssertEqual(MacProjectActions.selection(afterDeleting: "p1", current: "list-1"), "list-1")
        XCTAssertEqual(MacProjectActions.selection(afterDeleting: "p1", current: MacProjectSelection.tag(projectId: "p2")),
                       MacProjectSelection.tag(projectId: "p2"))
    }

    func testTheServersOwnerOnlyRefusalIsNamed_ADEV27() {
        let forbidden = CoreFailure(kind: .refused, message: "Only the owner can delete", status: 403, id: nil)
        XCTAssertEqual(MacProjectActions.deleteRefusalKey(for: forbidden), "projects.delete_forbidden")
        let offline = CoreFailure(kind: .offline, message: "offline", status: nil, id: nil)
        XCTAssertNil(MacProjectActions.deleteRefusalKey(for: offline))
    }
}
#endif
