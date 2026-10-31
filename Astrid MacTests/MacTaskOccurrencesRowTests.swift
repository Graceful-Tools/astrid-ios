//  MacTaskOccurrencesRowTests.swift
//  Regression guard for AITD-491 — the occurrence links in the Mac's task details. The rule
//  (`TaskOccurrences`) is shared with iOS and pinned by iOS's TaskOccurrencesTests; these hold
//  where the Mac puts the row.

import XCTest
@testable import Astrid_Mac

final class MacTaskOccurrencesRowTests: XCTestCase {

    private func rows(_ mode: TaskDisplayMode, links: Bool) -> [MacTaskFieldRow] {
        MacTaskFields.rows(showsTitle: true, displayMode: mode, isInProject: true,
                           hasOccurrenceLinks: links)
    }

    func testShownInBothDisplayModesWhenTheTaskHasALink() {
        XCTAssertTrue(rows(.list, links: true).contains(.occurrences))
        XCTAssertTrue(rows(.project, links: true).contains(.occurrences))
    }

    func testAbsentForATaskWithNoLinks() {
        XCTAssertFalse(rows(.list, links: false).contains(.occurrences))
        XCTAssertFalse(rows(.project, links: false).contains(.occurrences))
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true, displayMode: .list).contains(.occurrences))
    }

    func testSitsAfterWaitingOnAndBeforeTheDescription() {
        // Board state sits after Lists in project mode too since AITD-555.
        XCTAssertEqual(rows(.project, links: true),
                       [.title, .when, .lists, .projectState, .blockers, .occurrences, .description])
    }
}
