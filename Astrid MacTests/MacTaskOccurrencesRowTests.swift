//  MacTaskOccurrencesRowTests.swift
//  Regression guard for AITD-491 — the occurrence links in the Mac's task details. The rule
//  (`TaskOccurrences`) is shared with iOS and pinned by iOS's TaskOccurrencesTests; these hold
//  where the Mac puts the row.

import XCTest
@testable import Astrid_Mac

final class MacTaskOccurrencesRowTests: XCTestCase {

    private func rows(links: Bool) -> [MacTaskFieldRow] {
        MacTaskFields.rows(showsTitle: true, isInProject: true,
                           hasOccurrenceLinks: links)
    }

    func testShownWhenTheTaskHasALink() {
        XCTAssertTrue(rows(links: true).contains(.occurrences))
    }

    func testAbsentForATaskWithNoLinks() {
        XCTAssertFalse(rows(links: false).contains(.occurrences))
        XCTAssertFalse(MacTaskFields.rows(showsTitle: true).contains(.occurrences))
    }

    func testSitsAfterWaitingOnAndBeforeTheDescription() {
        let ordered = rows(links: true)
        XCTAssertEqual(Array(ordered.suffix(3)), [.blockers, .occurrences, .description])
    }
}
