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

    // MARK: - AITD-648 "iPad full screen task details should reset after each task"
    //
    // The flag was a remembered setting: one task expanded meant every task after it opened full
    // screen, even after a relaunch. It belongs to the task that was expanded.

    /// Closing the panel — close button, swipe, tap again, a list switch — ends full screen, so the
    /// next task opens as the normal side panel.
    func testAITD648ClosingThePanelResetsFullScreen() {
        XCTAssertFalse(DetailPanelChrome.fullScreen(true, afterSelectionChangeTo: nil))
        XCTAssertFalse(DetailPanelChrome.fullScreen(false, afterSelectionChangeTo: nil))
    }

    /// Moving straight to another task with the panel still open (a subtask or parent link, a board
    /// card's full-screen button) keeps what was asked for: that is still one reading session.
    func testAITD648MovingBetweenTasksWithoutClosingKeepsTheFlag() {
        XCTAssertTrue(DetailPanelChrome.fullScreen(true, afterSelectionChangeTo: "subtask"))
        XCTAssertFalse(DetailPanelChrome.fullScreen(false, afterSelectionChangeTo: "subtask"))
    }

    /// A relaunch never opens the first task full screen.
    func testAITD648AppStartsWithFullScreenOff() {
        XCTAssertFalse(DetailPanelChrome.fullScreenAtLaunch)
    }

    private func source(of path: String) throws -> String {
        try String(contentsOf: RepositoryLocator.root.appendingPathComponent(path),
                   encoding: .utf8)
    }
}
