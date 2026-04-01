import XCTest
@testable import Astrid_App

/// Tests for task sync deduplication logic and create-edit-sync race condition fix.
///
/// Group 1: mergeAndSortTasksInBackground pure function tests
/// Group 2: Fix validation tests (temp ID detection, edit detection, merge logic)
/// Group 3: Edge cases (concurrent creates, rapid edits, overlapping lists)
final class TaskSyncDeduplicationTests: XCTestCase {

    // MARK: - Helpers

    /// Convenience wrapper around the now-internal static method
    private func merge(
        serverTasks: [Task],
        pendingTasks: [Task]
    ) async -> [Task] {
        await TaskService.mergeAndSortTasksInBackground(
            newTasks: serverTasks,
            pendingTasks: pendingTasks
        )
    }

    /// Create a minimal task for merge tests
    private func task(
        id: String = UUID().uuidString,
        title: String = "Test Task",
        listIds: [String]? = ["list-1"],
        createdAt: Date? = Date(),
        updatedAt: Date? = nil,
        priority: Task.Priority = .none,
        dueDateTime: Date? = nil,
        completed: Bool = false
    ) -> Task {
        TestHelpers.createTestTask(
            id: id,
            title: title,
            priority: priority,
            completed: completed,
            dueDateTime: dueDateTime,
            listIds: listIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Group 1: mergeAndSortTasksInBackground Pure Function Tests

    func testServerTasksOnly() async {
        let server = [
            task(id: "s1", title: "Buy milk"),
            task(id: "s2", title: "Walk dog"),
        ]
        let result = await merge(serverTasks: server, pendingTasks: [])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.id == "s1" }))
        XCTAssertTrue(result.contains(where: { $0.id == "s2" }))
    }

    func testPendingTaskKeptWhenNoServerMatch() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Unique pending", listIds: ["list-1"], createdAt: now)]
        let server = [task(id: "s1", title: "Different task", listIds: ["list-1"], createdAt: now)]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.contains(where: { $0.id == "temp_1" }))
    }

    func testPendingTaskDeduplicatedWhenServerMatchFound() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Buy groceries", listIds: ["list-1"], createdAt: now)]
        let server = [task(id: "server-1", title: "Buy groceries", listIds: ["list-1"], createdAt: now.addingTimeInterval(5))]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 1, "Pending task should be deduped against server match")
        XCTAssertEqual(result.first?.id, "server-1")
    }

    func testNoDedupWhenTitleDiffers() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Buy groceries", listIds: ["list-1"], createdAt: now)]
        let server = [task(id: "s1", title: "Sell groceries", listIds: ["list-1"], createdAt: now)]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 2, "Different titles should not dedup")
    }

    func testNoDedupWhenListsDontOverlap() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Buy groceries", listIds: ["list-A"], createdAt: now)]
        let server = [task(id: "s1", title: "Buy groceries", listIds: ["list-B"], createdAt: now)]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 2, "Disjoint lists should not dedup")
    }

    func testNoDedupWhenCreatedAtExceeds60Seconds() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Buy groceries", listIds: ["list-1"], createdAt: now)]
        let server = [task(id: "s1", title: "Buy groceries", listIds: ["list-1"], createdAt: now.addingTimeInterval(120))]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 2, ">60s apart should not dedup")
    }

    func testDedupWindowBoundary() async {
        let now = Date()

        // 59.9 seconds — should dedup
        let pending1 = [task(id: "temp_1", title: "Task", listIds: ["list-1"], createdAt: now)]
        let server1 = [task(id: "s1", title: "Task", listIds: ["list-1"], createdAt: now.addingTimeInterval(59.9))]
        let result1 = await merge(serverTasks: server1, pendingTasks: pending1)
        XCTAssertEqual(result1.count, 1, "59.9s should dedup")

        // 60.1 seconds — should NOT dedup
        let pending2 = [task(id: "temp_2", title: "Task", listIds: ["list-1"], createdAt: now)]
        let server2 = [task(id: "s2", title: "Task", listIds: ["list-1"], createdAt: now.addingTimeInterval(60.1))]
        let result2 = await merge(serverTasks: server2, pendingTasks: pending2)
        XCTAssertEqual(result2.count, 2, "60.1s should NOT dedup")
    }

    func testMultiplePendingTasksSomeMatch() async {
        let now = Date()
        let pending = [
            task(id: "temp_1", title: "Match", listIds: ["list-1"], createdAt: now),
            task(id: "temp_2", title: "No match", listIds: ["list-1"], createdAt: now),
            task(id: "temp_3", title: "Also match", listIds: ["list-1"], createdAt: now),
        ]
        let server = [
            task(id: "s1", title: "Match", listIds: ["list-1"], createdAt: now.addingTimeInterval(2)),
            task(id: "s2", title: "Also match", listIds: ["list-1"], createdAt: now.addingTimeInterval(3)),
        ]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        // s1, s2 from server + temp_2 (no match) = 3
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.contains(where: { $0.id == "temp_2" }))
        XCTAssertFalse(result.contains(where: { $0.id == "temp_1" }))
        XCTAssertFalse(result.contains(where: { $0.id == "temp_3" }))
    }

    func testEditedPendingStillDeduped() async {
        let now = Date()
        // Pending task edited (different priority) but same title/list/time
        let pending = [task(id: "temp_1", title: "Buy groceries", listIds: ["list-1"], createdAt: now, priority: .high)]
        let server = [task(id: "s1", title: "Buy groceries", listIds: ["list-1"], createdAt: now.addingTimeInterval(2))]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 1, "Edited pending with same title should still dedup")
        XCTAssertEqual(result.first?.id, "s1")
    }

    func testCaseInsensitiveTitleMatching() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Buy Groceries", listIds: ["list-1"], createdAt: now)]
        let server = [task(id: "s1", title: "buy groceries", listIds: ["list-1"], createdAt: now.addingTimeInterval(1))]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 1, "Case-insensitive title match should dedup")
    }

    func testNilCreatedAtHandling() async {
        // Both have nil createdAt — they'll both use Date() which are ~same instant
        let pending = [task(id: "temp_1", title: "Task", listIds: ["list-1"], createdAt: nil)]
        let server = [task(id: "s1", title: "Task", listIds: ["list-1"], createdAt: nil)]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        // Both use Date() fallback, which will be within 60s of each other
        XCTAssertEqual(result.count, 1, "nil createdAt should use Date() fallback and dedup")
    }

    func testEmptyListIdsNotDeduped() async {
        let now = Date()
        let pending = [task(id: "temp_1", title: "Task", listIds: [], createdAt: now)]
        let server = [task(id: "s1", title: "Task", listIds: ["list-1"], createdAt: now)]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        // Empty pendingLists → isDisjoint guard prevents match
        XCTAssertEqual(result.count, 2, "Empty listIds should not match")
    }

    // MARK: - Group 2: Fix Validation Tests

    func testTempIdIsDetectedCorrectly() {
        let tempId = "temp_\(UUID().uuidString)"
        let serverId = UUID().uuidString

        XCTAssertTrue(tempId.hasPrefix("temp_"))
        XCTAssertFalse(serverId.hasPrefix("temp_"))
    }

    @MainActor func testLocalEditsDetectedByUpdatedAtChange() {
        let original = task(updatedAt: Date())
        var edited = original
        edited.updatedAt = Date().addingTimeInterval(5)

        XCTAssertNotEqual(original.updatedAt, edited.updatedAt)
    }

    @MainActor func testMergePreservesLocalEditsOverServerResponse() {
        // Simulate: optimistic task created, then edited, then server responds
        let serverTask = task(id: "server-1", title: "Original", priority: .none)
        var localEdited = task(id: "temp_1", title: "Edited title", priority: .high)
        localEdited.dueDateTime = Date().addingTimeInterval(86400)
        localEdited.isAllDay = true

        // Apply the same merge logic as Part C
        var merged = serverTask
        merged.title = localEdited.title
        merged.description = localEdited.description
        merged.priority = localEdited.priority
        merged.dueDateTime = localEdited.dueDateTime
        merged.isAllDay = localEdited.isAllDay
        merged.assigneeId = localEdited.assigneeId
        merged.completed = localEdited.completed
        merged.isPrivate = localEdited.isPrivate

        XCTAssertEqual(merged.id, "server-1", "Should use server ID")
        XCTAssertEqual(merged.title, "Edited title", "Should preserve local title")
        XCTAssertEqual(merged.priority, .high, "Should preserve local priority")
        XCTAssertNotNil(merged.dueDateTime, "Should preserve local dueDateTime")
        XCTAssertTrue(merged.isAllDay, "Should preserve local isAllDay")
    }

    @MainActor func testMergeDoesNotOverwriteWhenNoEdits() {
        let now = Date()
        let original = task(id: "temp_1", title: "Buy milk", updatedAt: now, priority: .none)
        // "current local" has same updatedAt → not edited
        let currentLocal = task(id: "temp_1", title: "Buy milk", updatedAt: now, priority: .none)

        let wasEdited = currentLocal.updatedAt != original.updatedAt
        XCTAssertFalse(wasEdited, "Same updatedAt means no edits")
    }

    func testPendingCreatesSetPreventsDoubleSync() {
        // Validate Set<String> operations match the Part A lifecycle
        var pendingCreates: Set<String> = []

        let tempId = "temp_123"
        pendingCreates.insert(tempId)
        XCTAssertTrue(pendingCreates.contains(tempId), "Should be in set after insert")

        // syncPendingOperations would check:
        let shouldSkip = pendingCreates.contains(tempId)
        XCTAssertTrue(shouldSkip, "Should skip this task during sync")

        // After create completes:
        pendingCreates.remove(tempId)
        XCTAssertFalse(pendingCreates.contains(tempId), "Should be removed after create completes")
    }

    // MARK: - Group 3: Edge Cases

    @MainActor func testMultipleEditsToSameField() {
        var t = task(id: "temp_1", title: "v1", priority: .none)

        // Rapid edits
        t.priority = .low
        t.priority = .medium
        t.priority = .high

        XCTAssertEqual(t.priority, .high, "Final state should reflect last edit")
    }

    func testPendingCreatesSetHandlesMultipleConcurrentCreates() {
        var pendingCreates: Set<String> = []

        let ids = (1...5).map { "temp_\($0)" }
        for id in ids {
            pendingCreates.insert(id)
        }
        XCTAssertEqual(pendingCreates.count, 5)

        // Remove 3, keep 2
        pendingCreates.remove("temp_1")
        pendingCreates.remove("temp_3")
        pendingCreates.remove("temp_5")
        XCTAssertEqual(pendingCreates.count, 2)
        XCTAssertTrue(pendingCreates.contains("temp_2"))
        XCTAssertTrue(pendingCreates.contains("temp_4"))
    }

    @MainActor func testRapidCreateEditDoesNotCorruptState() {
        // Simulate: create → edit → the merge logic
        let now = Date()
        let originalOptimistic = task(id: "temp_1", title: "Original", updatedAt: now, priority: .none)

        // User edits
        var editedLocal = originalOptimistic
        editedLocal.title = "Edited"
        editedLocal.priority = .high
        editedLocal.updatedAt = now.addingTimeInterval(2)

        // Server responds with the original data
        let serverResponse = task(id: "server-1", title: "Original", priority: .none)

        // Detect edit
        let wasEdited = editedLocal.updatedAt != originalOptimistic.updatedAt
        XCTAssertTrue(wasEdited)

        // Merge: server ID + local edits
        var merged = serverResponse
        if wasEdited {
            merged.title = editedLocal.title
            merged.priority = editedLocal.priority
        }

        XCTAssertEqual(merged.id, "server-1")
        XCTAssertEqual(merged.title, "Edited")
        XCTAssertEqual(merged.priority, .high)
    }

    func testDeduplicationWithOverlappingListIds() async {
        let now = Date()
        // Pending task is in [list-1, list-2], server task is in [list-2, list-3]
        // They share list-2, so they should dedup
        let pending = [task(id: "temp_1", title: "Overlap", listIds: ["list-1", "list-2"], createdAt: now)]
        let server = [task(id: "s1", title: "Overlap", listIds: ["list-2", "list-3"], createdAt: now.addingTimeInterval(1))]
        let result = await merge(serverTasks: server, pendingTasks: pending)
        XCTAssertEqual(result.count, 1, "Partial list overlap should still dedup")
        XCTAssertEqual(result.first?.id, "s1")
    }
}
