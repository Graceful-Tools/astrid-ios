//  MacTaskSearchTests.swift
//  Astrid for Mac — Task 36587d3d: task search across all tasks.
//
//  The Mac's own search (every word anywhere, completed included, newest first) was replaced by
//  iOS's, shared as `TaskSearch` — Jon 2026-10-03: on disagreement follow iOS. What differs from
//  the old Mac search is pinned in `MacFollowsIOSTests`; these are the parts that did not change.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacTaskSearchTests: XCTestCase {

    private func task(_ id: String, _ title: String, notes: String = "") -> Task {
        var t = Task(id: id, title: title, completed: false)
        t.description = notes
        return t
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(TaskSearch.results([task("1", "Buy milk")], query: "").isEmpty)
    }

    func testMatchesTitleAndNotesCaseInsensitive() {
        let tasks = [task("1", "Buy MILK"), task("2", "Call bank", notes: "about the mortgage")]
        XCTAssertEqual(TaskSearch.results(tasks, query: "milk").map(\.id), ["1"])
        XCTAssertEqual(TaskSearch.results(tasks, query: "MORTGAGE").map(\.id), ["2"])
    }
}
#endif
