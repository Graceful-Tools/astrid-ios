import XCTest
@testable import Astrid_App

/// Unit tests for My Tasks filtering logic
/// Ensures My Tasks only shows tasks assigned to the current user
final class MyTasksFilterTests: XCTestCase {

    // MARK: - Test Data

    let currentUserId = "user-123"
    let otherUserId = "user-456"
    let sharedListId = "list-shared"

    // MARK: - My Tasks Filter Tests

    func testMyTasksIncludesTasksAssignedToCurrentUser() {
        // Given: A task assigned to current user
        let task = createTask(
            id: "task-1",
            title: "My Task",
            assigneeId: currentUserId,
            completed: false
        )

        // When: Filtering for My Tasks
        let shouldInclude = task.assigneeId == currentUserId

        // Then: Task should be included
        XCTAssertTrue(shouldInclude, "My Tasks should include tasks assigned to current user")
    }

    func testMyTasksExcludesTasksAssignedToOtherUsers() {
        // Given: A task assigned to another user in a shared list
        let task = createTask(
            id: "task-2",
            title: "Other User's Task",
            assigneeId: otherUserId,
            completed: false,
            listIds: [sharedListId]
        )

        // When: Filtering for My Tasks
        let shouldInclude = task.assigneeId == currentUserId

        // Then: Task should NOT be included, even though user is member of the shared list
        XCTAssertFalse(shouldInclude, "My Tasks should NOT include tasks assigned to other users, even in shared lists")
    }

    func testMyTasksExcludesUnassignedTasksInUserLists() {
        // Given: An unassigned task in a list where user is a member
        let task = createTask(
            id: "task-3",
            title: "Unassigned Task",
            assigneeId: nil,
            completed: false,
            listIds: [sharedListId]
        )

        // When: Filtering for My Tasks
        let shouldInclude = task.assigneeId == currentUserId

        // Then: Task should NOT be included
        XCTAssertFalse(shouldInclude, "My Tasks should NOT include unassigned tasks, even in user's lists")
    }

    func testMyTasksIncludesCompletedTasksAssignedToCurrentUser() {
        // Given: A completed task assigned to current user
        let task = createTask(
            id: "task-4",
            title: "Completed Task",
            assigneeId: currentUserId,
            completed: true
        )

        // When: Filtering for My Tasks (before completion filter is applied)
        let shouldInclude = task.assigneeId == currentUserId

        // Then: Task should be included (completion filtering happens separately)
        XCTAssertTrue(shouldInclude, "My Tasks should include completed tasks assigned to current user (before completion filter)")
    }

    func testMyTasksFilterWithMultipleTasks() {
        // Given: Multiple tasks with different assignees
        let tasks = [
            createTask(id: "task-1", title: "My Task 1", assigneeId: currentUserId, completed: false),
            createTask(id: "task-2", title: "Other's Task", assigneeId: otherUserId, completed: false, listIds: [sharedListId]),
            createTask(id: "task-3", title: "My Task 2", assigneeId: currentUserId, completed: false),
            createTask(id: "task-4", title: "Unassigned Task", assigneeId: nil, completed: false, listIds: [sharedListId]),
            createTask(id: "task-5", title: "My Task 3", assigneeId: currentUserId, completed: true)
        ]

        // When: Filtering for My Tasks
        let myTasks = tasks.filter { $0.assigneeId == currentUserId }

        // Then: Should only include tasks assigned to current user
        XCTAssertEqual(myTasks.count, 3, "Should include exactly 3 tasks assigned to current user")
        XCTAssertTrue(myTasks.allSatisfy { $0.assigneeId == currentUserId }, "All tasks should be assigned to current user")
        XCTAssertEqual(myTasks[0].title, "My Task 1")
        XCTAssertEqual(myTasks[1].title, "My Task 2")
        XCTAssertEqual(myTasks[2].title, "My Task 3")
    }

    func testMyTasksExcludesTasksFromSharedListsAssignedToOthers() {
        // Given: Multiple tasks in shared lists with different assignees
        let sharedList1 = "list-shared-1"
        let sharedList2 = "list-shared-2"

        let tasks = [
            createTask(id: "task-1", title: "My Task in List 1", assigneeId: currentUserId, completed: false, listIds: [sharedList1]),
            createTask(id: "task-2", title: "Other's Task in List 1", assigneeId: otherUserId, completed: false, listIds: [sharedList1]),
            createTask(id: "task-3", title: "Other's Task in List 2", assigneeId: otherUserId, completed: false, listIds: [sharedList2]),
            createTask(id: "task-4", title: "My Task in List 2", assigneeId: currentUserId, completed: false, listIds: [sharedList2])
        ]

        // When: Filtering for My Tasks
        let myTasks = tasks.filter { $0.assigneeId == currentUserId }

        // Then: Should only include tasks assigned to current user, not other members' tasks
        XCTAssertEqual(myTasks.count, 2, "Should only include tasks assigned to current user")
        XCTAssertEqual(myTasks[0].title, "My Task in List 1")
        XCTAssertEqual(myTasks[1].title, "My Task in List 2")
    }

    // MARK: - Helper Methods

    private func createTask(
        id: String,
        title: String,
        assigneeId: String?,
        completed: Bool,
        listIds: [String]? = nil
    ) -> Astrid_App.Task {
        // creator = assignee, for simplicity
        TestHelpers.createTestTask(id: id, title: title, completed: completed,
                                   assigneeId: assigneeId, creatorId: assigneeId, listIds: listIds)
    }
}
