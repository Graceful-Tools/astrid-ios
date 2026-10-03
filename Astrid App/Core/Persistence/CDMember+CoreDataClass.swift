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
}
