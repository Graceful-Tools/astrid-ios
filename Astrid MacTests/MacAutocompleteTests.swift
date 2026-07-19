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

    // Shared suggestion builder (chat + task-detail comments) — Task eda86d23.
    func testTaskSuggestionsFilterIncompleteAndQuery() {
        func t(_ id: String, _ title: String, done: Bool = false) -> Task {
            var x = Task(id: id, title: title, completed: done); return x
        }
        let tasks = [t("1", "Buy milk"), t("2", "Buy bread", done: true), t("3", "Call bank")]
        let hit = MacAutocomplete.detectTrigger(in: "see !buy")!
        let s = MacAutocomplete.suggestions(for: hit, members: [], lists: [], tasks: tasks)
        // Only incomplete tasks whose title matches "buy" → "Buy milk" (not the completed "Buy bread").
        XCTAssertEqual(s.map(\.label), ["Buy milk"])
        XCTAssertEqual(s.first?.icon, "circle")
    }

    func testSuggestionsRespectLimit() {
        let tasks = (0..<10).map { Task(id: "\($0)", title: "task \($0)", completed: false) }
        let hit = MacAutocomplete.detectTrigger(in: "!task")!
        XCTAssertEqual(MacAutocomplete.suggestions(for: hit, members: [], lists: [], tasks: tasks, limit: 6).count, 6)
    }
}
