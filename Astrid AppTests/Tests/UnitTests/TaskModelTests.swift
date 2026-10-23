import XCTest
@testable import Astrid_App

/// Unit tests for Task model and related types
/// Tests priority, repeating enums, and task properties
final class TaskModelTests: XCTestCase {

    // MARK: - Priority Tests

    func testPriorityDisplayNames() {
        XCTAssertEqual(Task.Priority.none.displayName, "None")
        XCTAssertEqual(Task.Priority.low.displayName, "Low")
        XCTAssertEqual(Task.Priority.medium.displayName, "Medium")
        XCTAssertEqual(Task.Priority.high.displayName, "High")
    }

    // MARK: - Repeating Tests

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

    // MARK: - RepeatFromMode Tests

    func testRepeatFromModeDisplayNames() {
        XCTAssertEqual(Task.RepeatFromMode.DUE_DATE.displayName, "Repeat from due date")
        XCTAssertEqual(Task.RepeatFromMode.COMPLETION_DATE.displayName, "Repeat from completion date")
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
        
        let allFiles = task.allSecureFiles()
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
        
        let allFiles = task.allSecureFiles()
        XCTAssertEqual(allFiles.count, 2)
        XCTAssertTrue(allFiles.contains(where: { $0.id == "att-1" }))
        XCTAssertTrue(allFiles.contains(where: { $0.id == "file-1" }))
        
        if let legacyFile = allFiles.first(where: { $0.id == "att-1" }) {
            XCTAssertEqual(legacyFile.name, "legacy.jpg")
            XCTAssertEqual(legacyFile.mimeType, "image/jpeg")
        }
    }
}
