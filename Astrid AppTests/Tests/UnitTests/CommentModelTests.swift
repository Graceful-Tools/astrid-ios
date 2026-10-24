import XCTest
@testable import Astrid_App

/// `Comment.stableId` — the identity a comment list renders by, which must survive a comment the
/// server sent with an empty id (corrupted data) rather than collapse every such row into one.
///
/// This file used to hold twenty-one more tests that built a comment and read back the fields
/// they had just set; they could not fail when the app broke (AITD-531).
final class CommentModelTests: XCTestCase {


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
}
