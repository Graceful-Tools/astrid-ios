import CoreData
import Foundation
import os.log

private let logger = Logger(subsystem: Brand.logSubsystem, category: "CDChatMessage")

@objc(CDChatMessage)
public class CDChatMessage: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var channelId: String
    @NSManaged public var authorId: String?
    @NSManaged public var authorName: String?
    @NSManaged public var authorImage: String?
    @NSManaged public var authorIsAIAgent: Bool
    @NSManaged public var authorAIAgentType: String?
    @NSManaged public var content: String
    @NSManaged public var type: String  // TEXT, MARKDOWN, ATTACHMENT
    @NSManaged public var replyToId: String?
    @NSManaged public var clientRequestId: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var syncStatus: String  // "synced", "pending", "pending_delete", "failed"
    @NSManaged public var lastSyncedAt: Date?

    // Pending operation fields (for local-first offline support)
    @NSManaged public var pendingOperation: String?  // "create", "delete"
    @NSManaged public var pendingFileId: String?  // For attachment uploads
    @NSManaged public var syncAttempts: Int16
    @NSManaged public var syncError: String?
    @NSManaged public var lastSyncAttemptAt: Date?

    // Attachment data (JSON-serialized array of SecureFile)
    @NSManaged public var secureFilesData: String?

    // MARK: - Conversion to Domain Model

    func toDomainModel() -> ChatMessage {
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
                isAIAgent: authorIsAIAgent,
                aiAgentType: authorAIAgentType
            )
        }

        // Deserialize secureFiles from JSON
        var secureFiles: [SecureFile]? = nil
        if let jsonData = secureFilesData?.data(using: .utf8) {
            secureFiles = try? JSONDecoder().decode([SecureFile].self, from: jsonData)
        }

        return ChatMessage(
            id: id,
            channelId: channelId,
            authorId: authorId,
            author: author,
            content: content,
            type: Comment.CommentType(rawValue: type) ?? .TEXT,
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            replyToId: replyToId,
            clientRequestId: clientRequestId,
            secureFiles: secureFiles,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension CDChatMessage {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDChatMessage> {
        return NSFetchRequest<CDChatMessage>(entityName: "CDChatMessage")
    }
}
