//  MacTaskSearchTests.swift
//  Astrid for Mac — Task 36587d3d: full-text task search across all tasks incl. completed.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacTaskSearchTests: XCTestCase {

    private func task(_ id: String, _ title: String, notes: String = "", done: Bool = false,
                      created: TimeInterval = 0) -> Task {
        var t = Task(id: id, title: title, completed: done)
        t.description = notes
        t.createdAt = Date(timeIntervalSince1970: created)
        return t
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(MacTaskSearch.matches([task("1", "Buy milk")], query: "").isEmpty)
        XCTAssertTrue(MacTaskSearch.matches([task("1", "Buy milk")], query: "   ").isEmpty)
    }

    func testMatchesTitleAndNotesCaseInsensitive() {
        let tasks = [task("1", "Buy MILK"), task("2", "Call bank", notes: "about the mortgage")]
        XCTAssertEqual(MacTaskSearch.matches(tasks, query: "milk").map(\.id), ["1"])
        XCTAssertEqual(MacTaskSearch.matches(tasks, query: "MORTGAGE").map(\.id), ["2"])
    }

    func testAllTermsMustMatch() {
        let tasks = [task("1", "Buy milk and bread"), task("2", "Buy milk")]
        XCTAssertEqual(MacTaskSearch.matches(tasks, query: "buy bread").map(\.id), ["1"])
    }

    func testIncludesCompletedButSortsThemLast() {
        let tasks = [task("done", "milk", done: true, created: 5), task("open", "milk", done: false, created: 1)]
        // Both match; incomplete comes first even though it's older.
        XCTAssertEqual(MacTaskSearch.matches(tasks, query: "milk").map(\.id), ["open", "done"])
    }
}
#endif
