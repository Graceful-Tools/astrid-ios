import XCTest
@testable import Astrid_App

/// AITD-668 — "Task row format on profile not the same as normal row format. Should use same row
/// format (eg checkbox)."
///
/// The profile drew its tasks with `CompactTaskRow`, a reminder-card row whose checkbox did
/// nothing. It now draws `TaskRowView` and completes through `TaskService`. The profile's tasks are
/// a server snapshot taken when the profile loaded, so a working checkbox is only half the fix:
/// the row has to show the task's LIVE state, or a tick on the profile never shows on the profile.
final class UserProfileSharedTaskRowsTests: XCTestCase {

    func testRowsPreferTheLiveCopyOfATask() {
        let snapshot = TestHelpers.createTestTask(id: "a", title: "Old title", completed: false)
        let live = TestHelpers.createTestTask(id: "a", title: "Old title", completed: true)

        let rows = UserProfileView.sharedTaskRows(profileTasks: [snapshot], liveTasks: [live])

        XCTAssertEqual(rows.map(\.id), ["a"])
        XCTAssertTrue(rows[0].completed, "a task completed from the profile row must show as completed there")
    }

    func testRowsKeepTheProfileOrderAndFallBackToTheSnapshot() {
        let first = TestHelpers.createTestTask(id: "1", title: "First")
        let second = TestHelpers.createTestTask(id: "2", title: "Second")
        let third = TestHelpers.createTestTask(id: "3", title: "Third")
        let liveSecond = TestHelpers.createTestTask(id: "2", title: "Second, renamed")
        let unrelated = TestHelpers.createTestTask(id: "x", title: "Not on the profile")

        let rows = UserProfileView.sharedTaskRows(profileTasks: [first, second, third],
                                                  liveTasks: [unrelated, liveSecond])

        XCTAssertEqual(rows.map(\.id), ["1", "2", "3"], "the profile decides which tasks and in what order")
        XCTAssertEqual(rows.map(\.title), ["First", "Second, renamed", "Third"])
    }
}
