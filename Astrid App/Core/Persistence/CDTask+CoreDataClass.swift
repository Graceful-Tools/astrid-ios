import CoreData
@preconcurrency import Foundation

@objc(CDTask)
public class CDTask: NSManagedObject {
    @NSManaged public var id: String
    @NSManaged public var title: String
    @NSManaged public var taskDescription: String
    @NSManaged public var priority: Int16
    @NSManaged public var completed: Bool
    @NSManaged public var isPrivate: Bool
    @NSManaged public var repeating: String
    @NSManaged public var dueDateTime: Date?
    @NSManaged public var isAllDay: Bool
    @NSManaged public var reminderTime: Date?
    @NSManaged public var reminderSent: Bool
    @NSManaged public var reminderType: String?
    @NSManaged public var createdAt: Date?
    @NSManaged public var updatedAt: Date?
    @NSManaged public var syncStatus: String // "synced", "pending", "pending_delete", "failed"
    @NSManaged public var lastSyncedAt: Date?

    // Retry tracking for offline sync
    @NSManaged public var syncAttempts: Int16  // Number of retry attempts
    @NSManaged public var lastSyncAttemptAt: Date?  // When last attempt was made
    @NSManaged public var lastSyncError: String?  // Error message from last failure

    // Search index (lowercase title + description for fast offline search)
    @NSManaged public var searchableText: String?

    // Repeating task fields
    @NSManaged public var repeatFrom: String? // "DUE_DATE" or "COMPLETION_DATE"
    @NSManaged public var occurrenceCount: Int32 // Number of times task has repeated
    @NSManaged public var timerDuration: Int32 // Duration in minutes for the task timer
    @NSManaged public var lastTimerValue: String? // Last completion details for the timer

    // Relationships
    @NSManaged public var assigneeId: String?
    @NSManaged public var creatorId: String
    @NSManaged public var listIds: [String]? // JSON array of list IDs
    @NSManaged public var repeatingDataJSON: String? // JSON for CustomRepeatingPattern

    // Task copy tracking
    @NSManaged public var originalTaskId: String? // ID of task this was copied from
    @NSManaged public var parentTaskId: String? // Subtasks: parent task id (nil = top-level)
    @NSManaged public var sourceListId: String? // Which public list this was copied from

    // Idempotency key for dedup on server retry
    @NSManaged public var clientRequestId: String?

    /// Board status as a STATE on the task (task 2e41c645): ready | doing |
    /// waiting | a custom role. Nil means Inbox; Done is derived from
    /// `completed`. Persisted because the board prefers this over list
    /// membership — unstored, it read back nil on every cold start and every
    /// card fell to Inbox once the status lists went away.
    @NSManaged public var statusRole: String?
    /// The server-minted `KEY-N` (AITD-437). Optional, so a lightweight migration.
    @NSManaged public var identifier: String?

    // MARK: - Conversion to Domain Model
    
    func toDomainModel() -> Task {
        Task(
            id: id,
            title: title,
            description: taskDescription,
            assigneeId: assigneeId,
            assignee: nil, // Populate from separate fetch if needed
            creatorId: creatorId,
            creator: nil, // Populate from separate fetch if needed
            dueDateTime: dueDateTime,  // Core Data stores date+time in dueDateTime
            isAllDay: isAllDay,  // Persisted in Core Data
            reminderTime: reminderTime,
            reminderSent: reminderSent,
            reminderType: reminderType.flatMap { Task.ReminderType(rawValue: $0) },
            repeating: Task.Repeating(rawValue: repeating) ?? .never,
            repeatingData: parseRepeatingData(),
            repeatFrom: repeatFrom.flatMap { Task.RepeatFromMode(rawValue: $0) },
            occurrenceCount: occurrenceCount > 0 ? Int(occurrenceCount) : nil,
            timerDuration: timerDuration > 0 ? Int(timerDuration) : nil,
            lastTimerValue: lastTimerValue,
            priority: Task.Priority(rawValue: Int(priority)) ?? .none,
            lists: nil, // Populate from separate fetch if needed
            listIds: listIds,
            isPrivate: isPrivate,
            completed: completed,
            statusRole: statusRole,
            identifier: identifier,
            attachments: nil,
            comments: nil,
            createdAt: createdAt,
            updatedAt: updatedAt,
            originalTaskId: originalTaskId,
            sourceListId: sourceListId,
            clientRequestId: clientRequestId,
            parentTaskId: parentTaskId
        )
    }
    
    // MARK: - Private Helpers

    private func parseRepeatingData() -> CustomRepeatingPattern? {
        guard let repeatingDataJSON = self.repeatingDataJSON,
              let data = Data(base64Encoded: repeatingDataJSON) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(CustomRepeatingPattern.self, from: data)
    }
}

extension CDTask {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CDTask> {
        return NSFetchRequest<CDTask>(entityName: "CDTask")
    }
}
