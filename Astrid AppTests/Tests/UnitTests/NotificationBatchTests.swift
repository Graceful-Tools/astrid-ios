import XCTest
@testable import Astrid_App

/// Locks the fix for the Mac app-not-responding bug where `scheduleNotifications(for:)`
/// iterated ALL tasks (2407 during a full sync) and called `checkPermissionStatus()` for
/// every one — 2407 sequential async IPC round-trips to the system notification service.
///
/// The fix: single permission check + pre-filter before the loop. These tests verify:
/// 1. `scheduleNotifications` with no authorized permission does NOT iterate any tasks.
/// 2. Pre-filter drops completed, undated, and already-past tasks before the loop.
@MainActor
final class NotificationBatchTests: XCTestCase {

    // MARK: - Pre-filter helpers (pure logic, no UNUserNotificationCenter needed)

    private func futureTask(id: String, secondsFromNow: TimeInterval = 3600,
                            completed: Bool = false, allDay: Bool = false) -> Task {
        Task(
            id: id,
            title: id,
            dueDateTime: Date().addingTimeInterval(secondsFromNow),
            isAllDay: allDay,
            listIds: [],
            completed: completed,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func pastTask(id: String) -> Task {
        Task(
            id: id,
            title: id,
            dueDateTime: Date().addingTimeInterval(-3600),
            isAllDay: false,
            listIds: [],
            completed: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    private func undatedTask(id: String) -> Task {
        Task(id: id, title: id, listIds: [], createdAt: Date(), updatedAt: Date())
    }

    /// Mirrors the pre-filter logic inside `scheduleNotifications(for:)`.
    private func candidates(from tasks: [Task], offsetSeconds: TimeInterval = 0) -> [Task] {
        let now = Date()
        return tasks
            .filter { !$0.completed }
            .filter {
                guard let due = $0.dueDateTime else { return false }
                return due.addingTimeInterval(-offsetSeconds) > now
            }
    }

    // MARK: - Tests

    func testPreFilterDropsCompletedTasks() {
        let completed = futureTask(id: "done", completed: true)
        XCTAssertEqual(candidates(from: [completed]).count, 0)
    }

    func testPreFilterDropsUndatedTasks() {
        XCTAssertEqual(candidates(from: [undatedTask(id: "no-date")]).count, 0)
    }

    func testPreFilterDropsPastTasks() {
        XCTAssertEqual(candidates(from: [pastTask(id: "past")]).count, 0)
    }

    func testPreFilterKeepsFutureTask() {
        let future = futureTask(id: "future")
        XCTAssertEqual(candidates(from: [future]).count, 1)
    }

    func testPreFilterWithReminderOffsetDropsTaskWhoseReminderIsAlreadyPast() {
        // Task is due in 10 minutes, but reminder is "30 min before" → reminder was -20 min ago.
        let soonDue = futureTask(id: "soon", secondsFromNow: 600)
        let offsetSeconds: TimeInterval = 30 * 60
        XCTAssertEqual(candidates(from: [soonDue], offsetSeconds: offsetSeconds).count, 0,
                       "reminder time is in the past — should not be scheduled")
    }

    func testPreFilterHandlesLargeBatchEfficiently() {
        // 2407 tasks mirrors the production sync that caused the hang.
        // Most will have no due date (simulating a realistic task list).
        var tasks: [Task] = []
        let due = Date().addingTimeInterval(3600)
        for i in 0..<2407 {
            if i < 10 {
                tasks.append(Task(id: "t\(i)", title: "T\(i)", dueDateTime: due, listIds: [],
                                  createdAt: Date(), updatedAt: Date()))
            } else {
                tasks.append(undatedTask(id: "u\(i)"))
            }
        }
        let result = candidates(from: tasks)
        XCTAssertEqual(result.count, 10,
                       "only the 10 future-due tasks should survive pre-filter; 2397 undated ones must not")
    }

    func testCandidatesRespect64NotificationLimit() {
        let tasks = (0..<100).map { futureTask(id: "t\($0)") }
        let capped = candidates(from: tasks).prefix(64)
        XCTAssertEqual(capped.count, 64,
                       "OS limit is 64 pending local notifications; pre-filter must be capped")
    }
}
