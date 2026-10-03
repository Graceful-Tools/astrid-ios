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
    /// Per-list inline subtasks (ba1deb9d). NSNumber? so ABSENT stays distinct from false —
    /// absent means SHOW, and a scalar Bool would collapse the two into "hidden".
    @NSManaged public var showSubtasks: NSNumber?
    /// JSON-serialised `RecentlyCompletedWindow`. Nil = legacy 24h default.
    @NSManaged public var recentlyCompletedWindowJSON: String?
    /// JSON-serialised `ListRosterCache.Roster` — the list's owner and members (AITD-413).
    /// Nil = this list has never been cached with anybody in it.
    @NSManaged public var listRosterJSON: String?

    // MARK: - Conversion to Domain Model

    func toDomainModel() -> TaskList {
        TaskList(
            id: id,
            name: name,
            color: color,
            imageUrl: imageUrl,
            privacy: TaskList.Privacy(rawValue: privacy) ?? .PRIVATE,
            ownerId: ownerId,
            // Restored so an OFFLINE COLD LAUNCH still knows who is on this list: the assignee
            // picker's roster is built from exactly these two fields (AITD-413).
            owner: roster.owner,
            listMembers: roster.members,
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
            showSubtasks: showSubtasks?.boolValue,
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

    private var roster: ListRosterCache.Roster {
        ListRosterCache.decode(listRosterJSON)
    }

    private func decodeRecentlyCompletedWindow() -> RecentlyCompletedWindow? {
        guard let json = recentlyCompletedWindowJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RecentlyCompletedWindow.self, from: data)
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
}
