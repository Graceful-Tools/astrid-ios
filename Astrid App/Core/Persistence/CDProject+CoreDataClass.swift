import CoreData
import Foundation

/// Core Data backing for `Project` (status board). Mirrors the
/// CDTaskList pattern: domain-model conversion both directions + a sync
/// status column so the outbox can flush pending creates/deletes.
///
/// We deliberately do NOT model a `lists` relation here — the
/// project-to-list association lives on `CDTaskList.projectId` as a plain
/// string foreign key, matching how `CDTask.listIds` references
/// CDTaskList. Keeping the navigation pattern uniform avoids a one-off.
///
/// `customStates` (AITD-379) is likewise not cached, for the same reason
/// `lists` and `members` are not: this cache holds a project's own scalars so
/// the sidebar can name a board offline, and the board UI is online-first. A
/// cold launch therefore renders the config defaults until the first sync
/// fills the custom columns in — the same window that already exists for a
/// board's lists, and a strictly better failure than a stale column set.
@objc(CDProject)
public class CDProject: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var name: String
    @NSManaged public var projectDescription: String?
    @NSManaged public var color: String?
    @NSManaged public var imageUrl: String?
    @NSManaged public var ownerId: String
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var syncStatus: String
    @NSManaged public var lastSyncedAt: Date?

    func toDomainModel() -> Project {
        Project(
            id: id,
            name: name,
            description: projectDescription,
            color: color,
            imageUrl: imageUrl,
            ownerId: ownerId,
            owner: nil,
            members: nil,
            lists: nil,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    func update(from project: Project) {
        self.name = project.name
        self.projectDescription = project.description
        self.color = project.color
        self.imageUrl = project.imageUrl
        self.ownerId = project.ownerId ?? project.owner?.id ?? ""
        self.createdAt = project.createdAt ?? self.createdAt ?? Date()
        self.updatedAt = project.updatedAt ?? Date()
    }
}

extension CDProject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDProject> {
        NSFetchRequest<CDProject>(entityName: "CDProject")
    }

    static func fetchAll(context: NSManagedObjectContext) throws -> [CDProject] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }

    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDProject? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}
