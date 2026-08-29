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

    func testDoneColumnExcludesTasksCompletedBeforeWindow() {
        let recent = completedTask(id: "recent", completedAgo: 60 * 60)       // 1h ago
        let old = completedTask(id: "old", completedAgo: 48 * 60 * 60)        // 48h ago

        let result = boardColumnTasksSorted(
            [recent, old],
            projectId: "p1",
            column: doneColumn(),
            lists: [domainList()],
            manualOrder: nil,
            recentlyCompletedWindow: .duration(amount: 1, unit: .day),
            completionFilter: "default",
            now: now
        )

        let ids = result.map { $0.id }
        XCTAssertTrue(ids.contains("recent"), "recently completed task should remain in Done")
        XCTAssertFalse(ids.contains("old"), "task completed before the window must drop off Done")
    }

    func testShowFilterKeepsAllCompletedRegardlessOfWindow() {
        let recent = completedTask(id: "recent", completedAgo: 60 * 60)
        let old = completedTask(id: "old", completedAgo: 48 * 60 * 60)

        let result = boardColumnTasksSorted(
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
}
