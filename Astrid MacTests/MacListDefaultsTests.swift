//  MacListDefaultsTests.swift
//  Astrid for Mac — Task c82173ff: list new-task default settings payload + option vocabulary.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListDefaultsTests: XCTestCase {

    func testOptionValuesMatchIOS() {
        XCTAssertEqual(MacListDefaults.dueDate.map(\.value), ["none", "today", "tomorrow", "next_week", "next_month"])
        XCTAssertEqual(MacListDefaults.repeating.map(\.value), ["never", "daily", "weekly", "monthly", "yearly"])
    }

    func testUpdatesPayload() {
        let u = MacListDefaults.updates(priority: 2, dueDate: "tomorrow", repeating: "weekly")
        XCTAssertEqual(u["defaultPriority"] as? Int, 2)
        XCTAssertEqual(u["defaultDueDate"] as? String, "tomorrow")
        XCTAssertEqual(u["defaultRepeating"] as? String, "weekly")
    }
}
#endif
