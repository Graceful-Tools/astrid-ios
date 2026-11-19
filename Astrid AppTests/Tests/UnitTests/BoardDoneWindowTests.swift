import XCTest
@testable import Astrid_App

/// The board's Done column must honor the list's `recentlyCompletedWindow`,
/// matching the web (`project-status-board.tsx`). Previously iOS showed ALL
/// completed tasks in Done forever, so an old completed task stayed on the
/// board indefinitely while it had dropped off the web's Done column.
final class BoardDoneWindowTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func domainList() -> TaskList {
        var list = TaskList(id: "p1-list", name: "List")
        list.projectId = "p1"
        list.listType = "regular"
        return list
    }

    private func doneColumn() -> ProjectBoardColumn {
        ProjectBoardColumn(id: VIRTUAL_DONE_COLUMN_ID, name: "Done",
                           description: "", kind: .done)
    }

    private func completedTask(id: String, completedAgo: TimeInterval) -> Task {
        Task(id: id, title: id, lists: [domainList()],
             completed: true, updatedAt: now.addingTimeInterval(-completedAgo))
    }

    func testShowFilterKeepsAllCompletedRegardlessOfWindow() {
        let recent = completedTask(id: "recent", completedAgo: 60 * 60)
        let old = completedTask(id: "old", completedAgo: 48 * 60 * 60)

        let result = CoreBoardFixture.columnTasks(
            [recent, old],
            projectId: "p1",
            column: doneColumn(),
            lists: [domainList()],
            manualOrder: nil,
            recentlyCompletedWindow: .duration(amount: 1, unit: .day),
            completionFilter: "show",
            now: now
        )

        let ids = Set(result.map { $0.id })
        XCTAssertEqual(ids, ["recent", "old"], "'show' filter keeps every completed task")
    }

    /// Done is newest first by when each card was finished — `completedAt`, else `updatedAt` —
    /// whatever the manual order says (Jon, 2026-11-19; astrid-core CONTRACTS D43).
    func testDoneIsNewestFirstWhateverTheManualOrder_doneDatePill() {
        var oldest = completedTask(id: "oldest", completedAgo: 60 * 60)
        oldest.completedAt = now.addingTimeInterval(-72 * 60 * 60)
        var newest = completedTask(id: "newest", completedAgo: 30 * 24 * 60 * 60)
        newest.completedAt = now.addingTimeInterval(-10 * 60)
        let legacy = completedTask(id: "legacy", completedAgo: 24 * 60 * 60)

        let result = CoreBoardFixture.columnTasks(
            [oldest, newest, legacy],
            projectId: "p1",
            column: doneColumn(),
            lists: [domainList()],
            manualOrder: ["oldest", "legacy", "newest"],
            completionFilter: "show",
            now: now
        )

        XCTAssertEqual(result.map { $0.id }, ["newest", "legacy", "oldest"])
    }
}
