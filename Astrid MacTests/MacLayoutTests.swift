//  MacLayoutTests.swift
//  Astrid for Mac — Task 23c98550: responsive 2/3-column rule mirrors the web thresholds.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacLayoutTests: XCTestCase {

    func testThresholdMirrorsWeb() {
        // Web: 3-column at window ≥1100 with a ~240pt sidebar → content ≥860.
        XCTAssertEqual(MacLayout.chatColumnContentThreshold, 1100 - 240)
    }

    func testChatColumnRule() {
        XCTAssertTrue(MacLayout.showsChatColumn(contentWidth: 900, isRealList: true), "Wide + real list → 3-col")
        XCTAssertFalse(MacLayout.showsChatColumn(contentWidth: 700, isRealList: true), "Narrow → 2-col")
        XCTAssertFalse(MacLayout.showsChatColumn(contentWidth: 900, isRealList: false),
                       "Virtual selections (My Tasks/Search) have no chat channel")
        // Boundary: exactly at the threshold is 3-col (web uses >=).
        XCTAssertTrue(MacLayout.showsChatColumn(contentWidth: 860, isRealList: true))
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
