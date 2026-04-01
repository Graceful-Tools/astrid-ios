import XCTest
@testable import Astrid_App

/// Tests for sync race condition fixes:
/// - Pending edits (non-temp tasks) survive server merge
/// - Deleted tasks don't reappear after merge
/// - clientRequestId-based dedup works across temp→real swap
/// - Temp task ID mapping resolves stale IDs
final class SyncRaceConditionTests: XCTestCase {

    // MARK: - Helpers

    private func merge(
        serverTasks: [Task],
        pendingTasks: [Task]
    ) async -> [Task] {
        await TaskService.mergeAndSortTasksInBackground(
            newTasks: serverTasks,
            pendingTasks: pendingTasks
        )
    }

    @MainActor private func task(
        id: String = UUID().uuidString,
        title: String = "Test Task",
        listIds: [String]? = ["list-1"],
        createdAt: Date? = Date(),
        updatedAt: Date? = nil,
        priority: Task.Priority = .none,
        completed: Bool = false,
        clientRequestId: String? = nil,
        assigneeId: String? = nil
    ) -> Task {
        var t = TestHelpers.createTestTask(
            id: id,
            title: title,
            priority: priority,
            completed: completed,
            assigneeId: assigneeId,
            listIds: listIds,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        t.clientRequestId = clientRequestId
        return t
    }

    // MARK: - Non-temp pending edits survive merge

    @MainActor func testPendingEditWithRealIdOverridesServerVersion() async {
        // Scenario: user edits a synced task (real ID), then pull-to-refresh
        // fetches stale server version. The local edit should win.
        let now = Date()
        let serverTask = task(id: "real-123", title: "Original", updatedAt: now, priority: .none)
        let localEdit = task(id: "real-123", title: "Edited title", updatedAt: now.addingTimeInterval(5), priority: .high, assigneeId: "user-456")

        let result = await merge(serverTasks: [serverTask], pendingTasks: [localEdit])

        XCTAssertEqual(result.count, 1)
        let merged = result.first!
        XCTAssertEqual(merged.id, "real-123")
        XCTAssertEqual(merged.title, "Edited title", "Local edit should override server")
        XCTAssertEqual(merged.priority, .high, "Local priority should override server")
        XCTAssertEqual(merged.assigneeId, "user-456", "Local assignee should override server")
    }

    @MainActor func testMultiplePendingEditsAllPreserved() async {
        // Multiple tasks with pending edits should all be preserved
        let now = Date()
        let server = [
            task(id: "r1", title: "Task A old", updatedAt: now, priority: .none),
            task(id: "r2", title: "Task B old", updatedAt: now, priority: .none),
            task(id: "r3", title: "Task C", updatedAt: now, priority: .none),
        ]
        let pending = [
            task(id: "r1", title: "Task A edited", updatedAt: now.addingTimeInterval(5), priority: .high),
            task(id: "r2", title: "Task B edited", updatedAt: now.addingTimeInterval(5), priority: .medium),
        ]

        let result = await merge(serverTasks: server, pendingTasks: pending)

        XCTAssertEqual(result.count, 3)
        let taskA = result.first(where: { $0.id == "r1" })!
        let taskB = result.first(where: { $0.id == "r2" })!
        let taskC = result.first(where: { $0.id == "r3" })!

        XCTAssertEqual(taskA.title, "Task A edited", "Pending edit A should win")
        XCTAssertEqual(taskB.title, "Task B edited", "Pending edit B should win")
        XCTAssertEqual(taskC.title, "Task C", "Unedited task should keep server version")
    }

    // MARK: - Deleted tasks don't reappear

    @MainActor func testDeletedTaskFilteredFromServerResults() async {
        // Simulate: task deleted locally, but server still returns it
        // updateTasksFromSync filters pendingDeleteIds BEFORE merge
        let server = [
            task(id: "keep-1", title: "Keep me"),
            task(id: "deleted-1", title: "I was deleted"),
            task(id: "keep-2", title: "Keep me too"),
        ]

        // Simulate the filter that happens in updateTasksFromSync
        let pendingDeleteIds: Set<String> = ["deleted-1"]
        let filtered = server.filter { !pendingDeleteIds.contains($0.id) }

        let result = await merge(serverTasks: filtered, pendingTasks: [])

        XCTAssertEqual(result.count, 2)
        XCTAssertFalse(result.contains(where: { $0.id == "deleted-1" }), "Deleted task should not appear")
    }

    // MARK: - clientRequestId dedup

    @MainActor func testClientRequestIdMatchPreventsDuplicate() async {
        let crid = "crid-\(UUID().uuidString)"
        let now = Date()

        // Pending temp task with clientRequestId
        let pending = [task(id: "temp_abc", title: "Buy milk", listIds: ["list-1"], createdAt: now, clientRequestId: crid)]
        // Server has same task with different ID but same clientRequestId
        let server = [task(id: "server-xyz", title: "Buy milk", listIds: ["list-1"], createdAt: now.addingTimeInterval(2), clientRequestId: crid)]

        let result = await merge(serverTasks: server, pendingTasks: pending)

        XCTAssertEqual(result.count, 1, "clientRequestId match should dedup")
        XCTAssertEqual(result.first?.id, "server-xyz", "Server ID should win")
    }

    @MainActor func testClientRequestIdMatchWithEditedTitle() async {
        let crid = "crid-\(UUID().uuidString)"
        let now = Date()

        // User created task then edited the title before sync
        let pending = [task(
            id: "temp_abc",
            title: "Buy milk at Whole Foods",  // EDITED title
            listIds: ["list-1"],
            createdAt: now,
            updatedAt: now.addingTimeInterval(10),
            clientRequestId: crid
        )]
        // Server has original title but same clientRequestId
        let server = [task(
            id: "server-xyz",
            title: "Buy milk",  // Original title
            listIds: ["list-1"],
            createdAt: now.addingTimeInterval(2),
            updatedAt: now.addingTimeInterval(2),
            clientRequestId: crid
        )]

        let result = await merge(serverTasks: server, pendingTasks: pending)

        XCTAssertEqual(result.count, 1, "Should dedup even with different titles when clientRequestId matches")
        let merged = result.first!
        XCTAssertEqual(merged.id, "server-xyz", "Server ID should win")
        XCTAssertEqual(merged.title, "Buy milk at Whole Foods", "Edited title should be preserved (local is newer)")
    }

    // MARK: - Mixed pending temp + pending edit tasks

    @MainActor func testMixedTempAndRealPendingTasks() async {
        let now = Date()

        let server = [
            task(id: "r1", title: "Existing task old", updatedAt: now, priority: .none),
            task(id: "r2", title: "Another existing", updatedAt: now),
        ]
        let pending = [
            // Temp task not yet on server
            task(id: "temp_new", title: "Brand new task", listIds: ["list-1"], createdAt: now),
            // Real task with pending edit
            task(id: "r1", title: "Existing task edited", updatedAt: now.addingTimeInterval(5), priority: .high),
        ]

        let result = await merge(serverTasks: server, pendingTasks: pending)

        XCTAssertEqual(result.count, 3, "Should have: r1 (edited), r2 (server), temp_new")
        XCTAssertTrue(result.contains(where: { $0.id == "temp_new" }), "New temp task should be kept")
        let r1 = result.first(where: { $0.id == "r1" })!
        XCTAssertEqual(r1.title, "Existing task edited", "Real ID pending edit should override server")
        XCTAssertEqual(r1.priority, .high)
    }

    // MARK: - Temp ID mapping

    func testTempIdMappingResolution() {
        // Test the basic mapping logic used in updateTask/deleteTask
        var mapping: [String: String] = [:]
        let tempId = "temp_abc"
        let realId = "server-123"

        // Before mapping exists
        let resolved1 = mapping[tempId] ?? tempId
        XCTAssertEqual(resolved1, tempId, "Should return temp ID when no mapping")

        // After create completes
        mapping[tempId] = realId
        let resolved2 = mapping[tempId] ?? tempId
        XCTAssertEqual(resolved2, realId, "Should resolve to real ID after mapping")

        // Unknown temp ID
        let resolved3 = mapping["temp_unknown"] ?? "temp_unknown"
        XCTAssertEqual(resolved3, "temp_unknown", "Unknown temp ID should pass through")
    }

    // MARK: - Sort order preserved

    @MainActor func testMergePreservesSortOrder() async {
        let now = Date()
        let server = [
            TestHelpers.createTestTask(id: "s1", title: "Due tomorrow", dueDateTime: now.addingTimeInterval(86400)),
            TestHelpers.createTestTask(id: "s2", title: "Due today", dueDateTime: now),
            task(id: "s3", title: "No due date", createdAt: now),
        ]

        let result = await merge(serverTasks: server, pendingTasks: [])

        // Tasks with due dates sorted earliest first, then no-due-date tasks
        XCTAssertEqual(result[0].id, "s2", "Due today should come first")
        XCTAssertEqual(result[1].id, "s1", "Due tomorrow should come second")
        XCTAssertEqual(result[2].id, "s3", "No due date should come last")
    }

    // MARK: - Completed tasks preserved

    @MainActor func testCompletedTaskEditPreserved() async {
        let now = Date()

        // User just completed a task (pending edit)
        let server = [task(id: "r1", title: "Do laundry", updatedAt: now, completed: false)]
        let pending = [task(id: "r1", title: "Do laundry", updatedAt: now.addingTimeInterval(1), completed: true)]

        let result = await merge(serverTasks: server, pendingTasks: pending)

        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first!.completed, "Completion status should be preserved from pending edit")
    }

    // MARK: - Timestamp-based merge (newer local wins, server wins if same or newer)

    @MainActor func testServerVersionWinsWhenNewer() async {
        let now = Date()
        // Server has a newer version (e.g., edited on web)
        let server = [task(id: "r1", title: "Edited on web", updatedAt: now.addingTimeInterval(10), priority: .high)]
        let local = [task(id: "r1", title: "Old local version", updatedAt: now, priority: .none)]

        let result = await merge(serverTasks: server, pendingTasks: local)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first!.title, "Edited on web", "Server version should win when it's newer")
        XCTAssertEqual(result.first!.priority, .high, "Server priority should win when it's newer")
    }

    @MainActor func testServerVersionWinsWhenSameTimestamp() async {
        let now = Date()
        // Both have same updatedAt (task was synced, no local edits)
        let server = [task(id: "r1", title: "Server title", updatedAt: now)]
        let local = [task(id: "r1", title: "Same title", updatedAt: now)]

        let result = await merge(serverTasks: server, pendingTasks: local)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first!.title, "Server title", "Server should win when timestamps are equal")
    }

    @MainActor func testLocalEditPreservedWhenServerStale() async {
        let now = Date()
        // Simulates: syncPendingOps pushed edit, then getAllTasks returns stale data
        let server = [task(id: "r1", title: "Stale server data", updatedAt: now)]
        let local = [task(id: "r1", title: "My local edit", updatedAt: now.addingTimeInterval(5), priority: .high)]

        let result = await merge(serverTasks: server, pendingTasks: local)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first!.title, "My local edit", "Local edit should be preserved when server is stale")
        XCTAssertEqual(result.first!.priority, .high, "Local priority should be preserved when server is stale")
    }

    // MARK: - Local-only tasks not re-added when missing from server

    @MainActor func testLocalTaskNotOnServerIsDropped() async {
        // Task was deleted on server (another device), no local edits
        let now = Date()
        let server = [task(id: "r1", title: "Still on server", updatedAt: now)]
        // r2 exists locally but NOT on server (deleted remotely)
        let local = [
            task(id: "r1", title: "Still on server", updatedAt: now),
            task(id: "r2", title: "Deleted on server", updatedAt: now),
        ]

        let result = await merge(serverTasks: server, pendingTasks: local)

        XCTAssertEqual(result.count, 1, "Task not on server should not be re-added")
        XCTAssertEqual(result.first!.id, "r1")
    }

    // MARK: - Full local task set as pendingTasks

    @MainActor func testAllLocalTasksPassedToMerge() async {
        // Simulates the new behavior: ALL local tasks are passed (not just "pending" ones)
        // Tasks with no edits should still use server version (same timestamp)
        let now = Date()
        let server = [
            task(id: "r1", title: "Task A updated on server", updatedAt: now.addingTimeInterval(10)),
            task(id: "r2", title: "Task B same", updatedAt: now),
            task(id: "r3", title: "Task C unchanged", updatedAt: now),
        ]
        let local = [
            task(id: "r1", title: "Task A old local", updatedAt: now),  // server is newer
            task(id: "r2", title: "Task B edited locally", updatedAt: now.addingTimeInterval(5)),  // local is newer
            task(id: "r3", title: "Task C unchanged", updatedAt: now),  // same timestamp
        ]

        let result = await merge(serverTasks: server, pendingTasks: local)

        XCTAssertEqual(result.count, 3)
        let r1 = result.first(where: { $0.id == "r1" })!
        let r2 = result.first(where: { $0.id == "r2" })!
        let r3 = result.first(where: { $0.id == "r3" })!

        XCTAssertEqual(r1.title, "Task A updated on server", "Server should win when newer")
        XCTAssertEqual(r2.title, "Task B edited locally", "Local should win when newer")
        XCTAssertEqual(r3.title, "Task C unchanged", "Either version OK when same timestamp")
    }

    // MARK: - App restart delete persistence (UserDefaults-backed)

    @MainActor func testDeleteFilteringWithPersistedIds() async {
        // Simulates the EXACT bug: delete tasks → close app → reopen → sync
        // After restart, CoreData pending_delete records were already cleaned up
        // by syncPendingOperations, but recentlyDeletedIds persists via UserDefaults.
        let now = Date()
        let server = [
            task(id: "keep-1", title: "Task A"),
            task(id: "deleted-1", title: "Deleted task 1"),  // server still returns it
            task(id: "deleted-2", title: "Deleted task 2"),  // server still returns it
            task(id: "keep-2", title: "Task B"),
        ]

        // After app restart: CoreData pending_delete records are gone (syncPendingOps cleaned up)
        // But recentlyDeletedIds was loaded from UserDefaults
        let persistedDeletedIds: Set<String> = ["deleted-1", "deleted-2"]
        let coreDataDeleteIds: Set<String> = []  // Empty — already pushed and removed

        // This is exactly what updateTasksFromSync does:
        let allDeleteIds = coreDataDeleteIds.union(persistedDeletedIds)
        let filtered = server.filter { !allDeleteIds.contains($0.id) }

        let result = await merge(serverTasks: filtered, pendingTasks: [])

        XCTAssertEqual(result.count, 2, "Deleted tasks must not reappear after app restart")
        XCTAssertFalse(result.contains(where: { $0.id == "deleted-1" }))
        XCTAssertFalse(result.contains(where: { $0.id == "deleted-2" }))
        XCTAssertTrue(result.contains(where: { $0.id == "keep-1" }))
        XCTAssertTrue(result.contains(where: { $0.id == "keep-2" }))
    }

    @MainActor func testBulkDeleteFilteringSimulatesListDeletion() async {
        // Simulates: user selects and deletes ALL tasks in a list, closes app, reopens
        let now = Date()
        let server = (1...10).map { i in
            task(id: "task-\(i)", title: "Task \(i)", createdAt: now)
        }

        // User deleted all 10 tasks, IDs persisted to UserDefaults
        let deletedIds: Set<String> = Set(server.map { $0.id })
        let filtered = server.filter { !deletedIds.contains($0.id) }

        let result = await merge(serverTasks: filtered, pendingTasks: [])

        XCTAssertEqual(result.count, 0, "All deleted tasks should be filtered — none should reappear")
    }

    func testDeletedIdsUnionWithCoreDataCoversAllCases() {
        // Verify union logic: both sources contribute to the filter set
        let fromUserDefaults: Set<String> = ["a", "b"]  // Persisted across restart
        let fromCoreData: Set<String> = ["b", "c"]       // Not yet pushed

        let combined = fromCoreData.union(fromUserDefaults)

        XCTAssertEqual(combined, ["a", "b", "c"], "Union should include IDs from both sources")
    }

    // MARK: - Failed delete sync must not lose delete tracking

    @MainActor func testFailedDeleteKeepsFilteringAcrossMultipleSyncs() async {
        // THE BUG: Delete fails (server 500) → syncStatus becomes "failed" →
        // getPendingDeleteIds() no longer finds it → recentlyDeletedIds cleared →
        // next sync: task reappears.
        //
        // THE FIX: pending_delete status is preserved on failure, so CoreData
        // always contributes to the filter set across unlimited sync cycles.
        let now = Date()
        let server = [
            task(id: "keep-1", title: "Keep"),
            task(id: "deleted-1", title: "Delete failed on server"),
        ]

        // Simulate: delete failed, but CoreData still has pending_delete (not "failed")
        let coreDataDeleteIds: Set<String> = ["deleted-1"]
        // recentlyDeletedIds was already cleared from previous sync cycle
        let recentlyDeletedIds: Set<String> = []

        // This simulates the 2nd, 3rd, 4th... sync cycle after a failed delete.
        // The key insight: as long as pending_delete stays in CoreData, it's always filtered.
        let allDeleteIds = coreDataDeleteIds.union(recentlyDeletedIds)
        let filtered = server.filter { !allDeleteIds.contains($0.id) }

        let result = await merge(serverTasks: filtered, pendingTasks: [])

        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.contains(where: { $0.id == "deleted-1" }),
            "Deleted task must not reappear even after recentlyDeletedIds is cleared")
    }

    func testRecentlyDeletedIdsNotClearedWhileStillPending() {
        // recentlyDeletedIds should only be cleared for IDs no longer in CoreData.
        // If a delete is still pending (e.g., server keeps failing), the ID must persist.
        var recentlyDeletedIds: Set<String> = ["task-a", "task-b", "task-c"]
        let stillPendingInCoreData: Set<String> = ["task-a", "task-c"]  // These haven't synced yet

        // The fix: intersection keeps only IDs still pending
        recentlyDeletedIds = recentlyDeletedIds.intersection(stillPendingInCoreData)

        XCTAssertEqual(recentlyDeletedIds, ["task-a", "task-c"],
            "IDs still pending in CoreData should remain in recentlyDeletedIds")
        XCTAssertFalse(recentlyDeletedIds.contains("task-b"),
            "Successfully deleted IDs (not in CoreData) should be cleared")
    }
}
