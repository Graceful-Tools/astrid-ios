import XCTest
@testable import Astrid_App

/// Regression for the production bug: TaskService.syncPendingOperations dropped
/// repeatingData (sent nil) when replaying an offline-created/edited task, which
/// erased custom weekly/monthly/yearly recurrence after sync. Also, the
/// local-vs-server divergence check ignored recurrence, so a recurrence-only
/// edit wouldn't be pushed.
///
/// The sync wire-payload + divergence logic are extracted as pure helpers so
/// this is unit-testable (TaskService itself isn't mockable — hardcoded client).
final class TaskServiceSyncRecurrenceTests: XCTestCase {

    private func customTask() -> Task {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1, endCondition: "never",
            weekdays: ["monday", "wednesday", "friday"]
        )
        return Task(id: "temp_1", title: "gym", repeating: .custom, repeatingData: pattern,
                    priority: .none, isPrivate: true, completed: false)
    }

    func testSyncUpdateRequestCarriesRepeatingData() {
        let task = customTask()
        let req = TaskService.makeSyncUpdateRequest(task: task, dueDateTimeString: nil, listIds: nil)
        XCTAssertEqual(req.repeating, "custom")
        XCTAssertEqual(req.repeatingData?.weekdays, ["monday", "wednesday", "friday"],
                       "the offline-replay update must carry repeatingData, not nil")
    }

    func testDivergenceDetectsRecurrenceChange() {
        let local = customTask()
        // Server came back as a plain (non-repeating) task — recurrence was lost.
        var server = local
        server.repeating = .never
        server.repeatingData = nil
        XCTAssertTrue(TaskService.taskDiffersForSync(local: local, server: server),
                      "a recurrence difference must trigger a follow-up update push")
    }

    func testDivergenceFalseWhenRecurrenceMatches() {
        let local = customTask()
        let server = local
        XCTAssertFalse(TaskService.taskDiffersForSync(local: local, server: server))
    }
}
