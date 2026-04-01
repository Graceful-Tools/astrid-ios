import XCTest
@testable import Astrid_App

/// Unit tests for comment functionality
/// Tests comment creation, viewing comments from others, and comment types
final class CommentModelTests: XCTestCase {

    // MARK: - Basic Comment Creation Tests

    func testCreateTextComment() {
        // Given: A text comment
        let comment = TestHelpers.createTestComment(
            id: "comment-123",
            content: "This is a test comment",
            type: .TEXT
        )

        // Then: Comment should have correct properties
        XCTAssertEqual(comment.id, "comment-123")
        XCTAssertEqual(comment.content, "This is a test comment")
        XCTAssertEqual(comment.type, .TEXT)
    }

    func testCreateMarkdownComment() {
        // Given: A markdown comment
        let comment = TestHelpers.createTestComment(
            id: "comment-md",
            content: "# Heading\n\n**Bold text** and *italic*",
            type: .MARKDOWN
        )

        // Then: Comment should be markdown type
        XCTAssertEqual(comment.type, .MARKDOWN)
        XCTAssertTrue(comment.content.contains("**Bold text**"))
    }

    func testCreateAttachmentComment() {
        // Given: An attachment comment
        let comment = Comment(
            id: "comment-attach",
            content: "",
            type: .ATTACHMENT,
            authorId: "author-123",
            author: nil,
            taskId: "task-123",
            createdAt: Date(),
            updatedAt: nil,
            attachmentUrl: "https://example.com/file.pdf",
            attachmentName: "document.pdf",
            attachmentType: "application/pdf",
            attachmentSize: 1024000,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        // Then: Attachment details should be set
        XCTAssertEqual(comment.type, .ATTACHMENT)
        XCTAssertEqual(comment.attachmentUrl, "https://example.com/file.pdf")
        XCTAssertEqual(comment.attachmentName, "document.pdf")
        XCTAssertEqual(comment.attachmentType, "application/pdf")
        XCTAssertEqual(comment.attachmentSize, 1024000)
    }

    // MARK: - Comment Author Tests

    func testCommentWithAuthor() {
        // Given: A comment with author
        let author = TestHelpers.createTestUser(id: "author-123", name: "John Doe", email: "john@example.com")
        let comment = TestHelpers.createTestComment(
            content: "Great work!",
            authorId: author.id,
            author: author
        )

        // Then: Author should be set
        XCTAssertEqual(comment.authorId, "author-123")
        XCTAssertNotNil(comment.author)
        XCTAssertEqual(comment.author?.name, "John Doe")
    }

    func testSystemComment() {
        // Given: A system comment (no author)
        let comment = Comment(
            id: "system-comment",
            content: "Task was moved to this list",
            type: .TEXT,
            authorId: nil,
            author: nil,
            taskId: "task-123",
            createdAt: Date(),
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        // Then: Author should be nil (system comment)
        XCTAssertNil(comment.authorId)
        XCTAssertNil(comment.author)
    }

    // MARK: - View Comments from Others Tests

    func testMultipleCommentsFromDifferentUsers() {
        // Given: Comments from different users
        let user1 = TestHelpers.createTestUser(id: "user-1", name: "Alice")
        let user2 = TestHelpers.createTestUser(id: "user-2", name: "Bob")
        let user3 = TestHelpers.createTestUser(id: "user-3", name: "Charlie")

        let taskId = "shared-task-123"

        let comments = [
            TestHelpers.createTestComment(
                id: "comment-1",
                content: "I'll start working on this",
                authorId: user1.id,
                author: user1,
                taskId: taskId,
                createdAt: Date().addingTimeInterval(-3600)
            ),
            TestHelpers.createTestComment(
                id: "comment-2",
                content: "Let me know if you need help",
                authorId: user2.id,
                author: user2,
                taskId: taskId,
                createdAt: Date().addingTimeInterval(-1800)
            ),
            TestHelpers.createTestComment(
                id: "comment-3",
                content: "I can review when ready",
                authorId: user3.id,
                author: user3,
                taskId: taskId,
                createdAt: Date()
            )
        ]

        // Then: All comments should have correct authors
        XCTAssertEqual(comments.count, 3)
        XCTAssertEqual(comments[0].author?.name, "Alice")
        XCTAssertEqual(comments[1].author?.name, "Bob")
        XCTAssertEqual(comments[2].author?.name, "Charlie")

        // All should be for the same task
        XCTAssertTrue(comments.allSatisfy { $0.taskId == taskId })
    }

    func testDistinguishCurrentUserComments() {
        // Given: Comments including current user
        let currentUserId = "current-user"
        let otherUserId = "other-user"

        let comments = [
            TestHelpers.createTestComment(id: "c1", content: "My comment", authorId: currentUserId),
            TestHelpers.createTestComment(id: "c2", content: "Their comment", authorId: otherUserId),
            TestHelpers.createTestComment(id: "c3", content: "Another of mine", authorId: currentUserId)
        ]

        // When: Filtering comments by current user
        let myComments = comments.filter { $0.authorId == currentUserId }
        let otherComments = comments.filter { $0.authorId != currentUserId }

        // Then: Should correctly identify user's comments
        XCTAssertEqual(myComments.count, 2)
        XCTAssertEqual(otherComments.count, 1)
    }

    // MARK: - Comment Timestamps Tests

    func testCommentCreatedAt() {
        // Given: A comment with creation timestamp
        let createdAt = Date()
        let comment = TestHelpers.createTestComment(createdAt: createdAt)

        // Then: Created at should be set
        XCTAssertEqual(comment.createdAt, createdAt)
    }

    func testCommentUpdatedAt() {
        // Given: An updated comment
        let createdAt = Date().addingTimeInterval(-3600)
        let updatedAt = Date()

        let comment = Comment(
            id: "updated-comment",
            content: "Updated content",
            type: .TEXT,
            authorId: "author-123",
            author: nil,
            taskId: "task-123",
            createdAt: createdAt,
            updatedAt: updatedAt,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        // Then: Both timestamps should be set
        XCTAssertEqual(comment.createdAt, createdAt)
        XCTAssertEqual(comment.updatedAt, updatedAt)
    }

    func testCommentChronologicalOrder() {
        // Given: Comments at different times
        let now = Date()
        let comments = [
            TestHelpers.createTestComment(id: "c1", createdAt: now.addingTimeInterval(-3600)),  // 1 hour ago
            TestHelpers.createTestComment(id: "c2", createdAt: now.addingTimeInterval(-1800)),  // 30 min ago
            TestHelpers.createTestComment(id: "c3", createdAt: now)  // Now
        ]

        // When: Sorting by creation time
        let sortedComments = comments.sorted { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }

        // Then: Should be in chronological order
        XCTAssertEqual(sortedComments[0].id, "c1")
        XCTAssertEqual(sortedComments[1].id, "c2")
        XCTAssertEqual(sortedComments[2].id, "c3")
    }

    // MARK: - Reply Tests

    func testCommentWithReplies() {
        // Given: A parent comment with replies
        let parentId = "parent-comment"
        let author1 = TestHelpers.createTestUser(id: "author-1", name: "Author 1")
        let author2 = TestHelpers.createTestUser(id: "author-2", name: "Author 2")

        let reply1 = Comment(
            id: "reply-1",
            content: "First reply",
            type: .TEXT,
            authorId: author1.id,
            author: author1,
            taskId: "task-123",
            createdAt: Date(),
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: parentId,
            replies: nil,
            secureFiles: nil
        )

        let reply2 = Comment(
            id: "reply-2",
            content: "Second reply",
            type: .TEXT,
            authorId: author2.id,
            author: author2,
            taskId: "task-123",
            createdAt: Date(),
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: parentId,
            replies: nil,
            secureFiles: nil
        )

        let parentComment = Comment(
            id: parentId,
            content: "Parent comment",
            type: .TEXT,
            authorId: "parent-author",
            author: nil,
            taskId: "task-123",
            createdAt: Date().addingTimeInterval(-3600),
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: [reply1, reply2],
            secureFiles: nil
        )

        // Then: Parent should have replies
        XCTAssertEqual(parentComment.replies?.count, 2)
        XCTAssertEqual(parentComment.replies?[0].content, "First reply")
        XCTAssertEqual(parentComment.replies?[1].content, "Second reply")

        // Replies should reference parent
        XCTAssertEqual(reply1.parentCommentId, parentId)
        XCTAssertEqual(reply2.parentCommentId, parentId)
    }

    // MARK: - Stable ID Tests

    func testStableIdWithValidId() {
        // Given: A comment with valid ID
        let comment = TestHelpers.createTestComment(id: "valid-id-123")

        // Then: Stable ID should use the ID
        XCTAssertEqual(comment.stableId, "valid-id-123")
    }

    func testStableIdWithEmptyId() {
        // Given: A comment with empty ID (corrupted data)
        let comment = Comment(
            id: "",
            content: "Some content",
            type: .TEXT,
            authorId: nil,
            author: nil,
            taskId: "task-123",
            createdAt: Date(),
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        // Then: Stable ID should generate fallback
        XCTAssertTrue(comment.stableId.hasPrefix("fallback_"))
    }

    // MARK: - Secure Files Tests

    func testCommentWithSecureFiles() {
        // Given: A comment with secure files
        let secureFile = SecureFile(
            id: "file-123",
            name: "confidential.pdf",
            size: 2048000,
            mimeType: "application/pdf"
        )

        let comment = Comment(
            id: "secure-comment",
            content: "See attached file",
            type: .ATTACHMENT,
            authorId: "author-123",
            author: nil,
            taskId: "task-123",
            createdAt: Date(),
            updatedAt: nil,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: [secureFile]
        )

        // Then: Secure files should be present
        XCTAssertEqual(comment.secureFiles?.count, 1)
        XCTAssertEqual(comment.secureFiles?.first?.name, "confidential.pdf")
        XCTAssertEqual(comment.secureFiles?.first?.mimeType, "application/pdf")
    }

    // MARK: - Comment Equality Tests

    func testCommentIdEquality() {
        // Given: Two comments with same ID
        let comment1 = TestHelpers.createTestComment(id: "same-id", content: "Content 1")
        let comment2 = TestHelpers.createTestComment(id: "same-id", content: "Content 2")

        // Then: Should have same ID
        XCTAssertEqual(comment1.id, comment2.id)
    }

    func testCommentIdInequality() {
        // Given: Two comments with different IDs
        let comment1 = TestHelpers.createTestComment(id: "comment-1")
        let comment2 = TestHelpers.createTestComment(id: "comment-2")

        // Then: Should have different IDs
        XCTAssertNotEqual(comment1.id, comment2.id)
    }

    // MARK: - Comment Hashable Tests

    @MainActor func testCommentHashable() {
        // Given: A comment
        let comment = TestHelpers.createTestComment(id: "hash-test")

        // Then: Should work in Set
        var commentSet = Set<Comment>()
        commentSet.insert(comment)
        XCTAssertTrue(commentSet.contains(comment))
    }

    @MainActor func testMultipleCommentsInSet() {
        // Given: Multiple comments
        let comments = [
            TestHelpers.createTestComment(id: "c1"),
            TestHelpers.createTestComment(id: "c2"),
            TestHelpers.createTestComment(id: "c3")
        ]

        // When: Added to set
        let commentSet = Set(comments)

        // Then: All should be present
        XCTAssertEqual(commentSet.count, 3)
    }

    // MARK: - Task with Comments Tests

    func testTaskWithMultipleComments() {
        // Given: A task with multiple comments from different users
        let taskId = "task-with-comments"
        let user1 = TestHelpers.createTestUser(id: "user-1", name: "Alice")
        let user2 = TestHelpers.createTestUser(id: "user-2", name: "Bob")

        let comments = [
            TestHelpers.createTestComment(id: "c1", content: "Question about this task", authorId: user1.id, author: user1, taskId: taskId),
            TestHelpers.createTestComment(id: "c2", content: "Response to the question", authorId: user2.id, author: user2, taskId: taskId),
            TestHelpers.createTestComment(id: "c3", content: "Thanks!", authorId: user1.id, author: user1, taskId: taskId)
        ]

        let task = TestHelpers.createTestTask(
            id: taskId,
            title: "Task with Discussion",
            comments: comments
        )

        // Then: Task should have all comments
        XCTAssertEqual(task.comments?.count, 3)

        // Comments should be from different authors
        let authorIds = Set(task.comments?.compactMap { $0.authorId } ?? [])
        XCTAssertEqual(authorIds.count, 2)
    }

    // MARK: - AI Agent Comments Tests

    func testAIAgentComment() {
        // Given: A comment from an AI agent
        let aiAgent = TestHelpers.createTestUser(
            id: "ai-agent-claude",
            name: "Claude",
            email: "claude@astrid.cc",
            isAIAgent: true,
            aiAgentType: "claude"
        )

        let comment = TestHelpers.createTestComment(
            id: "ai-comment-1",
            content: "I've analyzed this task and here's my suggestion...",
            authorId: aiAgent.id,
            author: aiAgent
        )

        // Then: Comment should be from AI agent
        XCTAssertEqual(comment.author?.isAIAgent, true)
        XCTAssertEqual(comment.author?.aiAgentType, "claude")
    }

    // MARK: - Complete Workflow Tests

    func testCommentCollaborationWorkflow() {
        // Simulates: Multiple users commenting on a shared task

        // Setup users
        let taskOwner = TestHelpers.createTestUser(id: "owner", name: "Task Owner")
        let teammate1 = TestHelpers.createTestUser(id: "teammate-1", name: "Developer")
        let teammate2 = TestHelpers.createTestUser(id: "teammate-2", name: "Designer")

        let taskId = "collab-task"
        let now = Date()

        // Create comment thread
        let comments = [
            // Owner creates task and adds initial comment
            TestHelpers.createTestComment(
                id: "c1",
                content: "I've created this task for the new feature. Let me know if you have questions.",
                authorId: taskOwner.id,
                author: taskOwner,
                taskId: taskId,
                createdAt: now.addingTimeInterval(-7200)  // 2 hours ago
            ),
            // Developer responds
            TestHelpers.createTestComment(
                id: "c2",
                content: "I'll start on the backend implementation. What's the priority?",
                authorId: teammate1.id,
                author: teammate1,
                taskId: taskId,
                createdAt: now.addingTimeInterval(-3600)  // 1 hour ago
            ),
            // Owner responds
            TestHelpers.createTestComment(
                id: "c3",
                content: "It's high priority. We need it by Friday.",
                authorId: taskOwner.id,
                author: taskOwner,
                taskId: taskId,
                createdAt: now.addingTimeInterval(-1800)  // 30 min ago
            ),
            // Designer chimes in
            TestHelpers.createTestComment(
                id: "c4",
                content: "I'll have the mockups ready by tomorrow.",
                authorId: teammate2.id,
                author: teammate2,
                taskId: taskId,
                createdAt: now  // Now
            )
        ]

        // Create task with comments
        let task = TestHelpers.createTestTask(
            id: taskId,
            title: "New Feature Implementation",
            priority: .high,
            creatorId: taskOwner.id,
            creator: taskOwner,
            comments: comments
        )

        // Verify workflow
        XCTAssertEqual(task.comments?.count, 4)

        // Verify chronological order
        let sortedComments = task.comments?.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        XCTAssertEqual(sortedComments?[0].authorId, taskOwner.id)
        XCTAssertEqual(sortedComments?[1].authorId, teammate1.id)
        XCTAssertEqual(sortedComments?[2].authorId, taskOwner.id)
        XCTAssertEqual(sortedComments?[3].authorId, teammate2.id)

        // Count comments per user
        let commentsByOwner = comments.filter { $0.authorId == taskOwner.id }
        let commentsByDev = comments.filter { $0.authorId == teammate1.id }
        let commentsByDesigner = comments.filter { $0.authorId == teammate2.id }

        XCTAssertEqual(commentsByOwner.count, 2)
        XCTAssertEqual(commentsByDev.count, 1)
        XCTAssertEqual(commentsByDesigner.count, 1)
    }
}
