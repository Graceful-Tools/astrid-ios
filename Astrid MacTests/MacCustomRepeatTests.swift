//  MacCustomRepeatTests.swift
//  Regression for task 1b5f2810 — the custom repeat editor must build a normalized
//  CustomRepeatingPattern and summarize it.

import XCTest
@testable import Astrid_Mac

final class MacCustomRepeatTests: XCTestCase {

    func testBasicPattern() {
        let p = MacCustomRepeat.make(interval: 2, unit: "weeks", endCondition: "never",
                                     endAfter: 10, endUntil: Date())
        XCTAssertEqual(p.type, "custom")
        XCTAssertEqual(p.unit, "weeks")
        XCTAssertEqual(p.interval, 2)
        XCTAssertEqual(p.endCondition, "never")
        XCTAssertNil(p.endAfterOccurrences)
        XCTAssertNil(p.endUntilDate)
    }

    func testAfterOccurrences() {
        let p = MacCustomRepeat.make(interval: 1, unit: "days", endCondition: "after_occurrences",
                                     endAfter: 5, endUntil: Date())
        XCTAssertEqual(p.endAfterOccurrences, 5)
        XCTAssertNil(p.endUntilDate)
    }

    func testUntilDate() {
        let d = Date(timeIntervalSince1970: 2_000_000)
        let p = MacCustomRepeat.make(interval: 3, unit: "months", endCondition: "until_date",
                                     endAfter: 5, endUntil: d)
        XCTAssertEqual(p.endUntilDate, d)
        XCTAssertNil(p.endAfterOccurrences)
    }

    func testIntervalClampedToOne() {
        let p = MacCustomRepeat.make(interval: 0, unit: "weeks", endCondition: "never",
                                     endAfter: 1, endUntil: Date())
        XCTAssertEqual(p.interval, 1)
    }

    func testSummary() {
        let weekly = MacCustomRepeat.make(interval: 1, unit: "weeks", endCondition: "never", endAfter: 1, endUntil: Date())
        XCTAssertEqual(MacCustomRepeat.summary(weekly), "Every week")
        let biweekly = MacCustomRepeat.make(interval: 2, unit: "weeks", endCondition: "never", endAfter: 1, endUntil: Date())
        XCTAssertEqual(MacCustomRepeat.summary(biweekly), "Every 2 weeks")
    }
}
