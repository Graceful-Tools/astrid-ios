import XCTest
@testable import Astrid_App

/// Unit tests for task creation functionality
/// Tests task creation in My Tasks, quick priority setting, and task properties
final class TaskCreationTests: XCTestCase {

    // MARK: - Basic Task Creation Tests

    func testCreateTaskWithTitle() {
        // Given: A task with specific title
        let title = "Buy groceries"
        let task = TestHelpers.createTestTask(title: title)

        // Then: Title should be set correctly
        XCTAssertEqual(task.title, title)
    }

    func testCreateTaskWithDescription() {
        // Given: A task with description
        let task = TestHelpers.createTestTask(
            title: "Project Task",
            description: "This is a detailed description of the task"
        )

        // Then: Description should be set
        XCTAssertEqual(task.description, "This is a detailed description of the task")
    }

    // MARK: - Priority Tests (Quick Priority Setting)

    // MARK: - Due Date Tests

    func testCreateTaskWithDueDate() {
        // Given: A task with due date
        let dueDate = TestHelpers.createRelativeDate(daysFromNow: 1)
        let task = TestHelpers.createTestTask(dueDateTime: dueDate)

        // Then: Due date should be set
        XCTAssertEqual(task.dueDateTime, dueDate)
    }

    func testCreateAllDayTask() {
        // Given: An all-day task
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15)
        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            isAllDay: true
        )

        // Then: Should be marked as all-day
        XCTAssertTrue(task.isAllDay)
        XCTAssertNotNil(task.dueDateTime)
    }

    func testCreateTimedTask() {
        // Given: A timed task (not all-day)
        let dueDate = TestHelpers.createDate(year: 2024, month: 6, day: 15, hour: 14, minute: 30)
        let task = TestHelpers.createTestTask(
            dueDateTime: dueDate,
            isAllDay: false
        )

        // Then: Should not be marked as all-day
        XCTAssertFalse(task.isAllDay)
        XCTAssertNotNil(task.dueDateTime)

        // Verify time is preserved
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.hour, from: task.dueDateTime!), 14)
        XCTAssertEqual(calendar.component(.minute, from: task.dueDateTime!), 30)
    }

    // MARK: - Task in List Tests (My Tasks Context)

    func testCreateTaskInList() {
        // Given: A list and a task
        let list = TestHelpers.createTestList(id: "my-list", name: "My Tasks")
        let task = TestHelpers.createTestTask(
            title: "Task in My Tasks",
            listIds: [list.id],
            lists: [list]
        )

        // Then: Task should be associated with list
        XCTAssertEqual(task.listIds?.count, 1)
        XCTAssertEqual(task.listIds?.first, "my-list")
        XCTAssertEqual(task.lists?.count, 1)
        XCTAssertEqual(task.lists?.first?.name, "My Tasks")
    }

    func testCreateTaskInMultipleLists() {
        // Given: Multiple lists
        let list1 = TestHelpers.createTestList(id: "list-1", name: "Work")
        let list2 = TestHelpers.createTestList(id: "list-2", name: "Personal")
        let task = TestHelpers.createTestTask(
            title: "Multi-list Task",
            listIds: [list1.id, list2.id],
            lists: [list1, list2]
        )

        // Then: Task should be in both lists
        XCTAssertEqual(task.listIds?.count, 2)
        XCTAssertTrue(task.listIds?.contains("list-1") ?? false)
        XCTAssertTrue(task.listIds?.contains("list-2") ?? false)
    }

    // MARK: - Task Completion Tests

    func testNewTaskIsNotCompleted() {
        // Given: A new task
        let task = TestHelpers.createTestTask(completed: false)

        // Then: Should not be completed
        XCTAssertFalse(task.completed)
    }

    func testCompletedTask() {
        // Given: A completed task
        let task = TestHelpers.createTestTask(completed: true)

        // Then: Should be completed
        XCTAssertTrue(task.completed)
    }

    // MARK: - Private Task Tests

    func testCreatePublicTask() {
        // Given: A public task (default)
        let task = TestHelpers.createTestTask(isPrivate: false)

        // Then: Should not be private
        XCTAssertFalse(task.isPrivate)
    }

    func testCreatePrivateTask() {
        // Given: A private task
        let task = TestHelpers.createTestTask(isPrivate: true)

        // Then: Should be private
        XCTAssertTrue(task.isPrivate)
    }

    // MARK: - Creator Tests

    // MARK: - Assignee Tests

    func testTaskWithAssignee() {
        // Given: A task with assignee
        let assignee = TestHelpers.createTestUser(id: "assignee-123", name: "Assigned User")
        let task = TestHelpers.createTestTask(
            assigneeId: "assignee-123",
            assignee: assignee
        )

        // Then: Assignee should be set
        XCTAssertEqual(task.assigneeId, "assignee-123")
        XCTAssertNotNil(task.assignee)
        XCTAssertEqual(task.assignee?.name, "Assigned User")
    }

    func testUnassignedTask() {
        // Given: An unassigned task
        let task = TestHelpers.createTestTask(assigneeId: nil, assignee: nil)

        // Then: Assignee should be nil
        XCTAssertNil(task.assigneeId)
        XCTAssertNil(task.assignee)
    }

    // MARK: - Attachments Tests

    func testTaskWithAttachments() {
        // Given: A task with attachments
        let attachment = TestHelpers.createTestAttachment(
            id: "attach-1",
            name: "document.pdf"
        )
        let task = TestHelpers.createTestTask(attachments: [attachment])

        // Then: Attachments should be present
        XCTAssertEqual(task.attachments?.count, 1)
        XCTAssertEqual(task.attachments?.first?.name, "document.pdf")
    }

    func testTaskWithMultipleAttachments() {
        // Given: A task with multiple attachments
        let attach1 = TestHelpers.createTestAttachment(id: "attach-1", name: "doc1.pdf")
        let attach2 = TestHelpers.createTestAttachment(id: "attach-2", name: "image.png")
        let task = TestHelpers.createTestTask(attachments: [attach1, attach2])

        // Then: All attachments should be present
        XCTAssertEqual(task.attachments?.count, 2)
    }

    // MARK: - Comments Tests

    func testTaskWithComments() {
        // Given: A task with comments
        let comment = TestHelpers.createTestComment(
            id: "comment-1",
            content: "This is a comment"
        )
        let task = TestHelpers.createTestTask(comments: [comment])

        // Then: Comments should be present
        XCTAssertEqual(task.comments?.count, 1)
        XCTAssertEqual(task.comments?.first?.content, "This is a comment")
    }

    // MARK: - Timestamp Tests

    func testTaskTimestamps() {
        // Given: A task with timestamps
        let createdAt = Date()
        let updatedAt = Date().addingTimeInterval(3600) // 1 hour later
        let task = TestHelpers.createTestTask(
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        // Then: Timestamps should be set
        XCTAssertEqual(task.createdAt, createdAt)
        XCTAssertEqual(task.updatedAt, updatedAt)
    }

    // MARK: - Source List Tests

    func testTaskWithSourceList() {
        // Given: A task with source list (for cross-list tasks)
        let task = TestHelpers.createTestTask(sourceListId: "source-list-123")

        // Then: Source list should be set
        XCTAssertEqual(task.sourceListId, "source-list-123")
    }

    // MARK: - Original Task Tests (for repeated tasks)

    func testTaskWithOriginalTaskId() {
        // Given: A task that's an instance of a repeating task
        let task = TestHelpers.createTestTask(originalTaskId: "original-task-123")

        // Then: Original task ID should be set
        XCTAssertEqual(task.originalTaskId, "original-task-123")
    }

    // MARK: - Task Equality Tests

    // MARK: - Task Hashable Tests

    @MainActor func testMultipleTasksInSet() {
        // Given: Multiple tasks
        let tasks = [
            TestHelpers.createTestTask(id: "task-1"),
            TestHelpers.createTestTask(id: "task-2"),
            TestHelpers.createTestTask(id: "task-3")
        ]

        // When: Added to set
        let taskSet = Set<Task>(tasks)

        // Then: All should be present
        XCTAssertEqual(taskSet.count, 3)
    }

    // MARK: - Complete Task With Priority Workflow Tests

    func testCreateHighPriorityTaskWorkflow() {
        // Simulates: User creates a high-priority task in My Tasks

        // Given: User info and list
        let currentUser = TestHelpers.createTestUser(id: "current-user", name: "Me")
        let myTasksList = TestHelpers.createTestList(
            id: "my-tasks-list",
            name: "My Tasks",
            privacy: .PRIVATE,
            ownerId: currentUser.id
        )

        // When: Creating a high-priority task
        let task = TestHelpers.createTestTask(
            id: UUID().uuidString,
            title: "Urgent: Complete project report",
            priority: .high,
            dueDateTime: TestHelpers.createRelativeDate(daysFromNow: 1),
            isAllDay: false,
            creatorId: currentUser.id,
            creator: currentUser,
            listIds: [myTasksList.id],
            lists: [myTasksList]
        )

        // Then: Task should be correctly configured
        XCTAssertEqual(task.title, "Urgent: Complete project report")
        XCTAssertEqual(task.priority, .high)
        XCTAssertNotNil(task.dueDateTime)
        XCTAssertFalse(task.isAllDay)
        XCTAssertEqual(task.listIds?.first, myTasksList.id)
        XCTAssertTrue(task.isCreatedBy(currentUser.id))
        XCTAssertFalse(task.completed)
    }
}
