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

    // MARK: - Update from Domain Model

    func update(from comment: Comment) {
        self.content = comment.content
        self.type = comment.type.rawValue
        self.authorId = comment.authorId
        self.authorName = comment.author?.name
        self.authorImage = comment.author?.image
        self.taskId = comment.taskId
        self.createdAt = comment.createdAt
        self.updatedAt = comment.updatedAt ?? Date()

        // Serialize secureFiles to JSON
        if let secureFiles = comment.secureFiles, !secureFiles.isEmpty {
            if let jsonData = try? JSONEncoder().encode(secureFiles),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                self.secureFilesData = jsonString
            }
        } else {
            self.secureFilesData = nil
        }
    }
}

extension CDComment {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDComment> {
        return NSFetchRequest<CDComment>(entityName: "CDComment")
    }

    static func fetchAll(context: NSManagedObjectContext) throws -> [CDComment] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDComment? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchByTaskId(_ taskId: String, context: NSManagedObjectContext) throws -> [CDComment] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "taskId == %@", taskId)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Fetch all pending comments (create, update, delete operations; excludes permanently failed)
    static func fetchPending(context: NSManagedObjectContext) throws -> [CDComment] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "syncStatus IN %@",
            ["pending", "pending_update", "pending_delete"]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Fetch pending comments for a specific task (excludes permanently failed)
    static func fetchPendingForTask(_ taskId: String, context: NSManagedObjectContext) throws -> [CDComment] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "taskId == %@ AND syncStatus IN %@",
            taskId,
            ["pending", "pending_update", "pending_delete"]
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
        syncAttempts >= CDComment.maxSyncAttempts
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
        pendingContent = nil
    }
}
