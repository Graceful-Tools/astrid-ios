//  ServiceWritePathTests.swift
//  The TaskService and ListService writes the 2026-10-22 coverage audit found unexecuted
//  (AITD-535), driven the way the views drive them. The unit-test host runs astrid-core in memory
//  with no network, so each write lands in the core's cache and journal and nothing leaves the
//  machine.

import XCTest
@testable import Astrid_App

@MainActor
final class TaskServiceWritePathTests: XCTestCase {
    private var service: TaskService { TaskService.shared }

    private static func utc(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func title(_ name: String) -> String { "\(name) \(UUID().uuidString)" }

    // MARK: createTask — the due date it derives (TaskService.swift createTask)

    /// A date alone is an all-day task, stored as UTC midnight of that day — whatever the hour of
    /// the `Date` the picker handed over.
    func testADateAloneIsAllDayAtUTCMidnight_AITD535() async throws {
        let made = try await service.createTask(
            listIds: [], title: title("All day"), whenDate: Self.utc("2026-03-15T22:30:00Z"))

        XCTAssertEqual(made.dueDateTime, Self.utc("2026-03-15T00:00:00Z"))
        XCTAssertTrue(made.isAllDay)
    }

    /// A time makes it a timed task at exactly that moment, even with a date alongside.
    func testATimeIsATimedTaskAtThatMoment_AITD535() async throws {
        let made = try await service.createTask(
            listIds: [], title: title("Timed"),
            whenDate: Self.utc("2026-03-15T00:00:00Z"), whenTime: Self.utc("2026-03-15T14:45:00Z"))

        XCTAssertEqual(made.dueDateTime, Self.utc("2026-03-15T14:45:00Z"))
        XCTAssertFalse(made.isAllDay)
    }

    func testNeitherDateNorTimeIsNoDueDate_AITD535() async throws {
        let made = try await service.createTask(listIds: [], title: title("Undated"))

        XCTAssertNil(made.dueDateTime)
        XCTAssertFalse(made.isAllDay)
    }

    /// A history import (sync) is born completed and backdated, so the row never shows open.
    func testPresumeCompletedAtCreatesItCompletedAndBackdated_AITD535() async throws {
        let when = Self.utc("2026-01-02T03:04:05Z")
        let made = try await service.createTask(
            listIds: [], title: title("Imported"), presumeCompletedAt: when)

        XCTAssertTrue(made.completed)
        XCTAssertEqual(made.completedAt, when)
        XCTAssertEqual(service.tasksById[made.id]?.completed, true)
    }

    // MARK: updateTask — "" clears (TaskService.swift updateTask → TaskEdit)

    func testAnEmptyAssigneeUnassigns_AITD535() async throws {
        let made = try await service.createTask(listIds: [], title: title("Assign"))
        let assigned = try await service.updateTask(taskId: made.id, assigneeId: "user-a")
        XCTAssertEqual(assigned.assigneeId, "user-a")

        let cleared = try await service.updateTask(taskId: made.id, assigneeId: "")
        XCTAssertNil(cleared.assigneeId)
        XCTAssertNil(service.tasksById[made.id]?.assigneeId, "the row the list draws is unassigned")
    }

    func testAnEmptyParentPromotesASubtask_AITD535() async throws {
        let parent = try await service.createTask(listIds: [], title: title("Parent"))
        let child = try await service.createTask(listIds: [], title: title("Child"))

        let nested = try await service.updateTask(taskId: child.id, parentTaskId: parent.id)
        XCTAssertEqual(nested.parentTaskId, parent.id)

        let promoted = try await service.updateTask(taskId: child.id, parentTaskId: "")
        XCTAssertNil(promoted.parentTaskId)
    }

    /// An all-day `dueDateTime` edit is normalised to UTC midnight; a timed one is kept as given.
    func testADueDateEditNormalisesOnlyAllDay_AITD535() async throws {
        let made = try await service.createTask(listIds: [], title: title("Redate"))

        let allDay = try await service.updateTask(
            taskId: made.id, dueDateTime: Self.utc("2026-05-01T18:00:00Z"), isAllDay: true)
        XCTAssertEqual(allDay.dueDateTime, Self.utc("2026-05-01T00:00:00Z"))
        XCTAssertTrue(allDay.isAllDay)

        let timed = try await service.updateTask(
            taskId: made.id, dueDateTime: Self.utc("2026-05-01T18:00:00Z"), isAllDay: false)
        XCTAssertEqual(timed.dueDateTime, Self.utc("2026-05-01T18:00:00Z"))
        XCTAssertFalse(timed.isAllDay)

        let cleared = try await service.updateTask(taskId: made.id, dueDateTime: Date.distantPast)
        XCTAssertNil(cleared.dueDateTime)
    }

    // MARK: Lists, copies and filtering

    func testUpdateTaskListsMovesItAndGetTasksForListFindsIt_AITD535() async throws {
        let list = try await ListService.shared.createList(name: title("Home"))
        let made = try await service.createTask(listIds: [], title: title("Move me"))
        XCTAssertFalse(service.getTasksForList(list.id).contains { $0.id == made.id })

        let moved = try await service.updateTaskLists(taskId: made.id, listIds: [list.id])

        XCTAssertEqual(moved.listIds, [list.id])
        XCTAssertEqual(service.getTasksForList(list.id).map(\.id), [made.id])
    }

    /// A copy to a list keeps the title, priority and (when asked) the date, and arrives
    /// unassigned and as a new task.
    func testCopyToAListKeepsTheDateWhenAsked_AITD535() async throws {
        let list = try await ListService.shared.createList(name: title("Target"))
        let original = try await service.createTask(
            listIds: [], title: title("Original"), priority: 2,
            whenDate: Self.utc("2026-07-04T00:00:00Z"), assigneeId: "user-a")

        let kept = try await service.copyTask(id: original.id, targetListId: list.id, preserveDueDate: true)
        XCTAssertNotEqual(kept.id, original.id)
        XCTAssertEqual(kept.title, original.title)
        XCTAssertEqual(kept.priority.rawValue, 2)
        XCTAssertEqual(kept.listIds, [list.id])
        XCTAssertNil(kept.assigneeId, "a copy to a list arrives unassigned")
        XCTAssertEqual(kept.dueDateTime, Self.utc("2026-07-04T00:00:00Z"))
        XCTAssertTrue(kept.isAllDay)

        let dropped = try await service.copyTask(id: original.id, targetListId: list.id)
        XCTAssertNil(dropped.dueDateTime, "without preserveDueDate the copy is undated")
    }

    // MARK: Delivery

    /// Offline there is nothing to send to; asking must neither hang nor leave the flag set.
    func testRetryFailedOperationsLeavesTheSyncFlagClear_AITD535() async {
        await service.retryFailedOperations()
        XCTAssertFalse(service.isSyncingPendingOperations)
    }
}

@MainActor
final class ListServiceWritePathTests: XCTestCase {
    private var service: ListService { ListService.shared }

    private func name(_ base: String) -> String { "\(base) \(UUID().uuidString)" }

    func testCreateListCarriesItsFieldsAndDefaultsTheColor_AITD535() async throws {
        let listName = name("Groceries")
        let made = try await service.createList(name: listName, description: "weekly", privacy: "SHARED")

        XCTAssertEqual(made.name, listName)
        XCTAssertEqual(made.description, "weekly")
        XCTAssertEqual(made.privacy, .SHARED)
        XCTAssertEqual(made.color, "#3b82f6")
        XCTAssertEqual(service.getList(id: made.id)?.name, listName, "every screen reads the new list")
    }

    func testUpdateListRenamesIt_AITD535() async throws {
        let made = try await service.createList(name: name("Before"))
        let renamed = name("After")

        let updated = try await service.updateList(listId: made.id, name: renamed)

        XCTAssertEqual(updated.name, renamed)
        XCTAssertEqual(service.getList(id: made.id)?.name, renamed)
    }

    /// The settings screens clear a field with `NSNull`; anything else is set.
    func testUpdateListAdvancedSetsAndClears_AITD535() async throws {
        let made = try await service.createList(name: name("Settings"), description: "to clear")

        let updated = try await service.updateListAdvanced(
            listId: made.id, updates: ["description": NSNull(), "defaultPriority": 3])

        XCTAssertNil(updated.description)
        XCTAssertEqual(updated.defaultPriority, 3)
    }

    func testFavoriteListTogglesAndReturnsTheList_AITD535() async throws {
        let made = try await service.createList(name: name("Fave"))

        let favored = try await service.favoriteList(listId: made.id, favorite: true)
        XCTAssertEqual(favored.isFavorite, true)
        XCTAssertTrue(service.favoriteLists.contains { $0.id == made.id })

        try await service.toggleFavorite(listId: made.id, isFavorite: false)
        XCTAssertEqual(service.getList(id: made.id)?.isFavorite, false)
        XCTAssertFalse(service.favoriteLists.contains { $0.id == made.id })
    }

    func testUpdateManualOrderStoresTheOrder_AITD535() async throws {
        let list = try await service.createList(name: name("Ordered"))
        let first = try await TaskService.shared.createTask(listIds: [list.id], title: name("first"))
        let second = try await TaskService.shared.createTask(listIds: [list.id], title: name("second"))

        try await service.updateManualOrder(listId: list.id, order: [second.id, first.id])

        XCTAssertEqual(service.getList(id: list.id)?.manualSortOrder, [second.id, first.id])
    }

    func testDeleteListForgetsIt_AITD535() async throws {
        let made = try await service.createList(name: name("Doomed"))

        try await service.deleteList(listId: made.id)

        XCTAssertNil(service.getList(id: made.id))
        XCTAssertFalse(service.lists.contains { $0.id == made.id })
    }

    /// A membership edit the server refused puts the cached list back exactly as it was.
    func testRestoreCachedListPutsTheOriginalBack_AITD535() async throws {
        let made = try await service.createList(name: name("Roster"))
        let original = try XCTUnwrap(service.getList(id: made.id))

        service.applyMemberChange(listId: made.id) { list in
            var changed = list
            changed.name = "optimistic"
            return changed
        }
        XCTAssertEqual(service.getList(id: made.id)?.name, "optimistic")

        service.restoreCachedList(listId: made.id, from: original)
        XCTAssertEqual(service.getList(id: made.id), original)
    }
}
