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

    /// Rule 8 (AITD-537): the summary is built from keys that resolve, in every unit.
    func testSummaryReadsItsKeys_AITD537() {
        func text(_ key: String) -> String {
            let value = NSLocalizedString(key, comment: "")
            XCTAssertNotEqual(value, key, "\(key) is missing")
            return value
        }
        for unit in ["days", "weeks", "months", "years"] {
            let one = MacCustomRepeat.make(interval: 1, unit: unit, endCondition: "never", endAfter: 1, endUntil: Date())
            XCTAssertEqual(MacCustomRepeat.summary(one), text("mac.repeat.every_one.\(unit)"))
            let two = MacCustomRepeat.make(interval: 2, unit: unit, endCondition: "never", endAfter: 1, endUntil: Date())
            XCTAssertEqual(MacCustomRepeat.summary(two), String(format: text("mac.repeat.every_n.\(unit)"), 2))
        }
        let weekly = text("mac.repeat.every_one.weeks")
        let times = MacCustomRepeat.make(interval: 1, unit: "weeks", endCondition: "after_occurrences", endAfter: 3, endUntil: Date())
        XCTAssertEqual(MacCustomRepeat.summary(times), String(format: text("mac.repeat.summary_times"), weekly, 3))
        let until = MacCustomRepeat.make(interval: 1, unit: "weeks", endCondition: "until_date", endAfter: 1, endUntil: Date())
        XCTAssertEqual(MacCustomRepeat.summary(until), String(format: text("mac.repeat.summary_until_date"), weekly))
    }
}
