//  LiveUpdateWiringTests.swift
//  Regression coverage for task 63e75630 (AITD-314).
//
//  `SSEClient` decoded task_created / task_updated / task_deleted and the three list equivalents,
//  then handed each one to a handler array that NOTHING had ever subscribed to. A collaborator's
//  edit cost the victim a full main-thread decode and changed nothing on screen; rows only moved
//  when the 60 s full pull landed. "Live" updates were not live.
//
//  Two kinds of test here, and both are needed. The policy and apply tests prove an event does the
//  right thing to the cache. The wiring guard proves anything is listening at all — without it,
//  every other test in this file would still pass in the world where the bug shipped.

import XCTest
@testable import Astrid_App

final class LiveUpdateWiringTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    private func task(_ id: String, title: String = "T", due: Date? = nil,
                      created: Date? = nil, updated: Date? = nil) -> Task {
        Task(id: id, title: title, dueDateTime: due, listIds: [],
             createdAt: created ?? epoch, updatedAt: updated ?? epoch)
    }

    // MARK: - Policy: what may be applied

    func testAFreshRemoteEditIsApplied() {
        let cached = task("t1", title: "old", updated: epoch)
        let incoming = task("t1", title: "new", updated: epoch.addingTimeInterval(60))

        XCTAssertEqual(
            LiveUpdatePolicy.taskUpsert(incoming: incoming, cached: cached, locallyDeletedIds: []),
            .apply
        )
    }

    func testAStaleEventDoesNotClobberANewerLocalEdit() {
        // The user renamed the task a moment ago and it has not reached the server yet. An SSE
        // event describing the pre-edit state must not undo their typing.
        let localEdit = task("t1", title: "what the user just typed", updated: epoch.addingTimeInterval(60))
        let staleRemote = task("t1", title: "what the server still thinks", updated: epoch)

        XCTAssertEqual(
            LiveUpdatePolicy.taskUpsert(incoming: staleRemote, cached: localEdit, locallyDeletedIds: []),
            .ignoreStale
        )
    }

    func testAnEqualTimestampPrefersTheServerCopy() {
        // Same instant means the server already has this edit, and its copy may carry fields the
        // local one does not. This matches what the 60 s pull does.
        let cached = task("t1", updated: epoch)
        XCTAssertEqual(
            LiveUpdatePolicy.taskUpsert(incoming: task("t1", updated: epoch), cached: cached, locallyDeletedIds: []),
            .apply
        )
    }

    func testALateEventCannotResurrectATaskTheUserDeleted() {
        XCTAssertEqual(
            LiveUpdatePolicy.taskUpsert(incoming: task("t1"), cached: nil, locallyDeletedIds: ["t1"]),
            .ignoreLocallyDeleted
        )
    }

    func testTemporaryIdsAreNeverAppliedOrDeleted() {
        XCTAssertEqual(
            LiveUpdatePolicy.taskUpsert(incoming: task("temp_1"), cached: nil, locallyDeletedIds: []),
            .ignoreTemporaryId
        )
        XCTAssertEqual(LiveUpdatePolicy.taskDelete(id: "temp_1"), .ignoreTemporaryId)
        XCTAssertEqual(LiveUpdatePolicy.taskDelete(id: "real-1"), .apply)
        XCTAssertEqual(LiveUpdatePolicy.listDelete(id: "temp_1"), .ignoreTemporaryId)
    }

    func testANewTaskWithNoCachedCopyIsApplied() {
        XCTAssertEqual(
            LiveUpdatePolicy.taskUpsert(incoming: task("brand-new"), cached: nil, locallyDeletedIds: []),
            .apply
        )
    }

    func testListPolicyMirrorsTheTaskRules() {
        var cached = TaskList(id: "l1", name: "old")
        cached.updatedAt = epoch.addingTimeInterval(60)
        var stale = TaskList(id: "l1", name: "older")
        stale.updatedAt = epoch

        XCTAssertEqual(LiveUpdatePolicy.listUpsert(incoming: stale, cached: cached), .ignoreStale)
        XCTAssertEqual(LiveUpdatePolicy.listUpsert(incoming: cached, cached: stale), .apply)
        XCTAssertEqual(LiveUpdatePolicy.listUpsert(incoming: TaskList(id: "temp_x", name: "n"), cached: nil),
                       .ignoreTemporaryId)
    }

    // MARK: - Ordering: a live insert lands where a sync pull would put it

    func testALiveInsertLandsWhereTheSyncSortWouldPutIt() async {
        let a = task("a", due: epoch)
        let b = task("b", due: epoch.addingTimeInterval(3600))
        let c = task("c", due: epoch.addingTimeInterval(7200))

        let sorted = await TaskService.mergeAndSortTasksInBackground(newTasks: [a, c], pendingTasks: [])
        var live = sorted
        live.insert(b, at: TaskOrdering.insertionIndex(for: b, in: live))

        let pulled = await TaskService.mergeAndSortTasksInBackground(newTasks: [a, b, c], pendingTasks: [])
        XCTAssertEqual(live.map(\.id), pulled.map(\.id),
                       "a live insert and the next sync pull must agree, or the row jumps")
    }

    func testInsertionIndexHandlesTheEndsOfTheArray() {
        let middle = task("m", due: epoch.addingTimeInterval(3600))
        let sorted = [task("a", due: epoch), middle, task("z", due: epoch.addingTimeInterval(7200))]

        XCTAssertEqual(TaskOrdering.insertionIndex(for: task("first", due: epoch.addingTimeInterval(-1)), in: sorted), 0)
        XCTAssertEqual(TaskOrdering.insertionIndex(for: task("last", due: epoch.addingTimeInterval(99999)), in: sorted), 3)
        XCTAssertEqual(TaskOrdering.insertionIndex(for: task("undated"), in: sorted), 3,
                       "undated tasks sort after dated ones")
    }

    func testListOrderingPutsFavoritesFirstThenAlphabetical() {
        var zebra = TaskList(id: "1", name: "Zebra")
        zebra.isFavorite = true
        let apple = TaskList(id: "2", name: "apple")
        let banana = TaskList(id: "3", name: "Banana")

        let sorted = [banana, zebra, apple].sorted(by: ListOrdering.isOrderedBefore)
        XCTAssertEqual(sorted.map(\.name), ["Zebra", "apple", "Banana"])
    }

    // MARK: - Applying to the live caches, with no network

    @MainActor
    func testALiveTaskUpdateChangesTheCacheWithNoNetworkCall() {
        let service = TaskService.shared
        service.clearCache()
        defer { service.clearCache() }

        let original = task("live-1", title: "before", updated: epoch)
        service.updateTaskInCache(original)
        service.tasks = [original]

        service.applyLiveTaskUpsert(task("live-1", title: "after", updated: epoch.addingTimeInterval(60)))

        XCTAssertEqual(service.tasks.first?.title, "after")
        XCTAssertEqual(service.tasksById["live-1"]?.title, "after")
        XCTAssertEqual(service.pendingOperationsCount, 0,
                       "a live update is cache-only — it must never queue an outbound write")
    }

    @MainActor
    func testALiveTaskCreateAppearsInTheList() {
        let service = TaskService.shared
        service.clearCache()
        defer { service.clearCache() }

        service.applyLiveTaskUpsert(task("live-new", title: "from a collaborator"))

        XCTAssertEqual(service.tasks.map(\.id), ["live-new"])
        XCTAssertEqual(service.pendingOperationsCount, 0)
    }

    @MainActor
    func testALiveTaskDeleteRemovesItFromBothCaches() {
        let service = TaskService.shared
        service.clearCache()
        defer { service.clearCache() }

        let doomed = task("live-del")
        service.updateTaskInCache(doomed)
        service.tasks = [doomed]

        service.applyLiveTaskDelete("live-del")

        XCTAssertTrue(service.tasks.isEmpty)
        XCTAssertNil(service.tasksById["live-del"])
    }

    @MainActor
    func testAStaleLiveEventLeavesTheLocalEditAlone() {
        let service = TaskService.shared
        service.clearCache()
        defer { service.clearCache() }

        let localEdit = task("live-2", title: "the user's words", updated: epoch.addingTimeInterval(60))
        service.updateTaskInCache(localEdit)
        service.tasks = [localEdit]

        service.applyLiveTaskUpsert(task("live-2", title: "server's older copy", updated: epoch))

        XCTAssertEqual(service.tasks.first?.title, "the user's words")
    }

    @MainActor
    func testALiveListUpdateChangesTheListCache() {
        let service = ListService.shared
        let restore = service.lists
        defer { service.lists = restore }

        var original = TaskList(id: "live-list", name: "Before")
        original.updatedAt = epoch
        service.applyLiveListUpsert(original)
        XCTAssertTrue(service.lists.contains { $0.id == "live-list" })

        var renamed = original
        renamed.name = "After"
        renamed.updatedAt = epoch.addingTimeInterval(60)
        service.applyLiveListUpsert(renamed)
        XCTAssertEqual(service.lists.first { $0.id == "live-list" }?.name, "After")

        service.applyLiveListDelete("live-list")
        XCTAssertFalse(service.lists.contains { $0.id == "live-list" })
    }

    // MARK: - The guard: something must actually be listening

    func testTheServicesSubscribeToEveryTaskAndListEvent() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        let taskSource = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Services/TaskService.swift"),
            encoding: .utf8)
        let listSource = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Services/ListService.swift"),
            encoding: .utf8)

        for event in ["onTaskCreated", "onTaskUpdated", "onTaskDeleted"] {
            XCTAssertTrue(taskSource.contains(event),
                          "TaskService must subscribe to \(event) — an event delivered to nobody is "
                          + "a decode the user pays for and never sees (AITD-314)")
        }
        for event in ["onListCreated", "onListUpdated", "onListDeleted"] {
            XCTAssertTrue(listSource.contains(event),
                          "ListService must subscribe to \(event) (AITD-314)")
        }
    }

    func testTheLiveApplyPathNeverCallsTheAPIClient() throws {
        // Cache-only is the whole contract. A live event that wrote back to the server is the
        // ping-pong the web board has an open task about.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        for (file, methods) in [
            ("Astrid App/Core/Services/TaskService.swift", ["applyLiveTaskUpsert", "applyLiveTaskDelete"]),
            ("Astrid App/Core/Services/ListService.swift", ["applyLiveListUpsert", "applyLiveListDelete"]),
        ] {
            let source = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for method in methods {
                let body = try XCTUnwrap(functionBody(named: method, in: source),
                                         "\(method) not found in \(file)")
                XCTAssertFalse(body.contains("apiClient"),
                               "\(method) must be cache-only — it must not call the API")
                XCTAssertFalse(body.contains("Outbox"),
                               "\(method) must be cache-only — it must not enqueue a write")
            }
        }
    }

    /// Crude but sufficient: from `func <name>` to the first line that is a closing brace at the
    /// method's own indentation.
    private func functionBody(named name: String, in source: String) -> String? {
        let lines = source.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains("func \(name)(") }) else { return nil }
        let indent = lines[start].prefix { $0 == " " }
        let closing = "\(indent)}"
        guard let end = lines[(start + 1)...].firstIndex(of: closing) else { return nil }
        return lines[start...end].joined(separator: "\n")
    }
}
