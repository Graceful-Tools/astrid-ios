import XCTest
@testable import Astrid_App

/// Swift port of `tests/lib/task-sort.test.ts` (5 cases). iOS Task has a
/// single `dueDateTime` instead of web's separate `when`/`dueDate`, so
/// the "when: earliest due first" test uses `dueDateTime`.
final class TaskSortTests: XCTestCase {

    private func makeTask(
        id: String,
        title: String? = nil,
        priority: Task.Priority = .none,
        completed: Bool = false,
        dueDateTime: Date? = nil,
        createdAt: Date = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
    ) -> Task {
        Task(
            id: id,
            title: title ?? id,
            description: "",
            dueDateTime: dueDateTime,
            isAllDay: false,
            priority: priority,
            isPrivate: false,
            completed: completed,
            createdAt: createdAt
        )
    }

    func test_priority_highestFirst() {
        let tasks = [
            makeTask(id: "low", priority: .low),
            makeTask(id: "high", priority: .high),
            makeTask(id: "mid", priority: .medium),
        ]
        XCTAssertEqual(sortTasksForList(tasks, sortBy: "priority").map { $0.id },
                       ["high", "mid", "low"])
    }

    func test_when_earliestDueDateFirst_noDateLast() {
        let tasks = [
            makeTask(id: "b", dueDateTime: ISO8601DateFormatter().date(from: "2026-02-10T00:00:00Z")),
            makeTask(id: "a", dueDateTime: ISO8601DateFormatter().date(from: "2026-02-01T00:00:00Z")),
            makeTask(id: "none"),
        ]
        XCTAssertEqual(sortTasksForList(tasks, sortBy: "when").map { $0.id },
                       ["a", "b", "none"])
    }

    func test_auto_incompleteBeforeCompleted_thenPriorityDesc_thenDueDateAsc() {
        let tasks = [
            makeTask(id: "done-high", priority: .high, completed: true),
            makeTask(id: "open-low", priority: .low),
            makeTask(id: "open-high",
                     priority: .high,
                     dueDateTime: ISO8601DateFormatter().date(from: "2026-02-05T00:00:00Z")),
            makeTask(id: "open-high-earlier",
                     priority: .high,
                     dueDateTime: ISO8601DateFormatter().date(from: "2026-02-01T00:00:00Z")),
        ]
        XCTAssertEqual(sortTasksForList(tasks, sortBy: "auto").map { $0.id }, [
            "open-high-earlier",
            "open-high",
            "open-low",
            "done-high",
        ])
    }

    func test_manual_honorsProvidedOrder_andAppendsUnknownIdsByCreationDate() {
        let fmt = ISO8601DateFormatter()
        let tasks = [
            makeTask(id: "a", createdAt: fmt.date(from: "2026-01-01T00:00:00Z")!),
            makeTask(id: "b", createdAt: fmt.date(from: "2026-01-02T00:00:00Z")!),
            makeTask(id: "c", createdAt: fmt.date(from: "2026-01-03T00:00:00Z")!),
            makeTask(id: "d-new", createdAt: fmt.date(from: "2026-01-04T00:00:00Z")!),
        ]
        XCTAssertEqual(
            sortTasksForList(tasks, sortBy: "manual", manualOrder: ["c", "a", "b"]).map { $0.id },
            ["c", "a", "b", "d-new"]
        )
    }

    func test_manual_fallsBackToCreationOrder_whenNoManualOrderSupplied() {
        let fmt = ISO8601DateFormatter()
        let tasks = [
            makeTask(id: "late", createdAt: fmt.date(from: "2026-01-05T00:00:00Z")!),
            makeTask(id: "early", createdAt: fmt.date(from: "2026-01-01T00:00:00Z")!),
        ]
        XCTAssertEqual(sortTasksForList(tasks, sortBy: "manual", manualOrder: nil).map { $0.id },
                       ["early", "late"])
    }
}
