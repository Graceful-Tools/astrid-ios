//  iPhoneDetailZoomTests.swift
//  AITD-609, superseded by AITD-664 for the zoom — "[design] iPhone: what carries the task-details outline and motion when details take
//  the whole screen?" (register DS7 in astrid-core `design/README.md`).
//
//  On iPad the details panel wears the selected row's outline and opens out of it (AITD-607). On
//  iPhone the details are a full-screen push with no row beside them, so DS7 is carried there by
//  the motion instead: the details zoom out of the tapped row, and on the way back the row the
//  details closed into wears the selection outline for one `motion.panel`.

import XCTest
@testable import Astrid_App

final class iPhoneDetailZoomTests: XCTestCase {

    /// AITD-664 — "iOS iPhone open task rows to task details should open same way as board Tasks.
    /// See old way of opened." A board card on iPhone pushes the details with the ordinary slide
    /// (AITD-642, the old way), so a list row does too: no push from a row zooms out of it, on
    /// iPhone or as a forced push on iPad. One-pane views open details one way.
    func testAPushFromARowSlidesLikeABoardCard_AITD664() {
        XCTAssertFalse(DetailPanelChrome.zoomsFromRow(usesSplitLayout: false, forcePushNavigation: false))
        XCTAssertFalse(DetailPanelChrome.zoomsFromRow(usesSplitLayout: true, forcePushNavigation: true))
        XCTAssertFalse(DetailPanelChrome.zoomsFromRow(usesSplitLayout: true, forcePushNavigation: false))
    }

    /// The return flash lasts one `motion.panel`, the same beat the iPad panel opens over.
    func testReturnFlashLastsOnePanelBeat() {
        XCTAssertEqual(DetailPanelChrome.returnFlashDuration, DetailPanelChrome.panelDuration, accuracy: 0.0001)
    }

    /// The row the details closed into wears the outline while it flashes; other rows do not, and
    /// the iPad's panel selection still outlines its row.
    func testTheReturningRowWearsTheOutline() {
        XCTAssertTrue(DetailPanelChrome.rowIsOutlined(taskId: "a", panelSelectionId: nil, returningTaskId: "a"))
        XCTAssertFalse(DetailPanelChrome.rowIsOutlined(taskId: "b", panelSelectionId: nil, returningTaskId: "a"))
        XCTAssertTrue(DetailPanelChrome.rowIsOutlined(taskId: "b", panelSelectionId: "b", returningTaskId: nil))
        XCTAssertFalse(DetailPanelChrome.rowIsOutlined(taskId: "b", panelSelectionId: nil, returningTaskId: nil))
    }
}
