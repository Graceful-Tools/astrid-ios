import CoreData
import Foundation

@objc(CDChatChannel)
public class CDChatChannel: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var listId: String?
    @NSManaged public var virtualKey: String?
    @NSManaged public var name: String?
    @NSManaged public var lastFetchedAt: Date?

    // MARK: - Conversion to Domain Model

    func toDomainModel() -> ChatChannel {
        return ChatChannel(
            id: id,
            listId: listId,
            virtualKey: virtualKey,
            name: name,
            createdAt: nil,
            updatedAt: nil
        )
    }

    // MARK: - Update from Domain Model

    func update(from channel: ChatChannel) {
        self.listId = channel.listId
        self.virtualKey = channel.virtualKey
        self.name = channel.name
        self.lastFetchedAt = Date()
    }
}

extension CDChatChannel {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDChatChannel> {
        return NSFetchRequest<CDChatChannel>(entityName: "CDChatChannel")
    }

    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDChatChannel? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchByListId(_ listId: String, context: NSManagedObjectContext) throws -> CDChatChannel? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "listId == %@", listId)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func fetchAll(context: NSManagedObjectContext) throws -> [CDChatChannel] {
        let request = fetchRequest()
        return try context.fetch(request)
    }
}
