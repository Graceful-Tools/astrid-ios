import XCTest
import Combine
@testable import Astrid_App

/// Locks the two fixes for the "My Tasks flickers during background sync" bug.
///
/// 1. `mergeAndSortTasksInBackground` sorts `Array(mergedDict.values)` — the
///    dictionary hands values out in arbitrary order and Swift's sort is not
///    stable, so rows with tied sort keys (a batch of all-day tasks due the
///    same day, identical createdAt from an import) shuffled on every
///    background refresh. The comparator must be a TOTAL order (id tie-break).
///
/// 2. `updateTasksFromSync` reassigned the `@Published tasks` array even when
///    the merged result was identical — every no-op background refresh
///    republished and re-rendered the whole list.
@MainActor
final class TaskListStabilityTests: XCTestCase {
    private struct DescriptionProbeError: Error, CustomStringConvertible, LocalizedError {
        static var descriptionReads = 0
        var description: String {
            Self.descriptionReads += 1
            return "probe-description"
        }
        var errorDescription: String? { "probe-localized" }
    }

    private func tiedTask(_ n: Int, due: Date, created: Date) -> Task {
        Task(id: "tie-\(n)", title: "T\(n)", dueDateTime: due, isAllDay: true,
             listIds: [], createdAt: created, updatedAt: created)
    }

    func testMergeSortIsDeterministicForTiedKeys() async {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let tasks = (0..<40).map { tiedTask($0, due: due, created: created) }

        // Two fetches whose payloads arrive in different orders (server
        // pagination, merge insertion history) must render identically.
        let a = await TaskService.mergeAndSortTasksInBackground(newTasks: tasks, pendingTasks: [])
        let b = await TaskService.mergeAndSortTasksInBackground(newTasks: tasks.reversed(), pendingTasks: [])
        XCTAssertEqual(a.map(\.id), b.map(\.id),
                       "tied sort keys must have a total order — arbitrary tie order shuffles rows on every background refresh")
    }

    func testMergeSortKeepsPrimaryOrdering() async {
        // The id tie-break must not disturb the real ordering: due-date
        // ascending, dated before undated, newest-created first among undated.
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let early = Task(id: "z-early", title: "early", dueDateTime: base, listIds: [],
                         createdAt: base, updatedAt: base)
        let late = Task(id: "a-late", title: "late", dueDateTime: base.addingTimeInterval(3600), listIds: [],
                        createdAt: base, updatedAt: base)
        let undatedNew = Task(id: "undated-new", title: "n", listIds: [],
                              createdAt: base.addingTimeInterval(100), updatedAt: base)
        let undatedOld = Task(id: "undated-old", title: "o", listIds: [],
                              createdAt: base, updatedAt: base)
        let sorted = await TaskService.mergeAndSortTasksInBackground(
            newTasks: [undatedOld, late, undatedNew, early], pendingTasks: [])
        XCTAssertEqual(sorted.map(\.id), ["z-early", "a-late", "undated-new", "undated-old"])
    }

    /// Backfill imports must be born completed+backdated: the old
    /// create-then-complete sequence made each history import flash as an
    /// OPEN row (sorted above the viewport by its ancient due date) for the
    /// gap between the two writes — one viewport jump per import, 20 per
    /// sync pass while the backfill drained.
    func testHistoryImportIsBornCompletedAndBackdated() async throws {
        let backdated = Date(timeIntervalSince1970: 1_288_000_000)
        let task = try await TaskService.shared.createTask(
            listIds: [], title: "history import \(UUID().uuidString)",
            source: .google, presumeCompletedAt: backdated)
        XCTAssertTrue(task.completed, "must never exist as an open row")
        XCTAssertEqual(task.completedAt, backdated)
        XCTAssertEqual(task.completedSource, "google")
    }

    func testNoOpServerRefreshDoesNotRepublishTasks() async {
        let service = TaskService.shared
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let created = Date(timeIntervalSince1970: 1_790_000_000)
        let payload = (0..<25).map { tiedTask($0, due: due, created: created) }

        await service.updateTasksFromSync(payload)

        var republishes = 0
        let cancellable = service.$tasks.dropFirst().sink { _ in republishes += 1 }
        defer { cancellable.cancel() }

        // Identical payload again — the background-sync steady state.
        await service.updateTasksFromSync(payload)
        XCTAssertEqual(republishes, 0,
                       "an unchanged server refresh must not republish the tasks array — every publish re-renders the whole list (the large-list flicker)")

        // A real change must still publish.
        var changed = payload
        changed[0].title = "renamed"
        changed[0].updatedAt = Date(timeIntervalSince1970: 1_800_000_100)
        await service.updateTasksFromSync(changed)
        XCTAssertEqual(republishes, 1, "a real change must still publish")
    }

    func testSafeErrorSummaryDoesNotTouchErrorDescription() {
        DescriptionProbeError.descriptionReads = 0
        let summary = TaskService.safeErrorSummary(DescriptionProbeError())
        XCTAssertTrue(summary.contains("probe-localized"))
        XCTAssertEqual(
            DescriptionProbeError.descriptionReads,
            0,
            "safe error logging must not evaluate Error.description (can crash for CoreData-backed NSError payloads)"
        )
    }
}
