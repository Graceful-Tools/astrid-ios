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

    // MARK: - Update from Domain Model

    func update(from message: ChatMessage) {
        self.channelId = message.channelId
        self.content = message.content
        self.type = message.type.rawValue
        self.authorId = message.authorId
        self.authorName = message.author?.name
        self.authorImage = message.author?.image
        self.authorIsAIAgent = message.author?.isAIAgent ?? false
        self.authorAIAgentType = message.author?.aiAgentType
        self.replyToId = message.replyToId
        self.clientRequestId = message.clientRequestId
        self.createdAt = message.createdAt
        self.updatedAt = message.updatedAt ?? Date()

        // Serialize secureFiles to JSON
        if let secureFiles = message.secureFiles, !secureFiles.isEmpty {
            if let jsonData = try? JSONEncoder().encode(secureFiles),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.secureFilesData = jsonString
            }
        } else {
            self.secureFilesData = nil
        }
    }
}

extension CDChatMessage {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDChatMessage> {
        return NSFetchRequest<CDChatMessage>(entityName: "CDChatMessage")
    }

    static func fetchAll(context: NSManagedObjectContext) throws -> [CDChatMessage] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDChatMessage? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchByChannelId(_ channelId: String, context: NSManagedObjectContext) throws -> [CDChatMessage] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "channelId == %@", channelId)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    static func fetchByClientRequestId(_ clientRequestId: String, context: NSManagedObjectContext) throws -> CDChatMessage? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "clientRequestId == %@", clientRequestId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Fetch all pending messages (create/delete operations; excludes permanently failed)
    static func fetchPending(context: NSManagedObjectContext) throws -> [CDChatMessage] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "syncStatus IN %@",
            ["pending", "pending_delete"]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Fetch pending messages for a specific channel (excludes permanently failed)
    static func fetchPendingForChannel(_ channelId: String, context: NSManagedObjectContext) throws -> [CDChatMessage] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "channelId == %@ AND syncStatus IN %@",
            channelId,
            ["pending", "pending_delete"]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    // MARK: - Retry Policy

    /// Maximum retry attempts before giving up
    static let maxSyncAttempts: Int16 = 10

    /// Calculate next retry delay using exponential backoff
    var nextRetryDelay: TimeInterval {
        let baseDelay: TimeInterval = 1
        let maxDelay: TimeInterval = 32
        return min(baseDelay * pow(2, Double(syncAttempts)), maxDelay)
    }

    /// Whether we should give up on syncing
    var shouldGiveUp: Bool {
        syncAttempts >= CDChatMessage.maxSyncAttempts
    }

    /// Whether we can retry now (respects backoff delay)
    var canRetryNow: Bool {
        guard !shouldGiveUp else { return false }
        guard let lastAttempt = lastSyncAttemptAt else { return true }
        return Date().timeIntervalSince(lastAttempt) >= nextRetryDelay
    }

    /// Record a failed sync attempt
    func recordSyncFailure(error: String) {
        syncAttempts += 1
        lastSyncAttemptAt = Date()
        syncError = error
        if shouldGiveUp {
            syncStatus = "failed"
        }
    }

    /// Reset retry state after successful sync
    func resetSyncState() {
        syncAttempts = 0
        lastSyncAttemptAt = nil
        syncError = nil
        syncStatus = "synced"
        lastSyncedAt = Date()
        pendingOperation = nil
    }
}
