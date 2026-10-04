//  MacTaskSearchTests.swift
//  Astrid for Mac — Task 36587d3d: task search across all tasks.
//
//  The Mac's own search (every word anywhere, completed included, newest first) was replaced by
//  iOS's — Jon 2026-10-03: on disagreement follow iOS — and since AITD-459 astrid-core answers it
//  (`searchTasks`, through `TaskSearchModel`). What differs from the old Mac search is pinned in
//  `MacFollowsIOSTests`; these are the parts that did not change.

#if os(macOS)
import XCTest
import Combine
@testable import Astrid_Mac

@MainActor
final class MacTaskSearchTests: XCTestCase {

    private func task(_ id: String, _ title: String, notes: String = "") -> Task {
        var t = Task(id: id, title: title, completed: false)
        t.description = notes
        return t
    }

    private func results(_ tasks: [Task], query: String) async throws -> [String] {
        let model = TaskSearchModel(session: try CoreSearchFixture.session(seeding: tasks),
                                    tasksChanged: Empty().eraseToAnyPublisher())
        await model.search(query)
        return model.resultIds
    }

    func testEmptyQueryReturnsNothing() async throws {
        let found = try await results([task("1", "Buy milk")], query: "")
        XCTAssertTrue(found.isEmpty)
    }

    func testMatchesTitleAndNotesCaseInsensitive() async throws {
        let tasks = [task("1", "Buy MILK"), task("2", "Call bank", notes: "about the mortgage")]
        let milk = try await results(tasks, query: "milk")
        XCTAssertEqual(milk, ["1"])
        let mortgage = try await results(tasks, query: "MORTGAGE")
        XCTAssertEqual(mortgage, ["2"])
    }
}
#endif
