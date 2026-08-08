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
    
    // MARK: - Update from Domain Model

    func update(from task: Task) {
        self.title = task.title
        self.taskDescription = task.description
        self.priority = Int16(task.priority.rawValue)
        self.completed = task.completed
        self.isPrivate = task.isPrivate
        self.repeating = task.repeating?.rawValue ?? "never"  // Default to "never" if not provided
        self.dueDateTime = task.dueDateTime  // Primary datetime field
        self.isAllDay = task.isAllDay  // Persist all-day flag
        self.reminderTime = task.reminderTime
        self.reminderSent = task.reminderSent ?? false
        self.reminderType = task.reminderType?.rawValue
        self.assigneeId = task.assigneeId
        self.creatorId = task.creatorId ?? task.creator?.id ?? ""  // Use creator.id if creatorId not available
        self.listIds = task.listIds ?? task.lists?.map { $0.id }
        // Assigned unconditionally: moving a card to Inbox or Done clears the
        // role, and a `??  self.statusRole` fallback here would keep the old one
        // and snap the card back to the column it just left.
        self.statusRole = task.statusRole
        // Preserve createdAt: use task value if present, otherwise keep existing (or set to now for new entries)
        self.createdAt = task.createdAt ?? self.createdAt ?? Date()
        self.updatedAt = task.updatedAt ?? Date()

        // Update repeating task fields
        self.repeatFrom = task.repeatFrom?.rawValue
        self.occurrenceCount = Int32(task.occurrenceCount ?? 0)
        self.timerDuration = Int32(task.timerDuration ?? 0)
        self.lastTimerValue = task.lastTimerValue

        // Handle repeatingData: encode if present, clear if nil
        if let repeatingData = task.repeatingData {
            self.repeatingDataJSON = encodeRepeatingData(repeatingData)
        } else {
            // Clear repeatingDataJSON if task no longer has custom repeating pattern
            self.repeatingDataJSON = nil
        }

        // Task copy tracking
        self.originalTaskId = task.originalTaskId
        self.parentTaskId = task.parentTaskId
        self.sourceListId = task.sourceListId

        // Persist clientRequestId (idempotency key for dedup).
        // Use the Task model's value if present; otherwise keep the existing CoreData value.
        // This ensures:
        //  1. New CDTask entries get clientRequestId from the Task model (e.g. createTask)
        //  2. Edits via updateTask (where clientRequestId is typically nil) don't wipe
        //     a previously stored value
        //  3. Batch syncs from server (where clientRequestId is nil) preserve the local key
        self.clientRequestId = task.clientRequestId ?? self.clientRequestId

        // Update search index
        updateSearchableText()
    }

    /// Updates the searchable text index for offline search
    func updateSearchableText() {
        let titleText = title.lowercased()
        let descText = taskDescription.lowercased()
        searchableText = "\(titleText) \(descText)".trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Private Helpers

    private func encodeRepeatingData(_ pattern: CustomRepeatingPattern) -> String? {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(pattern) else {
            return nil
        }
        return data.base64EncodedString()
    }

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
    
    static func fetchAll(context: NSManagedObjectContext) throws -> [CDTask] {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return try context.fetch(request)
    }
    
    static func fetchById(_ id: String, context: NSManagedObjectContext) throws -> CDTask? {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    static func fetchUnsyncedTasks(context: NSManagedObjectContext) throws -> [CDTask] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@", "pending")
        return try context.fetch(request)
    }

    // MARK: - Retry Policy

    /// Maximum retry attempts before giving up
    static let maxSyncAttempts: Int16 = 10

    /// Calculate next retry delay using exponential backoff (1s → 2s → 4s → ... → 32s max)
    var nextRetryDelay: TimeInterval {
        let baseDelay: TimeInterval = 1
        let maxDelay: TimeInterval = 32
        return min(baseDelay * pow(2, Double(syncAttempts)), maxDelay)
    }

    /// Whether we should give up on syncing this task
    var shouldGiveUp: Bool {
        syncAttempts >= CDTask.maxSyncAttempts
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
        lastSyncError = error
        syncStatus = shouldGiveUp ? "failed" : "pending"
    }

    /// Reset retry state after successful sync
    func resetSyncState() {
        syncAttempts = 0
        lastSyncAttemptAt = nil
        lastSyncError = nil
        syncStatus = "synced"
        lastSyncedAt = Date()
    }

    /// Fetch tasks that are ready to retry (respecting backoff)
    static func fetchRetryableTasks(context: NSManagedObjectContext) throws -> [CDTask] {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "(syncStatus == %@ OR syncStatus == %@) AND syncAttempts < %d",
            "pending", "pending_delete", maxSyncAttempts
        )
        let tasks = try context.fetch(request)
        return tasks.filter { $0.canRetryNow }
    }

    /// Fetch tasks that have permanently failed
    static func fetchFailedTasks(context: NSManagedObjectContext) throws -> [CDTask] {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@", "failed")
        return try context.fetch(request)
    }

    // MARK: - Offline Search

    /// Search tasks by query using the searchableText index
    static func search(
        query: String,
        listId: String? = nil,
        includeCompleted: Bool = true,
        context: NSManagedObjectContext
    ) throws -> [CDTask] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        let request = fetchRequest()
        let lowercaseQuery = query.lowercased()

        var predicates: [NSPredicate] = [
            NSPredicate(format: "searchableText CONTAINS[cd] %@", lowercaseQuery)
        ]

        // Filter by list if specified
        if let listId = listId {
            predicates.append(NSPredicate(format: "ANY listIds == %@", listId))
        }

        // Filter out completed if requested
        if !includeCompleted {
            predicates.append(NSPredicate(format: "completed == NO"))
        }

        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [
            NSSortDescriptor(key: "updatedAt", ascending: false)
        ]

        return try context.fetch(request)
    }

    /// Rebuild search index for all tasks (run on migration or data repair)
    static func rebuildSearchIndex(context: NSManagedObjectContext) throws {
        let request = fetchRequest()
        let allTasks = try context.fetch(request)

        var updatedCount = 0
        for task in allTasks {
            task.updateSearchableText()
            updatedCount += 1
        }

        try context.save()
        print("🔍 [CDTask] Rebuilt search index for \(updatedCount) tasks")
    }
}
