import XCTest
@testable import Astrid_App

/// Task 76a6cfe9: active-task startup hydration is split into a bounded first
/// page (mapped synchronously) plus a background-context hydration of the rest.
/// These lock the dedup contract of the merge step so hydrating the backlog
/// never double-inserts a first-page task nor clobbers an in-flight edit.
final class StartupHydrationTests: XCTestCase {

    private func makeTask(_ id: String) -> Task {
        Task(
            id: id,
            title: id,
            description: "",
            dueDateTime: nil,
            isAllDay: false,
            priority: .none,
            isPrivate: false,
            completed: false,
            createdAt: ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        )
    }

    func test_dropsTasksAlreadyInMemory() {
        let remaining = [makeTask("a"), makeTask("b"), makeTask("c")]
        let fresh = TaskService.freshActiveTasksToAppend(
            remaining: remaining,
            alreadyLoadedIds: ["a"]
        )
        XCTAssertEqual(fresh.map { $0.id }, ["b", "c"])
    }

    func test_emptyAlreadyLoaded_keepsAll_inOrder() {
        let remaining = [makeTask("x"), makeTask("y"), makeTask("z")]
        let fresh = TaskService.freshActiveTasksToAppend(
            remaining: remaining,
            alreadyLoadedIds: []
        )
        XCTAssertEqual(fresh.map { $0.id }, ["x", "y", "z"])
    }

    func test_allAlreadyLoaded_returnsEmpty() {
        let remaining = [makeTask("a"), makeTask("b")]
        let fresh = TaskService.freshActiveTasksToAppend(
            remaining: remaining,
            alreadyLoadedIds: ["a", "b"]
        )
        XCTAssertTrue(fresh.isEmpty)
    }

    /// The union of the first page and the hydrated remainder must have no
    /// duplicate ids — the invariant a naive append would violate if the
    /// background fetch overlapped the first page.
    func test_firstPagePlusFresh_hasNoDuplicateIds() {
        let firstPage = [makeTask("a"), makeTask("b")]
        // Background fetch may re-observe first-page rows plus new ones.
        let remaining = [makeTask("a"), makeTask("b"), makeTask("c"), makeTask("d")]
        let fresh = TaskService.freshActiveTasksToAppend(
            remaining: remaining,
            alreadyLoadedIds: Set(firstPage.map { $0.id })
        )
        let combinedIds = firstPage.map { $0.id } + fresh.map { $0.id }
        XCTAssertEqual(combinedIds, ["a", "b", "c", "d"])
        XCTAssertEqual(Set(combinedIds).count, combinedIds.count, "no duplicate ids after hydration")
    }
}
