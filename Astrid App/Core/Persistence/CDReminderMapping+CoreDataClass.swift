import CoreData
import Foundation

/**
 * CDReminderMapping
 *
 * CoreData entity for tracking the mapping between Astrid tasks and Apple Reminders.
 * Each mapping represents a link between one Astrid task and one EKReminder.
 */
@objc(CDReminderMapping)
public class CDReminderMapping: NSManagedObject {
    /// The Astrid task ID (optional for migration compatibility)
    @NSManaged public var astridTaskId: String?

    /// The Astrid list ID this task belongs to
    @NSManaged public var astridListId: String?

    /// The Apple Reminders calendarItemIdentifier (optional for migration compatibility)
    @NSManaged public var reminderIdentifier: String?

    /// The Apple Reminders calendar (list) identifier
    @NSManaged public var reminderCalendarIdentifier: String?

    /// When this mapping was last synced
    @NSManaged public var lastSyncedAt: Date?

    /// The updatedAt timestamp from Astrid at last sync
    @NSManaged public var astridUpdatedAt: Date?

    /// The lastModifiedDate from Reminders at last sync
    @NSManaged public var reminderUpdatedAt: Date?
}

extension CDReminderMapping {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDReminderMapping> {
        return NSFetchRequest<CDReminderMapping>(entityName: "CDReminderMapping")
    }
}
