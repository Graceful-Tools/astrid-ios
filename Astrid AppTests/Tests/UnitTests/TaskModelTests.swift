import XCTest
@testable import Astrid_App

/// Unit tests for Task model and related types
/// Tests priority, repeating enums, and task properties
final class TaskModelTests: XCTestCase {

    // MARK: - Priority Tests

    func testPriorityRawValues() {
        XCTAssertEqual(Task.Priority.none.rawValue, 0)
        XCTAssertEqual(Task.Priority.low.rawValue, 1)
        XCTAssertEqual(Task.Priority.medium.rawValue, 2)
        XCTAssertEqual(Task.Priority.high.rawValue, 3)
    }

    func testPriorityDisplayNames() {
        XCTAssertEqual(Task.Priority.none.displayName, "None")
        XCTAssertEqual(Task.Priority.low.displayName, "Low")
        XCTAssertEqual(Task.Priority.medium.displayName, "Medium")
        XCTAssertEqual(Task.Priority.high.displayName, "High")
    }

    func testPriorityColors() {
        XCTAssertEqual(Task.Priority.none.color, "gray")
        XCTAssertEqual(Task.Priority.low.color, "#10b981")
        XCTAssertEqual(Task.Priority.medium.color, "#f59e0b")
        XCTAssertEqual(Task.Priority.high.color, "#ef4444")
    }

    func testPriorityAllCases() {
        // Verify all cases are present
        XCTAssertEqual(Task.Priority.allCases.count, 4)
        XCTAssertTrue(Task.Priority.allCases.contains(.none))
        XCTAssertTrue(Task.Priority.allCases.contains(.low))
        XCTAssertTrue(Task.Priority.allCases.contains(.medium))
        XCTAssertTrue(Task.Priority.allCases.contains(.high))
    }

    // MARK: - Repeating Tests

    func testRepeatingRawValues() {
        XCTAssertEqual(Task.Repeating.never.rawValue, "never")
        XCTAssertEqual(Task.Repeating.daily.rawValue, "daily")
        XCTAssertEqual(Task.Repeating.weekly.rawValue, "weekly")
        XCTAssertEqual(Task.Repeating.monthly.rawValue, "monthly")
        XCTAssertEqual(Task.Repeating.yearly.rawValue, "yearly")
        XCTAssertEqual(Task.Repeating.custom.rawValue, "custom")
    }

    func testRepeatingDisplayNames() {
        // Assert against the LOCALIZED value, not an English literal: the enum is localized now
        // (1d149492), and a literal assertion only passes in an English simulator — which is
        // exactly how the missing translations went unnoticed.
        XCTAssertEqual(Task.Repeating.never.displayName,
                       NSLocalizedString("repeating.one_time_only", comment: ""))
        XCTAssertEqual(Task.Repeating.daily.displayName,
                       NSLocalizedString("repeating.daily", comment: ""))
        XCTAssertEqual(Task.Repeating.weekly.displayName,
                       NSLocalizedString("repeating.weekly", comment: ""))
        XCTAssertEqual(Task.Repeating.monthly.displayName,
                       NSLocalizedString("repeating.monthly", comment: ""))
        XCTAssertEqual(Task.Repeating.yearly.displayName,
                       NSLocalizedString("repeating.yearly", comment: ""))
        XCTAssertEqual(Task.Repeating.custom.displayName,
                       NSLocalizedString("repeating.custom", comment: ""))

        // And every one of them RESOLVES — an unresolved key returns the key itself, which is
        // the failure this test exists to catch.
        for pattern in Task.Repeating.allCases {
            XCTAssertFalse(pattern.displayName.hasPrefix("repeating."),
                           "\(pattern.rawValue) has no translation")
        }
    }

    func testRepeatingAllCases() {
        XCTAssertEqual(Task.Repeating.allCases.count, 6)
    }

    // MARK: - RepeatFromMode Tests

    func testRepeatFromModeRawValues() {
        XCTAssertEqual(Task.RepeatFromMode.DUE_DATE.rawValue, "DUE_DATE")
        XCTAssertEqual(Task.RepeatFromMode.COMPLETION_DATE.rawValue, "COMPLETION_DATE")
    }

    func testRepeatFromModeDisplayNames() {
        XCTAssertEqual(Task.RepeatFromMode.DUE_DATE.displayName, "Repeat from due date")
        XCTAssertEqual(Task.RepeatFromMode.COMPLETION_DATE.displayName, "Repeat from completion date")
    }

    // MARK: - ReminderType Tests

    func testReminderTypeRawValues() {
        XCTAssertEqual(Task.ReminderType.push.rawValue, "push")
        XCTAssertEqual(Task.ReminderType.email.rawValue, "email")
        XCTAssertEqual(Task.ReminderType.both.rawValue, "both")
    }

    // MARK: - Task Creation Tests

    func testCreateMinimalTask() {
        let task = Task(
            id: "test-123",
            title: "Test Task",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        XCTAssertEqual(task.id, "test-123")
        XCTAssertEqual(task.title, "Test Task")
        XCTAssertEqual(task.priority, .none)
        XCTAssertFalse(task.completed)
        XCTAssertFalse(task.isPrivate)
        XCTAssertTrue(task.isAllDay)
        XCTAssertNil(task.dueDateTime)
        XCTAssertNil(task.repeating)
    }

    func testCreateTaskWithAllFields() {
        let now = Date()
        let dueDate = Calendar.current.date(byAdding: .day, value: 1, to: now)!

        let user = User(
            id: "user-123",
            email: "test@example.com",
            name: "Test User",
            image: nil,
            createdAt: now,
            defaultDueTime: nil,
            isPending: nil,
            isAIAgent: nil,
            aiAgentType: nil
        )

        let list = TestHelpers.createTestList(id: "list-123", name: "Test List", ownerId: "user-123")

        let task = Task(
            id: "task-full-123",
            title: "Full Task",
            description: "A complete task with all fields",
            assigneeId: "user-123",
            assignee: user,
            creatorId: "user-123",
            creator: user,
            dueDateTime: dueDate,
            isAllDay: false,
            reminderTime: dueDate.addingTimeInterval(-3600),
            reminderSent: false,
            reminderType: .push,
            repeating: .weekly,
            repeatingData: nil,
            repeatFrom: .DUE_DATE,
            occurrenceCount: 3,
            priority: .high,
            lists: [list],
            listIds: ["list-123"],
            isPrivate: true,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: now,
            updatedAt: now,
            originalTaskId: nil,
            sourceListId: "list-123"
        )

        XCTAssertEqual(task.id, "task-full-123")
        XCTAssertEqual(task.title, "Full Task")
        XCTAssertEqual(task.description, "A complete task with all fields")
        XCTAssertEqual(task.assigneeId, "user-123")
        XCTAssertNotNil(task.assignee)
        XCTAssertEqual(task.dueDateTime, dueDate)
        XCTAssertFalse(task.isAllDay)
        XCTAssertEqual(task.repeating, .weekly)
        XCTAssertEqual(task.repeatFrom, .DUE_DATE)
        XCTAssertEqual(task.occurrenceCount, 3)
        XCTAssertEqual(task.priority, .high)
        XCTAssertTrue(task.isPrivate)
        XCTAssertEqual(task.lists?.count, 1)
        XCTAssertEqual(task.listIds?.count, 1)
    }

    // MARK: - Task Extension Tests

    func testEffectiveCreatorIdWithCreatorId() {
        let task = Task(
            id: "task-1",
            title: "Test",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: "creator-123",
            creator: nil,
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        XCTAssertEqual(task.effectiveCreatorId, "creator-123")
    }

    func testEffectiveCreatorIdWithCreatorObject() {
        let creator = TestHelpers.createTestUser(id: "creator-from-object", name: "Creator", email: "creator@example.com")

        let task = Task(
            id: "task-1",
            title: "Test",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,  // No creatorId
            creator: creator,  // But has creator object
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        XCTAssertEqual(task.effectiveCreatorId, "creator-from-object")
    }

    func testIsCreatedBy() {
        let task = Task(
            id: "task-1",
            title: "Test",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: "user-abc",
            creator: nil,
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        XCTAssertTrue(task.isCreatedBy("user-abc"))
        XCTAssertFalse(task.isCreatedBy("user-xyz"))
        XCTAssertFalse(task.isCreatedBy(""))
    }

    func testAllSecureFiles() {
        let file1 = SecureFile(id: "file-1", name: "file1.jpg", size: 100, mimeType: "image/jpeg")
        let file2 = SecureFile(id: "file-2", name: "file2.pdf", size: 200, mimeType: "application/pdf")
        let file3 = SecureFile(id: "file-3", name: "file3.png", size: 300, mimeType: "image/png")
        
        let comment1 = Comment(
            id: "c1",
            content: "Comment 1",
            type: .TEXT,
            authorId: "u1",
            taskId: "t1",
            secureFiles: [file1]
        )
        
        let comment2 = Comment(
            id: "c2",
            content: "Comment 2",
            type: .TEXT,
            authorId: "u1",
            taskId: "t1",
            secureFiles: [file1, file2] // file1 is duplicate
        )
        
        let task = Task(
            id: "t1",
            title: "Task 1",
            description: "",
            secureFiles: [file3], // Direct attachment
            comments: [comment1, comment2]
        )
        
        let allFiles = task.allSecureFiles
        XCTAssertEqual(allFiles.count, 3)
        XCTAssertTrue(allFiles.contains(where: { $0.id == "file-1" }))
        XCTAssertTrue(allFiles.contains(where: { $0.id == "file-2" }))
        XCTAssertTrue(allFiles.contains(where: { $0.id == "file-3" }))
    }

    func testAllSecureFilesWithLegacyAttachments() {
        let att = Attachment(id: "att-1", name: "legacy.jpg", url: "...", type: "image/jpeg", size: 500)
        let file1 = SecureFile(id: "file-1", name: "new.jpg", size: 100, mimeType: "image/jpeg")
        
        let task = Task(
            id: "t1",
            title: "Task 1",
            attachments: [att],
            secureFiles: [file1]
        )
        
        let allFiles = task.allSecureFiles
        XCTAssertEqual(allFiles.count, 2)
        XCTAssertTrue(allFiles.contains(where: { $0.id == "att-1" }))
        XCTAssertTrue(allFiles.contains(where: { $0.id == "file-1" }))
        
        if let legacyFile = allFiles.first(where: { $0.id == "att-1" }) {
            XCTAssertEqual(legacyFile.name, "legacy.jpg")
            XCTAssertEqual(legacyFile.mimeType, "image/jpeg")
        }
    }

    // MARK: - CustomRepeatingPattern Tests

    func testCustomRepeatingPatternDaily() {
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "days",
            interval: 3,
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        XCTAssertEqual(pattern.type, "custom")
        XCTAssertEqual(pattern.unit, "days")
        XCTAssertEqual(pattern.interval, 3)
        XCTAssertEqual(pattern.endCondition, "never")
    }

    func testCustomRepeatingPatternWeekly() {
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: 2,
            endCondition: "after_occurrences",
            endAfterOccurrences: 10,
            endUntilDate: nil,
            weekdays: ["monday", "wednesday", "friday"],
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: nil,
            day: nil
        )

        XCTAssertEqual(pattern.unit, "weeks")
        XCTAssertEqual(pattern.interval, 2)
        XCTAssertEqual(pattern.weekdays?.count, 3)
        XCTAssertTrue(pattern.weekdays?.contains("monday") ?? false)
        XCTAssertTrue(pattern.weekdays?.contains("wednesday") ?? false)
        XCTAssertTrue(pattern.weekdays?.contains("friday") ?? false)
        XCTAssertEqual(pattern.endCondition, "after_occurrences")
        XCTAssertEqual(pattern.endAfterOccurrences, 10)
    }

    func testCustomRepeatingPatternMonthly() {
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "months",
            interval: 1,
            endCondition: "until_date",
            endAfterOccurrences: nil,
            endUntilDate: Date(),
            weekdays: nil,
            monthRepeatType: "same_weekday",
            monthDay: nil,
            monthWeekday: CustomRepeatingPattern.MonthWeekday(weekday: "tuesday", weekOfMonth: 2),
            month: nil,
            day: nil
        )

        XCTAssertEqual(pattern.unit, "months")
        XCTAssertEqual(pattern.monthRepeatType, "same_weekday")
        XCTAssertEqual(pattern.monthWeekday?.weekday, "tuesday")
        XCTAssertEqual(pattern.monthWeekday?.weekOfMonth, 2)
        XCTAssertEqual(pattern.endCondition, "until_date")
        XCTAssertNotNil(pattern.endUntilDate)
    }

    func testCustomRepeatingPatternYearly() {
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "years",
            interval: 1,
            endCondition: "never",
            endAfterOccurrences: nil,
            endUntilDate: nil,
            weekdays: nil,
            monthRepeatType: nil,
            monthDay: nil,
            monthWeekday: nil,
            month: 12,
            day: 25
        )

        XCTAssertEqual(pattern.unit, "years")
        XCTAssertEqual(pattern.month, 12)
        XCTAssertEqual(pattern.day, 25)
    }

    // MARK: - Task Equatable Tests

    @MainActor func testTaskEquality() {
        let task1 = Task(
            id: "same-id",
            title: "Task",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        let task2 = Task(
            id: "same-id",
            title: "Task",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        XCTAssertEqual(task1, task2)
    }

    @MainActor func testTaskHashable() {
        let task = Task(
            id: "hash-test",
            title: "Task",
            description: "",
            assigneeId: nil,
            assignee: nil,
            creatorId: nil,
            creator: nil,
            dueDateTime: nil,
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: nil,
            repeatingData: nil,
            repeatFrom: nil,
            occurrenceCount: nil,
            priority: .none,
            lists: nil,
            listIds: nil,
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: nil,
            updatedAt: nil,
            originalTaskId: nil,
            sourceListId: nil
        )

        // Task should be usable in a Set
        var taskSet = Set<Task>()
        taskSet.insert(task)
        XCTAssertTrue(taskSet.contains(task))
    }
}
