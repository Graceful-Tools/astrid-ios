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
}
