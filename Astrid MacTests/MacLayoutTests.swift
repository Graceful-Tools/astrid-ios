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

// MARK: - Detail pop-out width reservation (task f993dbe0)

extension MacLayoutTests {

    /// The task list must stay WIDER than the detail panel, so the arrow meets the row's trailing
    /// edge instead of the rows disappearing under a floating panel.
    func testTaskListStaysWiderThanTheDetailPanel() {
        let width = MacLayout.taskListWidth(contentWidth: 1200, popoutVisible: true)
        XCTAssertEqual(width, 1200 - MacLayout.detailPopoutWidth, accuracy: 0.001)
        XCTAssertGreaterThan(width, MacLayout.detailPopoutWidth,
                             "The list column must be wider than the detail pop-out")
    }

    func testFullWidthWhenNoPopout() {
        XCTAssertEqual(MacLayout.taskListWidth(contentWidth: 900, popoutVisible: false), 900)
    }

    /// Too narrow to fit both: keep the floating behaviour rather than squeezing the list.
    func testNarrowWindowDoesNotSqueezeTheList() {
        XCTAssertFalse(MacLayout.reservesDetailSpace(contentWidth: 700, popoutVisible: true))
        XCTAssertEqual(MacLayout.taskListWidth(contentWidth: 700, popoutVisible: true), 700)
    }

    func testWideWindowReservesSpace() {
        XCTAssertTrue(MacLayout.reservesDetailSpace(contentWidth: 1200, popoutVisible: true))
    }

    func testPopoutWidthMatchesTheRenderedPanel() {
        // 380 panel + 12 arrow + 14 trailing inset — keep in sync with taskDetailPopout.
        XCTAssertEqual(MacLayout.detailPopoutWidth, 406)
    }
}
