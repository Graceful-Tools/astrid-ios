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

    /// The whole design rests on this: the chat column is wide enough to CONTAIN the floating
    /// pop-out. If it ever gets narrower, the panel would spill over the task rows and the rows
    /// would have to give up width again — the behaviour this replaced.
    func testChatColumnContainsTheDetailPopout() {
        XCTAssertGreaterThanOrEqual(MacLayout.chatColumnWidth, MacLayout.detailPopoutWidth,
                                    "Chat must be at least as wide as the pop-out it hosts")
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
    func testChatColumnIsDerivedFromThePopoutNotAMagicNumber() {
        XCTAssertEqual(MacLayout.chatColumnWidth, MacLayout.detailPopoutWidth,
                       "Deriving it keeps the two in step when the panel width changes")
    }
}
