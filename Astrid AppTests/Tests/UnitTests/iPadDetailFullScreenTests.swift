//  iPadDetailFullScreenTests.swift
//  Regression guard for Task c5ba07ed — "[ipad] task details. Add expand to full screen and
//  back to normal. Just like on Mac".
//
//  The iPad detail panel could only ever be the width of the messages pane it covers (or 40/50%
//  with no messages pane), which is the same complaint the Mac's pop-out had: a description
//  needs more room than a side panel can give.
//
//  "Like on Mac" is specific about what full screen MEANS. The Mac's pop-out expands to fill the
//  detail column — its sidebar stays put — so these pin the iPad to the same thing: the panel
//  takes the content area, and the 3-column list picker keeps its share.

import XCTest
@testable import Astrid_App

final class iPadDetailFullScreenTests: XCTestCase {

    private let width: CGFloat = 1194   // iPad Pro 11" landscape

    /// 3-column: the picker is a real pane, so full screen is everything except the picker.
    func testFullScreenTakesTheContentAreaButNotTheListPicker() {
        let expanded = iPadPaneLayout.detailWidth(total: width, columns: 3,
                                                  showsMessages: true, isFullScreen: true)
        let sidebar = iPadPaneLayout.widths(total: width, columns: 3,
                                            showsMessages: true, boardFullScreen: false).sidebar
        XCTAssertEqual(expanded, width - sidebar, accuracy: 0.5,
                       "Full screen fills the detail column, like the Mac's pop-out")
    }

    /// 2-column: the picker is a sliding drawer costing no width, so full screen is the window.
    func testFullScreenInTwoColumnTakesTheWholeWidth() {
        XCTAssertEqual(iPadPaneLayout.detailWidth(total: width, columns: 2,
                                                  showsMessages: true, isFullScreen: true),
                       width, accuracy: 0.5)
    }

    /// Expanded beats the messages-pane width it would otherwise take — that is the whole point.
    func testFullScreenIsWiderThanTheNormalPanel() {
        for columns in [2, 3] {
            for showsMessages in [true, false] {
                let normal = iPadPaneLayout.detailWidth(total: width, columns: columns,
                                                        showsMessages: showsMessages)
                let expanded = iPadPaneLayout.detailWidth(total: width, columns: columns,
                                                          showsMessages: showsMessages,
                                                          isFullScreen: true)
                XCTAssertGreaterThan(expanded, normal,
                                     "\(columns)-column, messages=\(showsMessages)")
            }
        }
    }

    /// Collapsing back is the same call without the flag — no separate "restore" width to drift.
    func testCollapsingReturnsTheOriginalWidth() {
        let before = iPadPaneLayout.detailWidth(total: width, columns: 3, showsMessages: true)
        let after = iPadPaneLayout.detailWidth(total: width, columns: 3,
                                               showsMessages: true, isFullScreen: false)
        XCTAssertEqual(before, after)
    }

    /// The header control must be wired to the panel, not just exist as a layout rule.
    ///
    /// Two files since AITD-425 extracted the header bar out of what was the largest file in
    /// the repo: `TaskDetailViewNew` still has to ACCEPT the callback from the iPad panel and
    /// hand it on, and `TaskDetailHeaderBar` is where the control is drawn.
    func testTheDetailHeaderOffersTheExpandControl() throws {
        let detail = try source(of: "Astrid App/Views/Tasks/TaskDetailViewNew.swift")
        XCTAssertTrue(detail.contains("onToggleFullScreen"),
                      "TaskDetailViewNew needs the expand callback the iPad panel supplies")

        let header = try source(of: "Astrid App/Views/Tasks/TaskDetailHeaderBar.swift")
        XCTAssertTrue(header.contains("onToggleFullScreen"),
                      "…and must pass it through to the bar that draws the control")
        XCTAssertTrue(header.contains("arrow.up.left.and.arrow.down.right"),
                      "Expand uses the same glyph as the Mac pop-out and the board")
        XCTAssertTrue(header.contains("arrow.down.right.and.arrow.up.left"),
                      "…and its counterpart for going back to normal")
    }

    private func source(of path: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path),
                   encoding: .utf8)
    }
}
