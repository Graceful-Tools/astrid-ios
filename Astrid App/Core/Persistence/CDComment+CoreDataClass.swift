import CoreData
import Foundation
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "CDComment")

@objc(CDComment)
public class CDComment: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var content: String
    @NSManaged public var type: String
    @NSManaged public var authorId: String?
    @NSManaged public var authorName: String?
    @NSManaged public var authorImage: String?
    @NSManaged public var taskId: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var syncStatus: String // "synced", "pending", "pending_update", "pending_delete", "failed"
    @NSManaged public var lastSyncedAt: Date?

    // Pending operation fields (for local-first offline support)
    @NSManaged public var pendingOperation: String? // "create", "update", "delete"
    @NSManaged public var pendingContent: String? // Content waiting to sync (for updates)
    @NSManaged public var syncAttempts: Int16 // Number of retry attempts
    @NSManaged public var syncError: String? // Last error message
    @NSManaged public var lastSyncAttemptAt: Date?  // When last attempt was made

    // Attachment data (JSON-serialized array of SecureFile)
    @NSManaged public var secureFilesData: String?

    // Pending file ID for attachments (used during sync)
    @NSManaged public var pendingFileId: String?

    // MARK: - Conversion to Domain Model

    func toDomainModel() -> Comment {
        // Reconstruct author from cached data if available
        var author: User? = nil
        if let authorId = authorId {
            author = User(
                id: authorId,
                email: nil,
                name: authorName,
                image: authorImage,
                createdAt: nil,
                defaultDueTime: nil,
                isPending: nil,
                isAIAgent: authorId.hasPrefix("ai-agent-"),
                aiAgentType: authorId.hasPrefix("ai-agent-") ? String(authorId.dropFirst("ai-agent-".count)) : nil
            )
        }

        // Deserialize secureFiles from JSON
        var secureFiles: [SecureFile]? = nil
        if let jsonData = secureFilesData?.data(using: .utf8) {
            secureFiles = try? JSONDecoder().decode([SecureFile].self, from: jsonData)
        }

        return Comment(
            id: id,
            content: content,
            type: Comment.CommentType(rawValue: type) ?? .TEXT,
            authorId: authorId,
            author: author,
            taskId: taskId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: secureFiles
        )
    }
}

extension CDComment {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDComment> {
        return NSFetchRequest<CDComment>(entityName: "CDComment")
    }
}
