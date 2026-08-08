import XCTest
@testable import Astrid_App

/// Swift port of `tests/lib/project-status.test.ts` from astrid-web. Same
/// fixtures, same assertions — if iOS diverges from the web here, the
/// board behaviour will drift in production. Treat these as the contract.
///
/// Status lists are per-user globals: `projectId == nil`, `listType ==
/// "status"`, one Ready/Doing/Waiting set shared across every project
/// board. Domain lists keep their project id.
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

    /// A per-user global status list: projectId is always nil.
    private func makeStatusList(
        id: String,
        name: String,
        statusRole: String? = nil,
        statusOrder: Int? = nil,
        statusCompleted: Bool? = nil,
        description: String? = nil
    ) -> TaskList {
        makeList(id: id, name: name, projectId: nil, listType: "status",
                 statusRole: statusRole, statusOrder: statusOrder,
                 statusCompleted: statusCompleted, description: description)
    }

    private func makeTask(
        id: String = "task-1",
        lists: [TaskList],
        completed: Bool = false,
        statusRole: String? = nil
    ) -> Task {
        Task(
            id: id,
            title: "Task",
            description: "",
            isAllDay: false,
            priority: .none,
            lists: lists,
            isPrivate: true,
            completed: completed,
            statusRole: statusRole
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
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready", statusOrder: 0)
        let columns = getProjectBoardColumns([ready])
        let inbox = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!
        let done = columns.first { $0.id == VIRTUAL_DONE_COLUMN_ID }!
        XCTAssertEqual(inbox.description, "Move them to \"Ready\" when they are... ready!")
        XCTAssertEqual(done.description, "Complete — congrats!")
    }

    // MARK: - Column ordering

    func test_buildsBoardColumnsWithVirtualInboxFirstAndDoneLast() {
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready", statusOrder: 0)
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing", statusOrder: 1)
        let waiting = makeStatusList(id: "waiting", name: "Waiting", statusRole: "waiting", statusOrder: 2)

        let columns = getProjectBoardColumns([ready, doing, waiting])
        XCTAssertEqual(columns.map { $0.id }, [
            VIRTUAL_INBOX_COLUMN_ID, "ready", "doing", "waiting", VIRTUAL_DONE_COLUMN_ID,
        ])
    }

    /// Per-user global status lists (projectId nil) still render as board
    /// columns even though no list in the set carries the project's id.
    func test_rendersSameGlobalStatusColumnsRegardlessOfProject() {
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready", statusOrder: 0)
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing", statusOrder: 1)
        let projectA = makeList(id: "a", name: "Project A list", projectId: "project-a", listType: "regular")

        // Waiting appears without a backing row: the three defaults come from
        // config now, so the board survives the status lists going away
        // (task 2e41c645). A backed role keeps the LIST id; an unbacked one is
        // keyed on the role.
        let columns = getProjectBoardColumns([projectA, ready, doing])
        XCTAssertEqual(columns.map { $0.id }, [
            VIRTUAL_INBOX_COLUMN_ID, "ready", "doing", "waiting", VIRTUAL_DONE_COLUMN_ID,
        ])
    }

    func test_hidesLegacyInboxAndDoneStatusListsFromBoard() {
        let legacyInbox = makeStatusList(id: "inbox", name: "Inbox", statusRole: "inbox", statusOrder: -1)
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready", statusOrder: 0)
        let legacyDone = makeStatusList(id: "done", name: "Done", statusRole: "done",
                                        statusOrder: 9, statusCompleted: true)

        // The legacy inbox/done rows stay hidden; the config defaults render.
        let columns = getProjectBoardColumns([legacyInbox, ready, legacyDone])
        XCTAssertEqual(columns.map { $0.id }, [
            VIRTUAL_INBOX_COLUMN_ID, "ready", "doing", "waiting", VIRTUAL_DONE_COLUMN_ID,
        ])
    }

    // MARK: - getTaskProjectColumnId

    func test_putsCompletedTasksInTheVirtualDoneColumn() {
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")
        let completed = makeTask(lists: [ready], completed: true)
        XCTAssertEqual(
            getTaskProjectColumnId(completed, lists: [ready]),
            VIRTUAL_DONE_COLUMN_ID
        )
    }

    func test_routesProjectTasksWithoutStatusIntoInbox() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let t = makeTask(lists: [ios])
        XCTAssertEqual(
            getTaskProjectColumnId(t, lists: [ios, doing]),
            VIRTUAL_INBOX_COLUMN_ID
        )
    }

    // MARK: - resolveProjectColumnMove

    func test_keepsRegularListWhileReplacingStatus() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let t = makeTask(lists: [ios, ready])

        let columns = getProjectBoardColumns([ios, ready, doing])
        let doingColumn = columns.first { $0.id == "doing" }!
        let result = resolveProjectColumnMove(t, targetColumn: doingColumn,
                                              lists: [ios, ready, doing])
        XCTAssertEqual(result.listIds, ["ios", "doing"])
        XCTAssertFalse(result.completed)
    }

    func test_movesToVirtualDone_strippingStatusesAndSettingCompleted() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let t = makeTask(lists: [ios, ready])

        let columns = getProjectBoardColumns([ios, ready, doing])
        let doneColumn = columns.first { $0.id == VIRTUAL_DONE_COLUMN_ID }!
        let result = resolveProjectColumnMove(t, targetColumn: doneColumn,
                                              lists: [ios, ready, doing])
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
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")

        var cachedTask = makeTask(lists: [])
        cachedTask.lists = nil
        cachedTask.listIds = ["ios"]

        let columns = getProjectBoardColumns([ios, doing])
        let doingColumn = columns.first { $0.id == "doing" }!
        let move = resolveProjectColumnMove(cachedTask, targetColumn: doingColumn,
                                            lists: [ios, doing])
        XCTAssertEqual(move.listIds, ["ios", "doing"],
                       "Regular list membership must survive the move even when task.lists is nil")
        XCTAssertFalse(move.completed)
    }

    func test_movesBackToInbox_strippingStatusesAndClearingCompleted() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let completedTask = makeTask(lists: [ios, doing], completed: true)

        let columns = getProjectBoardColumns([ios, doing])
        let inboxColumn = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!
        let result = resolveProjectColumnMove(completedTask, targetColumn: inboxColumn,
                                              lists: [ios, doing])
        XCTAssertEqual(result.listIds, ["ios"])
        XCTAssertFalse(result.completed)
    }

    // MARK: - normalizeProjectStatusListIds

    func test_normalizesToOneGlobalStatus_andForcesCompletedFalse() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")

        let result = normalizeProjectStatusListIds(
            requestedListIds: ["ios", "ready", "doing"],
            knownLists: [ios, ready, doing]
        )
        XCTAssertEqual(result.listIds, ["ios", "doing"])
        XCTAssertEqual(result.completedFromStatus, false)
    }

    func test_stripsEveryStatus_whenTaskIsBeingCompleted() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")

        let result = normalizeProjectStatusListIds(
            requestedListIds: ["ios", "ready"],
            knownLists: [ios, ready],
            completed: true
        )
        XCTAssertEqual(result.listIds, ["ios"])
        XCTAssertNil(result.completedFromStatus)
    }

    func test_doesNotAutoAddStatus_whenProjectTaskCreatedWithoutOne() {
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: "project-1", listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing", statusOrder: 1)

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
        let status = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")

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

    func test_getProjectDomainTasks_prefersLists_butListIdsAlsoCountsWhenBothPresent() {
        let projectId = "project-1"
        let ios = makeList(id: "ios", name: "Astrid iOS To-do", projectId: projectId, listType: "regular")
        var t = makeTask(id: "t-both", lists: [ios])
        t.listIds = ["ios"]

        let result = getProjectDomainTasks([t], lists: [ios], projectId: projectId)
        XCTAssertEqual(result.map { $0.id }, ["t-both"])
    }

    // MARK: - Manual ordering: boardColumnTasksSorted + resolveBoardReorder

    /// boardColumnTasksSorted returns column tasks in the order
    /// dictated by manualSortOrder when one is present.
    func test_boardColumnTasksSorted_appliesManualOrder() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let a = makeTask(id: "a", lists: [ios, doing])
        let b = makeTask(id: "b", lists: [ios, doing])
        let c = makeTask(id: "c", lists: [ios, doing])

        let columns = getProjectBoardColumns([ios, doing])
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
        let columns = getProjectBoardColumns([ios])
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

    /// Drop a Doing task between two Doing tasks → manual order places
    /// the dragged task at the right global slot.
    func test_resolveBoardReorder_insertsAtMiddleIndex_inSameColumn() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let a = makeTask(id: "a", lists: [ios, doing])
        let b = makeTask(id: "b", lists: [ios, doing])
        let c = makeTask(id: "c", lists: [ios, doing])
        let columns = getProjectBoardColumns([ios, doing])
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
    /// listIds AND its id moves to before Doing's current first task.
    func test_resolveBoardReorder_movesAcrossColumns_atSlotZero() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let inboxTask = makeTask(id: "i-1", lists: [ios])
        let doing1 = makeTask(id: "d-1", lists: [ios, doing])
        let doing2 = makeTask(id: "d-2", lists: [ios, doing])
        let columns = getProjectBoardColumns([ios, doing])
        let doingColumn = columns.first { $0.id == "doing" }!

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
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let a = makeTask(id: "a", lists: [ios, doing])
        let b = makeTask(id: "b", lists: [ios, doing])
        let c = makeTask(id: "c", lists: [ios])  // currently inbox
        let columns = getProjectBoardColumns([ios, doing])
        let doingColumn = columns.first { $0.id == "doing" }!

        let result = resolveBoardReorder(
            task: c,
            targetColumn: doingColumn,
            targetIndex: 2,
            projectId: projectId,
            lists: [ios, doing],
            allTasks: [a, b, c],
            currentManualOrder: ["a", "b", "c"]
        )
        let ai = result.newManualOrder.firstIndex(of: "a")!
        let bi = result.newManualOrder.firstIndex(of: "b")!
        let ci = result.newManualOrder.firstIndex(of: "c")!
        XCTAssertLessThan(ai, bi)
        XCTAssertLessThan(bi, ci)
        XCTAssertTrue(result.listIds.contains("doing"))
    }

    /// Drop on Inbox (virtual) → strips status, completed=false, inserts
    /// at target slot.
    func test_resolveBoardReorder_toInbox_stripsStatusAndOrders() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let inboxA = makeTask(id: "i-a", lists: [ios])
        let inboxB = makeTask(id: "i-b", lists: [ios])
        let doingX = makeTask(id: "d-x", lists: [ios, doing])

        let columns = getProjectBoardColumns([ios, doing])
        let inboxColumn = columns.first { $0.id == VIRTUAL_INBOX_COLUMN_ID }!

        let result = resolveBoardReorder(
            task: doingX,
            targetColumn: inboxColumn,
            targetIndex: 1,
            projectId: projectId,
            lists: [ios, doing],
            allTasks: [inboxA, inboxB, doingX],
            currentManualOrder: ["i-a", "i-b", "d-x"]
        )
        XCTAssertFalse(result.listIds.contains("doing"))
        XCTAssertTrue(result.listIds.contains("ios"))
        XCTAssertFalse(result.completed)
        let positions = ["i-a", "d-x", "i-b"].compactMap { id in result.newManualOrder.firstIndex(of: id) }
        XCTAssertEqual(positions, positions.sorted(),
                       "Expected d-x between i-a and i-b; got \(result.newManualOrder)")
    }

    // MARK: - isTaskAlreadyInColumn (drag-drop reliability)

    /// Task currently in Doing dropped on Doing → no-op. Short-circuits
    /// the network round-trip so the cell doesn't flicker.
    func test_isTaskAlreadyInColumn_droppedOnOwnStatusColumn_isTrue() {
        let ios = makeList(id: "ios", name: "iOS", projectId: "project-1", listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let t = makeTask(lists: [ios, doing])

        let columns = getProjectBoardColumns([ios, doing])
        let doingColumn = columns.first { $0.id == "doing" }!
        XCTAssertTrue(isTaskAlreadyInColumn(t, targetColumn: doingColumn,
                                            lists: [ios, doing]))
    }

    /// Inbox task dropped on Doing → not a no-op (real move).
    func test_isTaskAlreadyInColumn_inboxDroppedOnDoing_isFalse() {
        let ios = makeList(id: "ios", name: "iOS", projectId: "project-1", listType: "regular")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")
        let t = makeTask(lists: [ios])

        let columns = getProjectBoardColumns([ios, doing])
        let doingColumn = columns.first { $0.id == "doing" }!
        XCTAssertFalse(isTaskAlreadyInColumn(t, targetColumn: doingColumn,
                                             lists: [ios, doing]))
    }

    /// Completed task dropped on Done → no-op (already in virtual Done).
    func test_isTaskAlreadyInColumn_completedDroppedOnDone_isTrue() {
        let ios = makeList(id: "ios", name: "iOS", projectId: "project-1", listType: "regular")
        let t = makeTask(lists: [ios], completed: true)

        let columns = getProjectBoardColumns([ios])
        let doneColumn = columns.first { $0.id == VIRTUAL_DONE_COLUMN_ID }!
        XCTAssertTrue(isTaskAlreadyInColumn(t, targetColumn: doneColumn,
                                            lists: [ios]))
    }

    // MARK: - BoardCardPayload (typed drag-drop)

    /// The custom Transferable round-trips through JSON encoding.
    func test_boardCardPayload_codableRoundTrip() throws {
        let original = BoardCardPayload(taskId: "task-abc-123")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BoardCardPayload.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - boardColumnsVisible (iPad landscape: 3-5 columns)

    func test_columnsVisible_iPhonePortrait_isOne() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 390), 1)
    }

    func test_columnsVisible_iPhoneLandscape_isTwo() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 752), 2)
    }

    func test_columnsVisible_iPadMiniPortrait_isTwo() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 744), 2)
    }

    func test_columnsVisible_iPadStandardLandscape_isThree() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 1080), 3)
    }

    func test_columnsVisible_iPadProLandscape_isFour() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 1366), 4)
    }

    func test_columnsVisible_isClampedToFive() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 3000), 5)
    }

    func test_columnsVisible_handlesZeroOrNegativeWidth() {
        XCTAssertEqual(boardColumnsVisible(availableWidth: 0), 1)
        XCTAssertEqual(boardColumnsVisible(availableWidth: -10), 1)
    }

    // MARK: - Board create / disable: local list-state mirroring

    /// Creating a board get-or-creates the user's global Ready/Doing/
    /// Waiting status lists; the helper merges them into the in-memory
    /// list array so the board's columns render before the next sync.
    func test_applyProjectStatusLists_addsGlobalStatusLists() {
        let ios = makeList(id: "ios", name: "iOS", projectId: "p-1", listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready", statusOrder: 0)
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing", statusOrder: 1)

        let result = applyProjectStatusLists([ios], adding: [ready, doing])
        XCTAssertEqual(Set(result.map { $0.id }), ["ios", "ready", "doing"])
    }

    /// Idempotent — a status list already present (by id) is not
    /// duplicated when the helper runs again.
    func test_applyProjectStatusLists_isIdempotent() {
        let ios = makeList(id: "ios", name: "iOS", projectId: "p-1", listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")

        let once = applyProjectStatusLists([ios], adding: [ready])
        let twice = applyProjectStatusLists(once, adding: [ready])
        XCTAssertEqual(once.map { $0.id }, twice.map { $0.id })
        XCTAssertEqual(twice.filter { $0.id == "ready" }.count, 1)
    }

    /// Non-status lists in the `adding` set are ignored.
    func test_applyProjectStatusLists_ignoresNonStatusLists() {
        let ios = makeList(id: "ios", name: "iOS", projectId: "p-1", listType: "regular")
        let other = makeList(id: "other", name: "Other", projectId: "p-1", listType: "regular")
        let result = applyProjectStatusLists([ios], adding: [other])
        XCTAssertEqual(result.map { $0.id }, ["ios"])
    }

    /// Disabling a board deletes the project: its domain (regular) list
    /// is detached — projectId cleared, the list itself kept. Status
    /// lists are per-user globals and survive the deletion untouched.
    func test_applyProjectDeletion_keepsGlobalStatusLists_detachesDomainList() {
        let projectId = "p-1"
        let ios = makeList(id: "ios", name: "iOS", projectId: projectId, listType: "regular")
        let ready = makeStatusList(id: "ready", name: "Ready", statusRole: "ready")
        let doing = makeStatusList(id: "doing", name: "Doing", statusRole: "doing")

        let result = applyProjectDeletion([ios, ready, doing], deletedProjectId: projectId)
        XCTAssertEqual(Set(result.map { $0.id }), ["ios", "ready", "doing"],
                       "Global status lists survive; domain list kept")
        XCTAssertNil(result.first { $0.id == "ios" }?.projectId,
                     "Domain list detached — projectId cleared")
    }

    /// Lists belonging to OTHER projects (or no project) are untouched.
    func test_applyProjectDeletion_leavesOtherProjectsListsAlone() {
        let groceries = makeList(id: "groc", name: "Groceries", listType: "regular")
        let otherDomain = makeList(id: "od", name: "Other", projectId: "p-2", listType: "regular")
        let globalStatus = makeStatusList(id: "gs", name: "Doing", statusRole: "doing")
        let deadDomain = makeList(id: "dd", name: "Dead", projectId: "p-1", listType: "regular")

        let result = applyProjectDeletion(
            [groceries, otherDomain, globalStatus, deadDomain],
            deletedProjectId: "p-1"
        )
        XCTAssertEqual(result.map { $0.id }, ["groc", "od", "gs", "dd"])
        XCTAssertEqual(result.first { $0.id == "od" }?.projectId, "p-2")
        XCTAssertNil(result.first { $0.id == "groc" }?.projectId)
        XCTAssertNil(result.first { $0.id == "dd" }?.projectId,
                     "p-1's domain list detached, not deleted")
    }

    // MARK: - Status as a state on the task (AWTD-562)

    /// Swift port of the web tests added with `Task.statusRole`. Status stopped
    /// being list membership because that model could not be both per-user (or
    /// pickers filled with duplicate Ready/Doing/Waiting) and shared (or two
    /// members of a board resolved different columns). As a field on the shared
    /// task both hold.
    ///
    /// These also pin the BACKWARDS COMPATIBILITY this build depends on: a
    /// deployment older than the field does not send it, so membership must
    /// still resolve the column.

    func test_statusRoleField_winsOverMembership() {
        let ready = makeList(id: "ready", name: "Ready", listType: "status", statusRole: "ready", statusOrder: 0)
        let doing = makeList(id: "doing", name: "Doing", listType: "status", statusRole: "doing", statusOrder: 1)
        // Membership says Ready, the field says Doing. The field is authoritative.
        let task = makeTask(lists: [ready], statusRole: "doing")
        XCTAssertEqual(getTaskProjectColumnId(task, lists: [ready, doing]), "doing")
    }

    func test_backwardsCompatible_membershipStillResolvesWhenFieldIsAbsent() {
        // An older server sends no statusRole at all. The board must still work.
        let ready = makeList(id: "ready", name: "Ready", listType: "status", statusRole: "ready", statusOrder: 0)
        let task = makeTask(lists: [ready], statusRole: nil)
        XCTAssertEqual(getTaskProjectColumnId(task, lists: [ready]), "ready")
    }

    func test_emptyStatusRoleIsTreatedAsAbsent() {
        let ready = makeList(id: "ready", name: "Ready", listType: "status", statusRole: "ready", statusOrder: 0)
        let task = makeTask(lists: [ready], statusRole: "")
        XCTAssertEqual(getTaskProjectColumnId(task, lists: [ready]), "ready")
    }

    func test_completedWinsOverStatusRole() {
        let doing = makeList(id: "doing", name: "Doing", listType: "status", statusRole: "doing", statusOrder: 1)
        let task = makeTask(lists: [doing], completed: true, statusRole: "doing")
        XCTAssertEqual(getTaskProjectColumnId(task, lists: [doing]), VIRTUAL_DONE_COLUMN_ID)
    }

    func test_unrenderableStatusFallsBackToInboxRatherThanVanishing() {
        // 'blocked' has no backing status list, which is every custom state
        // until they have one. Returning the bare role would match no column
        // and the card would disappear from the board entirely.
        let ready = makeList(id: "ready", name: "Ready", listType: "status", statusRole: "ready", statusOrder: 0)
        let task = makeTask(lists: [ready], statusRole: "blocked")
        XCTAssertEqual(getTaskProjectColumnId(task, lists: [ready]), VIRTUAL_INBOX_COLUMN_ID)
    }

    func test_everyResolvedColumnIdIsOneTheBoardRenders() {
        // The invariant behind the fallback above.
        let ready = makeList(id: "ready", name: "Ready", listType: "status", statusRole: "ready", statusOrder: 0)
        let lists = [ready]
        let columnIds = Set(getProjectBoardColumns(lists).map { $0.id })
        for role in ["ready", "blocked", "doing"] {
            let task = makeTask(lists: lists, statusRole: role)
            XCTAssertTrue(
                columnIds.contains(getTaskProjectColumnId(task, lists: lists)),
                "resolved a column the board does not render for role \(role)"
            )
        }
    }

    // MARK: - Move writes the field as well as the membership

    func test_moveToStatusReportsTheRoleToWrite() {
        let ready = makeList(id: "ready", name: "Ready", listType: "status", statusRole: "ready", statusOrder: 0)
        let doing = makeList(id: "doing", name: "Doing", listType: "status", statusRole: "doing", statusOrder: 1)
        let domain = makeList(id: "domain", name: "Board", projectId: "p1")
        let task = makeTask(lists: [domain, ready])

        let columns = getProjectBoardColumns([ready, doing])
        let target = columns.first { $0.id == "doing" }!
        let move = resolveProjectColumnMove(task, targetColumn: target, lists: [ready, doing, domain])

        XCTAssertEqual(move.statusRole, "doing")
        // Dual-write: membership is still updated for older servers.
        XCTAssertTrue(move.listIds.contains("doing"))
        XCTAssertFalse(move.listIds.contains("ready"))
        XCTAssertTrue(move.listIds.contains("domain"))
        XCTAssertFalse(move.completed)
    }

    func test_moveToInboxClearsTheRole() {
        let doing = makeList(id: "doing", name: "Doing", listType: "status", statusRole: "doing", statusOrder: 1)
        let domain = makeList(id: "domain", name: "Board", projectId: "p1")
        let task = makeTask(lists: [domain, doing])

        let columns = getProjectBoardColumns([doing])
        let inbox = columns.first { $0.kind == .inbox }!
        let move = resolveProjectColumnMove(task, targetColumn: inbox, lists: [doing, domain])

        XCTAssertNil(move.statusRole)
        XCTAssertFalse(move.listIds.contains("doing"))
        XCTAssertFalse(move.completed)
    }

    func test_moveToDoneClearsTheRoleAndCompletes() {
        // Done carries no status — the same invariant the server enforces.
        let doing = makeList(id: "doing", name: "Doing", listType: "status", statusRole: "doing", statusOrder: 1)
        let domain = makeList(id: "domain", name: "Board", projectId: "p1")
        let task = makeTask(lists: [domain, doing])

        let columns = getProjectBoardColumns([doing])
        let done = columns.first { $0.kind == .done }!
        let move = resolveProjectColumnMove(task, targetColumn: done, lists: [doing, domain])

        XCTAssertNil(move.statusRole)
        XCTAssertFalse(move.listIds.contains("doing"))
        XCTAssertTrue(move.completed)
    }
}
