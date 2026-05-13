import XCTest
@testable import Astrid_App

/// Swift port of `tests/lib/project-status.test.ts` (13 cases) from
/// astrid-web. Same fixtures, same assertions — if iOS diverges from
/// the web here, the board behaviour will drift in production. Treat
/// these as the contract.
final class ProjectStatusTests: XCTestCase {

    // MARK: - Fixtures

    private func makeList(
        id: String,
        name: String,
        projectId: String? = nil,
        listType: String? = nil,
        statusRole: String? = nil,
        statusOrder: Int? = nil,
        statusCompleted: Bool? = nil,
        description: String? = nil
    ) -> TaskList {
        var list = TaskList(id: id, name: name)
        list.privacy = .PRIVATE
        list.ownerId = "user-1"
        list.projectId = projectId
        list.listType = listType
        list.statusRole = statusRole
        list.statusOrder = statusOrder
        list.statusCompleted = statusCompleted
        list.description = description
        return list
    }

    private func makeTask(
        id: String = "task-1",
        lists: [TaskList],
        completed: Bool = false
    ) -> Task {
        Task(
            id: id,
            title: "Task",
            description: "",
            isAllDay: false,
            priority: .none,
            lists: lists,
            isPrivate: true,
            completed: completed
        )
    }

    // MARK: - Default statuses

    func test_seedsOnlyReadyDoingWaitingAsRealStatusLists() {
        XCTAssertEqual(
            DEFAULT_PROJECT_STATUSES.map { $0.name },
            ["Ready", "Doing", "Waiting"]
        )
        XCTAssertTrue(DEFAULT_PROJECT_STATUSES.allSatisfy { $0.description.count > 12 })
    }

    // MARK: - Virtual column copy

    func test_usesApprovedCopyForVirtualInboxAndDoneColumns() {
        let projectId = "project-1"
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId,
                             listType: "status", statusRole: "ready", statusOrder: 0)
        let columns = getProjectBoardColumns([ready], projectId: projectId)
        let inbox = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!
        let done = columns.first { $0.id == VIRTUAL_DONE_COLUMN_ID }!
        XCTAssertEqual(inbox.description, "Move them to \"Ready\" when they are... ready!")
        XCTAssertEqual(done.description, "Complete — congrats!")
    }

    // MARK: - Column ordering

    func test_buildsBoardColumnsWithVirtualInboxFirstAndDoneLast() {
        let projectId = "project-1"
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId,
                             listType: "status", statusRole: "ready", statusOrder: 0)
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId,
                             listType: "status", statusRole: "doing", statusOrder: 1)
        let waiting = makeList(id: "waiting", name: "Waiting", projectId: projectId,
                               listType: "status", statusRole: "waiting", statusOrder: 2)

        let columns = getProjectBoardColumns([ready, doing, waiting], projectId: projectId)
        XCTAssertEqual(columns.map { $0.id }, [
            VIRTUAL_INBOX_COLUMN_ID, "ready", "doing", "waiting", VIRTUAL_DONE_COLUMN_ID,
        ])
    }

    func test_hidesLegacyInboxAndDoneStatusListsFromBoard() {
        let projectId = "project-1"
        let legacyInbox = makeList(id: "inbox", name: "Inbox", projectId: projectId,
                                   listType: "status", statusRole: "inbox", statusOrder: -1)
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId,
                             listType: "status", statusRole: "ready", statusOrder: 0)
        let legacyDone = makeList(id: "done", name: "Done", projectId: projectId,
                                  listType: "status", statusRole: "done",
                                  statusOrder: 9, statusCompleted: true)

        let columns = getProjectBoardColumns([legacyInbox, ready, legacyDone], projectId: projectId)
        XCTAssertEqual(columns.map { $0.id }, [
            VIRTUAL_INBOX_COLUMN_ID, "ready", VIRTUAL_DONE_COLUMN_ID,
        ])
    }

    // MARK: - getTaskProjectColumnId

    func test_putsCompletedTasksInTheVirtualDoneColumn() {
        let projectId = "project-1"
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId,
                             listType: "status", statusRole: "ready")
        let completed = makeTask(lists: [ready], completed: true)
        XCTAssertEqual(
            getTaskProjectColumnId(completed, projectId: projectId, lists: [ready]),
            VIRTUAL_DONE_COLUMN_ID
        )
    }

    func test_routesProjectTasksWithoutStatusIntoInbox() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let t = makeTask(lists: [ios])
        XCTAssertEqual(
            getTaskProjectColumnId(t, projectId: projectId, lists: [ios, doing]),
            VIRTUAL_INBOX_COLUMN_ID
        )
    }

    // MARK: - resolveProjectColumnMove

    func test_keepsRegularListWhileReplacingStatus() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId, listType: "status", statusRole: "ready")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let t = makeTask(lists: [ios, ready])

        let columns = getProjectBoardColumns([ios, ready, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!
        let result = resolveProjectColumnMove(t, targetColumn: doingColumn,
                                              projectId: projectId, lists: [ios, ready, doing])
        XCTAssertEqual(result.listIds, ["ios", "doing"])
        XCTAssertFalse(result.completed)
    }

    func test_movesToVirtualDone_strippingStatusesAndSettingCompleted() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId, listType: "status", statusRole: "ready")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let t = makeTask(lists: [ios, ready])

        let columns = getProjectBoardColumns([ios, ready, doing], projectId: projectId)
        let doneColumn = columns.first { $0.id == VIRTUAL_DONE_COLUMN_ID }!
        let result = resolveProjectColumnMove(t, targetColumn: doneColumn,
                                              projectId: projectId, lists: [ios, ready, doing])
        XCTAssertEqual(result.listIds, ["ios"])
        XCTAssertTrue(result.completed)
    }

    /// Bug 2026-05-12 #3: a task loaded from Core Data has
    /// `task.lists = nil` but `task.listIds = ["ios"]`. Dropping it on
    /// the Doing column was producing `listIds = ["doing"]` — wiping
    /// the regular-list membership, so the task vanished from the
    /// board after the move. resolveProjectColumnMove must respect
    /// listIds the same way getProjectDomainTasks does.
    func test_resolveMove_honorsListIds_whenTaskListsIsNil() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")

        var cachedTask = makeTask(lists: [])
        cachedTask.lists = nil
        cachedTask.listIds = ["ios"]

        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!
        let move = resolveProjectColumnMove(cachedTask, targetColumn: doingColumn,
                                            projectId: projectId, lists: [ios, doing])
        XCTAssertEqual(move.listIds, ["ios", "doing"],
                       "Regular list membership must survive the move even when task.lists is nil")
        XCTAssertFalse(move.completed)
    }

    func test_movesBackToInbox_strippingStatusesAndClearingCompleted() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let completedTask = makeTask(lists: [ios, doing], completed: true)

        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let inboxColumn = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!
        let result = resolveProjectColumnMove(completedTask, targetColumn: inboxColumn,
                                              projectId: projectId, lists: [ios, doing])
        XCTAssertEqual(result.listIds, ["ios"])
        XCTAssertFalse(result.completed)
    }

    // MARK: - normalizeProjectStatusListIds

    func test_normalizesToOneStatusPerProject_andForcesCompletedFalse() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId, listType: "status", statusRole: "ready")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")

        let result = normalizeProjectStatusListIds(
            requestedListIds: ["ios", "ready", "doing"],
            knownLists: [ios, ready, doing]
        )
        XCTAssertEqual(result.listIds, ["ios", "doing"])
        XCTAssertEqual(result.completedFromStatus, false)
    }

    func test_stripsEveryProjectStatus_whenTaskIsBeingCompleted() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let ready = makeList(id: "ready", name: "Ready", projectId: projectId, listType: "status", statusRole: "ready")

        let result = normalizeProjectStatusListIds(
            requestedListIds: ["ios", "ready"],
            knownLists: [ios, ready],
            completed: true
        )
        XCTAssertEqual(result.listIds, ["ios"])
        XCTAssertNil(result.completedFromStatus)
    }

    func test_doesNotAutoAddStatus_whenProjectTaskCreatedWithoutOne() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing", statusOrder: 1)

        let result = normalizeProjectStatusListIds(
            requestedListIds: ["ios"],
            knownLists: [ios, doing]
        )
        XCTAssertEqual(result.listIds, ["ios"])
        XCTAssertNil(result.completedFromStatus)
    }

    // MARK: - getProjectDomainTasks

    func test_getProjectDomainTasks_onlyReturnsTasksAttachedToRegularList() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        let otherProject = makeList(id: "web", name: "Web", projectId: "project-2", listType: "regular")
        let status = makeList(id: "ready", name: "Ready", projectId: projectId, listType: "status", statusRole: "ready")

        let inProject = makeTask(id: "t-1", lists: [ios])
        let onlyStatus = makeTask(id: "t-2", lists: [status])
        let outside = makeTask(id: "t-3", lists: [otherProject])

        let result = getProjectDomainTasks(
            [inProject, onlyStatus, outside],
            lists: [ios, otherProject, status],
            projectId: projectId
        )
        XCTAssertEqual(result.map { $0.id }, ["t-1"])
    }

    /// Bug 2026-05-12 #2: tasks loaded from Core Data have `task.lists`
    /// nil but `task.listIds` populated (the cache stores only ids).
    /// Without this fallback the board's Inbox column appears empty on
    /// cold start until a full sync repopulates `task.lists`.
    func test_getProjectDomainTasks_fallsBackToListIds_whenListsIsNil() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")

        // Task has no `lists` array (came from Core Data) but listIds has the regular list id.
        var cachedTask = makeTask(id: "t-cache", lists: [])
        cachedTask.lists = nil
        cachedTask.listIds = ["ios"]

        let result = getProjectDomainTasks(
            [cachedTask],
            lists: [ios],
            projectId: projectId
        )
        XCTAssertEqual(result.map { $0.id }, ["t-cache"],
                       "Task with listIds=[\"ios\"] but task.lists=nil should still surface in the project board")
    }

    // MARK: - Manual ordering: boardColumnTasksSorted + resolveBoardReorder

    /// boardColumnTasksSorted returns column tasks in the order
    /// dictated by manualSortOrder when one is present.
    func test_boardColumnTasksSorted_appliesManualOrder() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let a = makeTask(id: "a", lists: [ios, doing])
        let b = makeTask(id: "b", lists: [ios, doing])
        let c = makeTask(id: "c", lists: [ios, doing])

        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!

        let sorted = boardColumnTasksSorted(
            [a, b, c],
            projectId: projectId,
            column: doingColumn,
            lists: [ios, doing],
            manualOrder: ["c", "a", "b"]
        )
        XCTAssertEqual(sorted.map { $0.id }, ["c", "a", "b"])
    }

    func test_boardColumnTasksSorted_nilManualOrder_returnsIncomingOrder() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let a = makeTask(id: "a", lists: [ios])
        let b = makeTask(id: "b", lists: [ios])
        let columns = getProjectBoardColumns([ios], projectId: projectId)
        let inboxColumn = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!

        let result = boardColumnTasksSorted(
            [a, b],
            projectId: projectId,
            column: inboxColumn,
            lists: [ios],
            manualOrder: nil
        )
        XCTAssertEqual(result.map { $0.id }, ["a", "b"])
    }

    /// Drop a Doing task between two Inbox tasks → manual order places
    /// the dragged task at the right global slot so it shows in that
    /// position in Inbox AFTER the move.
    func test_resolveBoardReorder_insertsAtMiddleIndex_inSameColumn() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let a = makeTask(id: "a", lists: [ios, doing])
        let b = makeTask(id: "b", lists: [ios, doing])
        let c = makeTask(id: "c", lists: [ios, doing])
        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!

        // current order: a, b, c. Drag c to index 1 → expect a, c, b
        let result = resolveBoardReorder(
            task: c,
            targetColumn: doingColumn,
            targetIndex: 1,
            projectId: projectId,
            lists: [ios, doing],
            allTasks: [a, b, c],
            currentManualOrder: ["a", "b", "c"]
        )
        XCTAssertEqual(result.newManualOrder, ["a", "c", "b"])
        XCTAssertFalse(result.completed)
        XCTAssertTrue(result.listIds.contains("ios"))
        XCTAssertTrue(result.listIds.contains("doing"))
    }

    /// Drop an Inbox task at index 0 of Doing → task joins Doing's
    /// listIds AND its id moves to before Doing's current first task
    /// in the global manual order.
    func test_resolveBoardReorder_movesAcrossColumns_atSlotZero() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let inboxTask = makeTask(id: "i-1", lists: [ios])
        let doing1 = makeTask(id: "d-1", lists: [ios, doing])
        let doing2 = makeTask(id: "d-2", lists: [ios, doing])
        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!

        // Inbox task → top of Doing
        let result = resolveBoardReorder(
            task: inboxTask,
            targetColumn: doingColumn,
            targetIndex: 0,
            projectId: projectId,
            lists: [ios, doing],
            allTasks: [inboxTask, doing1, doing2],
            currentManualOrder: ["d-1", "d-2", "i-1"]
        )
        XCTAssertEqual(result.newManualOrder.firstIndex(of: "i-1"), 0)
        XCTAssertEqual(result.newManualOrder, ["i-1", "d-1", "d-2"])
        XCTAssertTrue(result.listIds.contains("doing"))
    }

    /// Drop a task at the END of a column → appended after the column's
    /// current last task in the global order.
    func test_resolveBoardReorder_appendAtEnd() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let a = makeTask(id: "a", lists: [ios, doing])
        let b = makeTask(id: "b", lists: [ios, doing])
        let c = makeTask(id: "c", lists: [ios])  // currently inbox
        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!

        // Drop c at end of Doing (index 2 = past last task)
        let result = resolveBoardReorder(
            task: c,
            targetColumn: doingColumn,
            targetIndex: 2,
            projectId: projectId,
            lists: [ios, doing],
            allTasks: [a, b, c],
            currentManualOrder: ["a", "b", "c"]
        )
        // c ends up after b in global order: ["a", "b", "c"] still works
        // but if c was before b, this would reorder. Verify c is after b.
        let ai = result.newManualOrder.firstIndex(of: "a")!
        let bi = result.newManualOrder.firstIndex(of: "b")!
        let ci = result.newManualOrder.firstIndex(of: "c")!
        XCTAssertLessThan(ai, bi)
        XCTAssertLessThan(bi, ci)
        XCTAssertTrue(result.listIds.contains("doing"))
    }

    /// Drop on Inbox (virtual) → strips status, completed=false, inserts
    /// at target slot. Mirrors the same persistence semantics.
    func test_resolveBoardReorder_toInbox_stripsStatusAndOrders() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let inboxA = makeTask(id: "i-a", lists: [ios])
        let inboxB = makeTask(id: "i-b", lists: [ios])
        let doingX = makeTask(id: "d-x", lists: [ios, doing])

        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let inboxColumn = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!

        let result = resolveBoardReorder(
            task: doingX,
            targetColumn: inboxColumn,
            targetIndex: 1,  // between inboxA and inboxB
            projectId: projectId,
            lists: [ios, doing],
            allTasks: [inboxA, inboxB, doingX],
            currentManualOrder: ["i-a", "i-b", "d-x"]
        )
        XCTAssertFalse(result.listIds.contains("doing"))
        XCTAssertTrue(result.listIds.contains("ios"))
        XCTAssertFalse(result.completed)
        // d-x ends up between i-a and i-b in the global manual order
        let positions = ["i-a", "d-x", "i-b"].compactMap { id in result.newManualOrder.firstIndex(of: id) }
        XCTAssertEqual(positions, positions.sorted(),
                       "Expected d-x between i-a and i-b; got \(result.newManualOrder)")
    }

    // MARK: - isTaskAlreadyInColumn (drag-drop reliability)

    /// Task currently in Doing dropped on Doing → no-op. Short-circuits
    /// the network round-trip so the cell doesn't flicker from a
    /// pointless re-render.
    func test_isTaskAlreadyInColumn_droppedOnOwnStatusColumn_isTrue() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let t = makeTask(lists: [ios, doing])

        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!
        XCTAssertTrue(isTaskAlreadyInColumn(t, targetColumn: doingColumn,
                                            projectId: projectId,
                                            lists: [ios, doing]))
    }

    /// Inbox task dropped on Doing → not a no-op (real move).
    func test_isTaskAlreadyInColumn_inboxDroppedOnDoing_isFalse() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId, listType: "status", statusRole: "doing")
        let t = makeTask(lists: [ios])

        let columns = getProjectBoardColumns([ios, doing], projectId: projectId)
        let doingColumn = columns.first { $0.id == "doing" }!
        XCTAssertFalse(isTaskAlreadyInColumn(t, targetColumn: doingColumn,
                                             projectId: projectId,
                                             lists: [ios, doing]))
    }

    /// Completed task dropped on Done → no-op (already in virtual Done).
    func test_isTaskAlreadyInColumn_completedDroppedOnDone_isTrue() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let t = makeTask(lists: [ios], completed: true)

        let columns = getProjectBoardColumns([ios], projectId: projectId)
        let doneColumn = columns.first { $0.id == VIRTUAL_DONE_COLUMN_ID }!
        XCTAssertTrue(isTaskAlreadyInColumn(t, targetColumn: doneColumn,
                                            projectId: projectId,
                                            lists: [ios]))
    }

    // MARK: - BoardCardPayload (typed drag-drop)

    /// The custom Transferable round-trips through JSON encoding.
    /// Smoke check that the payload type itself is stable.
    func test_boardCardPayload_codableRoundTrip() throws {
        let original = BoardCardPayload(taskId: "task-abc-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BoardCardPayload.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - boardColumnsVisible (iPad landscape: 3-5 columns)

    /// iPhone portrait width (~390pt). Single full-screen paged column.
    func test_columnsVisible_iPhonePortrait_isOne() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 390), 1)
    }

    /// iPhone landscape on standard models (~752pt). Two columns fit.
    func test_columnsVisible_iPhoneLandscape_isTwo() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 752), 2)
    }

    /// iPad mini portrait (~744pt). Two columns fit.
    func test_columnsVisible_iPadMiniPortrait_isTwo() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 744), 2)
    }

    /// iPad standard landscape (~1080pt). Three columns fit — minimum
    /// of the user's stated 3-5 range.
    func test_columnsVisible_iPadStandardLandscape_isThree() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 1080), 3)
    }

    /// iPad Pro 12.9" landscape (~1366pt). Four columns fit.
    func test_columnsVisible_iPadProLandscape_isFour() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 1366), 4)
    }

    /// Clamps to 5 even for unrealistically wide screens.
    func test_columnsVisible_isClampedToFive() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 3000), 5)
    }

    /// Degenerate inputs never crash and never yield 0.
    func test_columnsVisible_handlesZeroOrNegativeWidth() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 0), 1)
        XCTAssertEqual(boardColumnsVisible(availableWidth: -10), 1)
    }

    func test_getProjectDomainTasks_prefersLists_butListIdsAlsoCountsWhenBothPresent() {
        // Defensive: when both lists and listIds are populated, either
        // matching the project's regular list should include the task.
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        var t = makeTask(id: "t-both", lists: [ios])
        t.listIds = ["ios"]

        let result = getProjectDomainTasks([t], lists: [ios], projectId: projectId)
        XCTAssertEqual(result.map { $0.id }, ["t-both"])
    }

    // MARK: - applyBoardReorderLocally (drag-drop no-flicker contract)

    /// Pure helper: given a [TaskList] and a BoardReorder, returns a
    /// new array with the project's domain list patched in place so
    /// `manualSortOrder` reflects the drop and `sortBy` is "manual".
    ///
    /// The drop handler calls this BEFORE the async server PUT so the
    /// list state — and therefore the column's task order — is updated
    /// in the same tick as the task move. Without this the card appears
    /// to "reload" after the server round-trip lands.
    func test_applyBoardReorderLocally_writesManualSortOrderAndSetsSortBy() {
        let projectId = "p-1"
        var ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        ios.sortBy = "createdAt"
        ios.manualSortOrder = ["a", "b", "c"]
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId,
                             listType: "status", statusRole: "doing")

        let reorder = BoardReorder(
            listIds: ["ios", "doing"],
            completed: false,
            newManualOrder: ["a", "c", "b"]
        )

        let updated = applyBoardReorderLocally(
            lists: [ios, doing],
            reorder: reorder,
            domainListId: "ios"
        )
        let updatedIos = updated.first { $0.id == "ios" }!
        XCTAssertEqual(updatedIos.manualSortOrder, ["a", "c", "b"])
        XCTAssertEqual(updatedIos.sortBy, "manual")
        // Other lists untouched.
        let updatedDoing = updated.first { $0.id == "doing" }!
        XCTAssertEqual(updatedDoing.manualSortOrder, doing.manualSortOrder)
        XCTAssertEqual(updatedDoing.sortBy, doing.sortBy)
    }

    /// If the domain list isn't in the array (defensive — shouldn't
    /// happen, but the drop handler shouldn't crash if state is stale),
    /// the function returns the input unchanged.
    func test_applyBoardReorderLocally_missingListIsNoOp() {
        let projectId = "p-1"
        let doing = makeList(id: "doing", name: "Doing", projectId: projectId,
                             listType: "status", statusRole: "doing")
        let reorder = BoardReorder(
            listIds: ["ios", "doing"],
            completed: false,
            newManualOrder: ["a", "b"]
        )
        let updated = applyBoardReorderLocally(
            lists: [doing],
            reorder: reorder,
            domainListId: "ios"
        )
        XCTAssertEqual(updated, [doing])
    }

    /// Already on "manual" — don't churn sortBy back through itself.
    /// The function should be idempotent on repeat application.
    func test_applyBoardReorderLocally_isIdempotent() {
        let projectId = "p-1"
        var ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        ios.sortBy = "manual"
        ios.manualSortOrder = ["a", "b"]
        let reorder = BoardReorder(
            listIds: ["ios"],
            completed: false,
            newManualOrder: ["b", "a"]
        )
        let once = applyBoardReorderLocally(lists: [ios], reorder: reorder, domainListId: "ios")
        let twice = applyBoardReorderLocally(lists: once, reorder: reorder, domainListId: "ios")
        XCTAssertEqual(once, twice)
        XCTAssertEqual(once.first?.manualSortOrder, ["b", "a"])
        XCTAssertEqual(once.first?.sortBy, "manual")
    }
}
