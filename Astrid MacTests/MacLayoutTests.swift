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
