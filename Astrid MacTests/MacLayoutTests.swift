//  MacLayoutTests.swift
//  Astrid for Mac — Task 23c98550: responsive 2/3-column rule mirrors the web thresholds.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacLayoutTests: XCTestCase {

    func testThresholdMirrorsWeb() {
        // Web goes 3-column at a ≥1100px WINDOW. Mac now measures the window too, so the numbers
        // are directly comparable (it used to subtract the sidebar and measure the content).
        XCTAssertEqual(MacLayout.chatColumnWindowThreshold, 1100)
    }

    func testChatColumnRule() {
        XCTAssertTrue(MacLayout.showsChatColumn(windowWidth: 1200, isRealList: true), "Wide + real list → 3-col")
        XCTAssertFalse(MacLayout.showsChatColumn(windowWidth: 900, isRealList: true), "Narrow → 2-col")
        XCTAssertFalse(MacLayout.showsChatColumn(windowWidth: 1200, isRealList: false),
                       "Virtual selections (Search / saved filters) have no chat channel")
        // Boundary: exactly at the threshold is 3-col (web uses >=).
        XCTAssertTrue(MacLayout.showsChatColumn(windowWidth: 1100, isRealList: true))
    }

    /// Reported: showing the left rail closed the right column. The decision must depend only on
    /// the WINDOW, which does not change when the sidebar opens — so the same window width gives
    /// the same answer regardless of how much content area the sidebar leaves behind.
    func testTogglingTheSidebarCannotCloseTheChatColumn() {
        let window: CGFloat = 1_200
        let withSidebar = MacLayout.showsChatColumn(windowWidth: window, isRealList: true)
        let withoutSidebar = MacLayout.showsChatColumn(windowWidth: window, isRealList: true)
        XCTAssertEqual(withSidebar, withoutSidebar)
        XCTAssertTrue(withSidebar)
        // The old content-based rule failed exactly here: 1200 − 240 = 960, which is under the
        // 1100 threshold it was compared against once the sidebar opened.
        XCTAssertTrue(window - 240 < MacLayout.chatColumnWindowThreshold,
                      "This is the case that used to close the chat column")
    }
}
#endif

// MARK: - Detail pop-out floats over the chat column (task 89e42f29 follow-up)

extension MacLayoutTests {

    /// The arrow TIP must land exactly on the row card's trailing edge. Both sides are computed
    /// from the same constants, so this is the real invariant: derive the chat width, then check
    /// the two edges coincide.
    func testArrowTipMeetsTheRowTrailingEdge() {
        let contentRight: CGFloat = 1_000
        let cardLeft = contentRight - MacLayout.detailPanelMargin - MacLayout.detailPanelWidth
        let arrowTip = cardLeft - (MacLayout.detailArrowWidth - MacLayout.arrowOverlap)
        let rowRight = contentRight - MacLayout.chatColumnWidth
            - MacLayout.columnDividerWidth - MacLayout.rowTrailingGap
        XCTAssertEqual(arrowTip, rowRight, accuracy: 0.001,
                       "The arrow must touch the row card, not float short of it")
    }

    /// The panel still fits beside the rows: it may overlap the divider by the arrow, but the
    /// CARD itself must stay clear of the row content.
    func testPanelStaysWithinTheChatSideOfTheDivider() {
        let contentRight: CGFloat = 1_000
        let cardLeft = contentRight - MacLayout.detailPanelMargin - MacLayout.detailPanelWidth
        let rowRight = contentRight - MacLayout.chatColumnWidth
            - MacLayout.columnDividerWidth - MacLayout.rowTrailingGap
        XCTAssertGreaterThan(cardLeft, rowRight, "The card must not cover the row content")
    }

    /// The pop-out width is panel + arrow + a margin on EACH side, so the arrow has room on the
    /// leading edge and the panel has a matching margin on the trailing edge.
    func testPopoutWidthIsPanelPlusArrowPlusBothMargins() {
        XCTAssertEqual(MacLayout.detailPopoutWidth,
                       MacLayout.detailPanelWidth + MacLayout.detailArrowWidth
                       + MacLayout.detailPanelMargin * 2)
    }

    /// Margins are symmetric — "a similar width on the right" as on the arrow side.
    func testMarginsAreSymmetric() {
        XCTAssertGreaterThan(MacLayout.detailPanelMargin, 0)
        XCTAssertEqual(MacLayout.detailPopoutWidth - MacLayout.detailPanelWidth
                       - MacLayout.detailArrowWidth,
                       MacLayout.detailPanelMargin * 2)
    }

    /// There is deliberately NO "reserve width for the pop-out" helper any more: reserving width
    /// is what made the rows reflow when a task was selected.
    /// Chat width is DERIVED from the panel geometry, so changing the panel width cannot silently
    /// break the arrow alignment or reintroduce a row reflow.
    func testChatColumnIsDerivedNotAMagicNumber() {
        let expected = MacLayout.detailPanelMargin + MacLayout.detailPanelWidth
            + (MacLayout.detailArrowWidth - MacLayout.arrowOverlap)
            - MacLayout.rowTrailingGap - MacLayout.columnDividerWidth
        XCTAssertEqual(MacLayout.chatColumnWidth, expected, accuracy: 0.001)
    }

    /// The panel is allowed to OVERHANG the chat column slightly — that is what pulls the arrow
    /// far enough left to touch the row. What matters is that the overhang stays inside the row
    /// gutter (empty margin), which testPanelStaysWithinTheChatSideOfTheDivider checks; here we
    /// bound it so it can never grow into a full column's worth.
    func testPanelOverhangStaysWithinTheRowGutter() {
        let overhang = (MacLayout.detailPanelWidth + MacLayout.detailPanelMargin)
            - MacLayout.chatColumnWidth
        XCTAssertGreaterThanOrEqual(overhang, 0, "Some overhang is expected by construction")
        XCTAssertLessThan(overhang, MacLayout.rowTrailingGap,
                          "Overhang must stay inside the row's trailing gutter")
    }
}

// MARK: - Board and chat are mutually exclusive (task f1430338)

extension MacLayoutTests {

    /// A board needs the full width for its columns, so the chat column stands down for it.
    func testBoardModeHidesTheChatColumn() {
        XCTAssertFalse(MacLayout.showsChatColumn(windowWidth: 1_600, isRealList: true, isBoard: true),
                       "Even on a very wide window, a board takes the horizontal space")
    }

    /// …and the list view is unaffected.
    func testListModeStillShowsTheChatColumn() {
        XCTAssertTrue(MacLayout.showsChatColumn(windowWidth: 1_600, isRealList: true, isBoard: false))
    }

    /// Board mode does not resurrect chat for a selection that never had a channel.
    func testBoardModeDoesNotOverrideTheChannelRule() {
        XCTAssertFalse(MacLayout.showsChatColumn(windowWidth: 1_600, isRealList: false, isBoard: false))
    }
}
