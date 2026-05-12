import CoreData
import Foundation

@objc(CDTaskList)
public class CDTaskList: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var listDescription: String?
    @NSManaged public var color: String?
    @NSManaged public var imageUrl: String?
    @NSManaged public var privacy: String
    @NSManaged public var ownerId: String
    @NSManaged public var isFavorite: Bool
    @NSManaged public var favoriteOrder: Int32
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var syncStatus: String
    @NSManaged public var lastSyncedAt: Date?
    
    // Settings
    @NSManaged public var defaultAssigneeId: String?
    @NSManaged public var defaultPriority: Int16
    @NSManaged public var defaultRepeating: String?
    @NSManaged public var defaultIsPrivate: Bool
    @NSManaged public var defaultDueDate: String?
    @NSManaged public var defaultDueTime: String?

    // Filters
    @NSManaged public var sortBy: String?
    @NSManaged public var filterCompletion: String?
    @NSManaged public var filterPriority: String?
    @NSManaged public var filterDueDate: String?
    @NSManaged public var filterAssignee: String?
    @NSManaged public var filterRepeating: String?

    // Project status board (added 2026-05-12). Lightweight-migration safe:
    // every new attribute is optional with a sensible default.
    @NSManaged public var projectId: String?
    @NSManaged public var listType: String?
    @NSManaged public var statusRole: String?
    @NSManaged public var statusOrder: NSNumber?
    @NSManaged public var statusDescription: String?
    @NSManaged public var statusCompleted: NSNumber?
    /// JSON-serialised `RecentlyCompletedWindow`. Nil = legacy 24h default.
    @NSManaged public var recentlyCompletedWindowJSON: String?

    // MARK: - Conversion to Domain Model

    func toDomainModel() -> TaskList {
        TaskList(
            id: id,
            name: name,
            color: color,
            imageUrl: imageUrl,
            privacy: TaskList.Privacy(rawValue: privacy) ?? .PRIVATE,
            ownerId: ownerId,
            defaultAssigneeId: defaultAssigneeId,
            defaultPriority: Int(defaultPriority),
            defaultRepeating: defaultRepeating,
            defaultIsPrivate: defaultIsPrivate,
            defaultDueDate: defaultDueDate,
            defaultDueTime: defaultDueTime,
            createdAt: createdAt,
            updatedAt: updatedAt,
            description: listDescription,
            isFavorite: isFavorite,
            favoriteOrder: Int(favoriteOrder),
            sortBy: sortBy,
            filterCompletion: filterCompletion,
            filterDueDate: filterDueDate,
            filterAssignee: filterAssignee,
            filterRepeating: filterRepeating,
            filterPriority: filterPriority,
            projectId: projectId,
            listType: listType,
            statusRole: statusRole,
            statusOrder: statusOrder?.intValue,
            statusDescription: statusDescription,
            statusCompleted: statusCompleted?.boolValue,
            recentlyCompletedWindow: decodeRecentlyCompletedWindow()
        )
    }

    private func decodeRecentlyCompletedWindow() -> RecentlyCompletedWindow? {
        guard let json = recentlyCompletedWindowJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
    }

    // MARK: - Update from Domain Model

    func update(from list: TaskList) {
        self.name = list.name
        self.listDescription = list.description
        self.color = list.color
        self.imageUrl = list.imageUrl
        self.privacy = list.privacy?.rawValue ?? "PRIVATE"  // Default to PRIVATE if not specified
        self.ownerId = list.ownerId ?? list.owner?.id ?? ""  // Use owner.id if ownerId not available
        self.isFavorite = list.isFavorite ?? false
        self.favoriteOrder = Int32(list.favoriteOrder ?? 0)
        self.defaultAssigneeId = list.defaultAssigneeId
        self.defaultPriority = Int16(list.defaultPriority ?? 0)
        self.defaultRepeating = list.defaultRepeating
        self.defaultIsPrivate = list.defaultIsPrivate ?? false
        self.defaultDueDate = list.defaultDueDate
        self.defaultDueTime = list.defaultDueTime
        self.sortBy = list.sortBy
        self.filterCompletion = list.filterCompletion
        self.filterPriority = list.filterPriority
        self.filterDueDate = list.filterDueDate
        self.filterAssignee = list.filterAssignee
        self.filterRepeating = list.filterRepeating
        self.projectId = list.projectId
        self.listType = list.listType
        self.statusRole = list.statusRole
        self.statusOrder = list.statusOrder.map(NSNumber.init(value:))
        self.statusDescription = list.statusDescription
        self.statusCompleted = list.statusCompleted.map(NSNumber.init(value:))
        if let window = list.recentlyCompletedWindow,
           let data = try? JSONEncoder().encode(window),
           let json = String(data: data, encoding: .utf8) {
            self.recentlyCompletedWindowJSON = json
        } else {
            self.recentlyCompletedWindowJSON = nil
        }
        self.updatedAt = list.updatedAt ?? Date()
    }
}

extension CDTaskList {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTaskList> {
        return NSFetchRequest<CDTaskList>(entityName: "CDTaskList")
    }
    
    static func fetchAll(context: NSManagedObjectContext) throws -> [CDTaskList] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
        return try context.fetch(request)
    }
    
    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDTaskList? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    static func fetchFavorites(context: NSManagedObjectContext) throws -> [CDTaskList] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "isFavorite == YES")
        request.sortDescriptors = [NSSortDescriptor(key: "favoriteOrder", ascending: true)]
        return try context.fetch(request)
    }
}
