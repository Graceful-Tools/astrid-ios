//  MacAutocompleteTests.swift
//  Regression for task cc67a3a5 — @/#/! trigger detection + insertion.

import XCTest
@testable import Astrid_Mac

final class MacAutocompleteTests: XCTestCase {

    func testDetectsMentionAtStart() {
        let hit = MacAutocomplete.detectTrigger(in: "@jo")
        XCTAssertEqual(hit, MacAutocompleteHit(kind: .mention, triggerOffset: 0, search: "jo"))
    }

    func testDetectsListAfterWhitespace() {
        let hit = MacAutocomplete.detectTrigger(in: "hey #wor")
        XCTAssertEqual(hit?.kind, .list)
        XCTAssertEqual(hit?.search, "wor")
    }

    func testRightmostTriggerWins() {
        let hit = MacAutocomplete.detectTrigger(in: "@bob then !ta")
        XCTAssertEqual(hit?.kind, .task)
        XCTAssertEqual(hit?.search, "ta")
    }

    func testNoTriggerWhenSpaceAfter() {
        XCTAssertNil(MacAutocomplete.detectTrigger(in: "email me@ later"))
    }

    func testTriggerMustFollowWhitespace() {
        // '#' glued to a word (no leading space) is not a trigger.
        XCTAssertNil(MacAutocomplete.detectTrigger(in: "issue#42"))
    }

    func testInsertReplacesToken() {
        let hit = MacAutocomplete.detectTrigger(in: "hey #wor")!
        XCTAssertEqual(MacAutocomplete.insert(label: "Work", into: "hey #wor", hit: hit), "hey #Work ")
    }
}
