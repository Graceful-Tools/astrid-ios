import CoreData
import Foundation

@objc(CDMember)
public class CDMember: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var listId: String
    @NSManaged public var userId: String
    @NSManaged public var role: String // "owner", "editor", "viewer"
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?

    // Sync fields (following established local-first pattern)
    @NSManaged public var syncStatus: String // "synced", "pending", "pending_update", "pending_delete", "failed"
    @NSManaged public var lastSyncedAt: Date?
    @NSManaged public var pendingOperation: String? // "add", "update_role", "remove"
    @NSManaged public var pendingRole: String? // For role updates
    @NSManaged public var syncAttempts: Int16
    @NSManaged public var syncError: String?
    @NSManaged public var lastSyncAttemptAt: Date?  // When last attempt was made

    // MARK: - Conversion to Domain Model

    func toDomainModel() -> ListMember {
        ListMember(
            id: id,
            listId: listId,
            userId: userId,
            role: role,
            createdAt: createdAt,
            updatedAt: updatedAt,
            user: nil // Populate from separate fetch if needed
        )
    }

    // MARK: - Update from Domain Model

    func update(from member: ListMember) {
        self.role = member.role
        self.userId = member.userId
        self.listId = member.listId ?? ""
        self.createdAt = member.createdAt
        self.updatedAt = member.updatedAt ?? Date()
    }
}

extension CDMember {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDMember> {
        return NSFetchRequest<CDMember>(entityName: "CDMember")
    }

    /// Fetch all members
    static func fetchAll(context: NSManagedObjectContext) throws -> [CDMember] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Fetch member by ID
    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDMember? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Fetch all members for a specific list
    static func fetchByListId(_ listId: String, context: NSManagedObjectContext) throws -> [CDMember] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "listId == %@", listId)
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Fetch member by list and user ID
    static func fetchByListAndUser(_ listId: String, userId: String, context: NSManagedObjectContext) throws -> CDMember? {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "listId == %@ AND userId == %@",
            listId, userId
        )
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    /// Fetch all pending members (add, update, remove operations)
    static func fetchPending(context: NSManagedObjectContext) throws -> [CDMember] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "syncStatus IN %@",
            ["pending", "pending_update", "pending_delete", "failed"]
        )
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        return try context.fetch(request)
    }

    /// Fetch pending members for a specific list
    static func fetchPendingForList(_ listId: String, context: NSManagedObjectContext) throws -> [CDMember] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "listId == %@ AND syncStatus IN %@",
            listId,
            ["pending", "pending_update", "pending_delete", "failed"]
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
        syncAttempts >= CDMember.maxSyncAttempts
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
        pendingRole = nil
    }
}
