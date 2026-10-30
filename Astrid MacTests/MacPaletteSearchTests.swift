//  MacPaletteSearchTests.swift
//  Regression for task 5003c622 — the command palette must fuzzy-search tasks and lists
//  (open tasks only), ranked, capped, and empty for a blank query.

import XCTest
@testable import Astrid_Mac

final class MacPaletteSearchTests: XCTestCase {

    private func task(_ id: String, _ title: String, completed: Bool = false) -> Task {
        Task(id: id, title: title, completed: completed)
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(MacPaletteSearch.matchingTasks("", tasks: [task("1", "Buy milk")]).isEmpty)
        XCTAssertTrue(MacPaletteSearch.matchingLists("  ", lists: []).isEmpty)
    }

    func testTaskFuzzyMatchAndCompletedExcluded() {
        let tasks = [task("1", "Buy milk"), task("2", "Ship release"), task("3", "Milk run", completed: true)]
        let hits = MacPaletteSearch.matchingTasks("milk", tasks: tasks)
        XCTAssertTrue(hits.contains { $0.id == "1" }, "open matching task should be found")
        XCTAssertFalse(hits.contains { $0.id == "3" }, "completed tasks must be excluded")
        XCTAssertFalse(hits.contains { $0.id == "2" }, "non-matching task excluded")
    }

    func testTaskResultsAreCapped() {
        let many = (0..<20).map { task("\($0)", "alpha task \($0)") }
        XCTAssertLessThanOrEqual(MacPaletteSearch.matchingTasks("alpha", tasks: many, limit: 6).count, 6)
    }

    // AITD-565: ⌘K finds a task by its id, in any case, ahead of title matches.
    func testTaskIdentifierMatchesInAnyCaseAndRanksFirst() {
        var byId = task("1", "Fix the sync banner")
        byId.identifier = "AWTD-1405"
        let titled = task("2", "awtd-1405 follow-up")
        let other = task("3", "Buy milk")
        for query in ["awtd-1405", "AWTD-1405", " Awtd-1405 "] {
            let hits = MacPaletteSearch.matchingTasks(query, tasks: [titled, other, byId])
            XCTAssertEqual(hits.first?.id, "1", "the task with that id comes first for \(query)")
            XCTAssertEqual(hits.filter { $0.id == "1" }.count, 1, "and only once")
        }
    }

    func testTaskIdentifierMatchIsExactNotPrefix() {
        var t = task("1", "Something")
        t.identifier = "AWTD-14050"
        XCTAssertFalse(MacPaletteSearch.matchingTasks("awtd-1405", tasks: [t]).contains { $0.id == "1" })
    }

    func testEmptyListQueryReturnsNothing() {
        // matchingLists shares matchingTasks' ranking; verify the empty-query guard here too.
        XCTAssertTrue(MacPaletteSearch.matchingLists("", lists: []).isEmpty)
    }
}
