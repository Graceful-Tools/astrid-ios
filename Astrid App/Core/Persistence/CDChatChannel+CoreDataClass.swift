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
}

extension CDChatChannel {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDChatChannel> {
        return NSFetchRequest<CDChatChannel>(entityName: "CDChatChannel")
    }

    static func fetchAll(context: NSManagedObjectContext) throws -> [CDChatChannel] {
        let request = fetchRequest()
        return try context.fetch(request)
    }
}
