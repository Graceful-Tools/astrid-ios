import Foundation
import EventKit
import UIKit
import Combine
import CoreData

/**
 * AppleRemindersService
 *
 * Manages two-way sync between Astrid tasks and Apple Reminders:
 * - Requests and checks Reminders permission
 * - Links Astrid lists to Apple Reminders calendars (and vice versa)
 * - Syncs tasks bidirectionally with conflict resolution
 * - Supports user choice: export to Reminders or import from Reminders
 */
@MainActor
class AppleRemindersService: ObservableObject {
    static let shared = AppleRemindersService()

    // MARK: - EventKit

    let eventStore = EKEventStore()

    // MARK: - Published State

    @Published var authorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncedTaskCount: Int = 0
    @Published var linkedListCount: Int = 0

    /// Set of Astrid list IDs that are linked to Reminders calendars
    @Published var linkedLists: [String: ReminderListLink] = [:]

    // MARK: - Dependencies

    private let coreDataManager = CoreDataManager.shared
    private let taskService = TaskService.shared
    private let listService = ListService.shared

    // MARK: - UserDefaults Keys

    private let linkedListsKey = "AppleReminders.linkedLists"
    private let lastSyncKey = "AppleReminders.lastSyncDate"

    // MARK: - Initialization

    private init() {
        loadPersistedState()
        checkAuthorizationStatus()
        setupAutoSync()
        setupTempIdFixup()
    }

    // MARK: - Auto-sync (Phase 1 of the sync-provider plan)
    //
    // Closes the historical "manual sync only" gap. Two triggers:
    // - EKEventStoreChanged: a reminder changed in Apple Reminders.
    // - App became active: catch changes made while backgrounded.
    // Debounced (EventKit fires bursts of change notifications), and inert
    // unless permission is granted and at least one list is linked. Sync is
    // fully local (EventKit + TaskService, whose writes flow through the
    // Outbox), so it needs no network and no Outbox kind of its own.

    private var autoSyncObservers: [NSObjectProtocol] = []
    private var autoSyncDebounce: _Concurrency.Task<Void, Never>?

    /// Import saves mappings against the Outbox's optimistic temp task id
    /// (works offline; the reminder-id key still prevents re-import). When the
    /// create reconciles, rewrite the mapping to the real id — otherwise export
    /// sees the real-id task as unmapped and creates a duplicate reminder.
    private func setupTempIdFixup() {
        NotificationCenter.default.addObserver(
            forName: .taskTempIdResolved, object: nil, queue: .main
        ) { [weak self] notification in
            guard let tempId = notification.userInfo?["tempId"] as? String,
                  let realId = notification.userInfo?["realId"] as? String else { return }
            _Concurrency.Task { @MainActor [weak self] in
                guard let self else { return }
                let request = CDReminderMapping.fetchRequest()
                request.predicate = NSPredicate(format: "astridTaskId == %@", tempId)
                if let mapping = try? self.coreDataManager.viewContext.fetch(request).first {
                    mapping.astridTaskId = realId
                    try? self.coreDataManager.viewContext.save()
                }
            }
        }
    }

    private func setupAutoSync() {
        let center = NotificationCenter.default
        autoSyncObservers.append(center.addObserver(
            forName: .EKEventStoreChanged, object: eventStore, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in self?.scheduleAutoSync() }
        })
        autoSyncObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor [weak self] in self?.scheduleAutoSync() }
        })
    }

    private func scheduleAutoSync() {
        guard hasPermission, !linkedLists.isEmpty, !isSyncing else { return }
        autoSyncDebounce?.cancel()
        autoSyncDebounce = _Concurrency.Task { @MainActor [weak self] in
            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)  // 2s debounce
            guard !_Concurrency.Task.isCancelled, let self, !self.isSyncing else { return }
            do {
                try await self.syncAllLinkedLists()
                print("🔄 [AppleRemindersService] Auto-sync completed")
            } catch {
                print("⚠️ [AppleRemindersService] Auto-sync failed: \(error)")
            }
        }
    }

    private func loadPersistedState() {
        // Load last sync date
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date

        // Load linked lists
        if let data = UserDefaults.standard.data(forKey: linkedListsKey),
           let decoded = try? JSONDecoder().decode([String: ReminderListLink].self, from: data) {
            linkedLists = decoded
            linkedListCount = decoded.count
        }
    }

    private func persistLinkedLists() {
        if let encoded = try? JSONEncoder().encode(linkedLists) {
            UserDefaults.standard.set(encoded, forKey: linkedListsKey)
        }
        linkedListCount = linkedLists.count
    }

    /// Clear all Apple Reminders integration data on logout
    /// This prevents data leakage between users
    func clearAllData() {
        // Clear linked lists
        linkedLists = [:]
        linkedListCount = 0

        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: linkedListsKey)
        UserDefaults.standard.removeObject(forKey: lastSyncKey)

        // Reset sync state
        lastSyncDate = nil
        syncedTaskCount = 0
        isSyncing = false

        print("🗑️ [AppleRemindersService] All data cleared for logout")
    }

    // MARK: - Authorization

    /// Check current Reminders authorization status
    func checkAuthorizationStatus() {
        if #available(iOS 17.0, *) {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        } else {
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
    }

    /// Request access to Reminders
    /// - Returns: True if access was granted
    @discardableResult
    func requestAccess() async -> Bool {
        do {
            var granted: Bool
            if #available(iOS 17.0, *) {
                granted = try await eventStore.requestFullAccessToReminders()
            } else {
                granted = try await eventStore.requestAccess(to: .reminder)
            }
            checkAuthorizationStatus()
            return granted
        } catch {
            print("❌ [AppleRemindersService] Error requesting access: \(error)")
            return false
        }
    }

    /// Check if we have Reminders permission
    var hasPermission: Bool {
        if #available(iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }

    // MARK: - Reminders Calendar Management

    /// Get all Reminders calendars (lists) from Apple Reminders
    func getRemindersCalendars() -> [EKCalendar] {
        guard hasPermission else { return [] }
        return eventStore.calendars(for: .reminder)
    }

    /// Get Reminders calendars that are not yet linked to any Astrid list
    func getUnlinkedRemindersCalendars() -> [EKCalendar] {
        let linkedCalendarIds = Set(linkedLists.values.map { $0.reminderCalendarId })
        return getRemindersCalendars().filter { !linkedCalendarIds.contains($0.calendarIdentifier) }
    }

    /// Create a new Reminders calendar for an Astrid list
    func createRemindersCalendar(for astridList: TaskList) throws -> EKCalendar {
        guard hasPermission else {
            throw AppleRemindersError.notAuthorized
        }

        let calendar = EKCalendar(for: .reminder, eventStore: eventStore)
        calendar.title = astridList.name

        // Use default source for reminders
        if let source = eventStore.defaultCalendarForNewReminders()?.source {
            calendar.source = source
        } else if let source = eventStore.sources.first(where: { $0.sourceType == .local }) {
            calendar.source = source
        } else if let source = eventStore.sources.first(where: { $0.sourceType == .calDAV }) {
            calendar.source = source
        } else {
            throw AppleRemindersError.noCalendarSource
        }

        try eventStore.saveCalendar(calendar, commit: true)
        print("✅ [AppleRemindersService] Created calendar '\(astridList.name)' with ID: \(calendar.calendarIdentifier)")

        return calendar
    }

    /// Get or create a Reminders calendar for an Astrid list
    func getOrCreateRemindersCalendar(for astridList: TaskList) throws -> EKCalendar {
        // Check if already linked
        if let link = linkedLists[astridList.id],
           let calendar = eventStore.calendar(withIdentifier: link.reminderCalendarId) {
            return calendar
        }

        // Look for existing calendar with same name
        if let existingCalendar = getRemindersCalendars().first(where: { $0.title == astridList.name }) {
            return existingCalendar
        }

        // Create new calendar
        return try createRemindersCalendar(for: astridList)
    }

    // MARK: - List Linking

    /// Link an Astrid list to a Reminders calendar
    /// - Parameters:
    ///   - astridListId: The Astrid list ID
    ///   - calendar: The Reminders calendar (nil to create new)
    ///   - direction: The sync direction
    ///   - includeCompletedTasks: Whether to sync completed tasks
    func linkList(_ astridListId: String, toCalendar calendar: EKCalendar?, direction: SyncDirection, includeCompletedTasks: Bool = true) async throws {
        guard hasPermission else {
            throw AppleRemindersError.notAuthorized
        }

        guard let astridList = listService.lists.first(where: { $0.id == astridListId }) else {
            throw AppleRemindersError.listNotFound
        }

        let targetCalendar: EKCalendar
        if let calendar = calendar {
            targetCalendar = calendar
        } else {
            targetCalendar = try getOrCreateRemindersCalendar(for: astridList)
        }

        let link = ReminderListLink(
            astridListId: astridListId,
            astridListName: astridList.name,
            reminderCalendarId: targetCalendar.calendarIdentifier,
            reminderCalendarTitle: targetCalendar.title,
            syncDirection: direction,
            createdAt: Date(),
            lastSyncedAt: nil,
            includeCompletedTasks: includeCompletedTasks
        )

        linkedLists[astridListId] = link
        persistLinkedLists()

        print("🔗 [AppleRemindersService] Linked '\(astridList.name)' to '\(targetCalendar.title)' with direction: \(direction.rawValue)")

        // Perform initial sync
        try await syncList(astridListId)
    }

    /// Unlink an Astrid list from Reminders
    func unlinkList(_ astridListId: String) {
        linkedLists.removeValue(forKey: astridListId)
        persistLinkedLists()

        // Clean up mappings for this list
        clearMappingsForList(astridListId)

        print("🔗 [AppleRemindersService] Unlinked list: \(astridListId)")
    }

    /// Check if an Astrid list is linked to Reminders
    func isListLinked(_ astridListId: String) -> Bool {
        return linkedLists[astridListId] != nil
    }

    /// Update sync settings for a linked list
    func updateLinkSettings(_ astridListId: String, includeCompletedTasks: Bool? = nil, syncDirection: SyncDirection? = nil) {
        guard var link = linkedLists[astridListId] else { return }

        if let includeCompleted = includeCompletedTasks {
            link.includeCompletedTasks = includeCompleted
        }
        if let direction = syncDirection {
            link.syncDirection = direction
        }

        linkedLists[astridListId] = link
        persistLinkedLists()
    }

    // MARK: - Sync Operations

    /// Sync a specific linked list. Reentrancy-guarded: two interleaved
    /// imports for the same list would double-import unmapped reminders.
    func syncList(_ astridListId: String) async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        try await syncListUnguarded(astridListId)
    }

    private func syncListUnguarded(_ astridListId: String) async throws {
        guard let link = linkedLists[astridListId] else {
            throw AppleRemindersError.listNotLinked
        }

        guard let calendar = eventStore.calendar(withIdentifier: link.reminderCalendarId) else {
            throw AppleRemindersError.calendarNotFound
        }

        switch link.syncDirection {
        case .export:
            try await exportToReminders(listId: astridListId, calendar: calendar)
        case .import_:
            try await importFromReminders(listId: astridListId, calendar: calendar)
        case .bidirectional:
            try await syncBidirectional(listId: astridListId, calendar: calendar)
        }

        // Update link with last sync date
        var updatedLink = link
        updatedLink.lastSyncedAt = Date()
        linkedLists[astridListId] = updatedLink
        persistLinkedLists()

        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
    }

    /// Sync all linked lists — one guard for the whole pass (the flag must not
    /// flicker false between lists, where a debounced auto-sync could slip in).
    func syncAllLinkedLists() async throws {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        for listId in linkedLists.keys {
            try await syncListUnguarded(listId)
        }
    }

    // MARK: - Export (Astrid -> Reminders)

    private func exportToReminders(listId: String, calendar: EKCalendar) async throws {
        // Get the link config to check includeCompletedTasks
        let link = linkedLists[listId]
        let includeCompleted = link?.includeCompletedTasks ?? true

        // Get Astrid tasks for this list
        var astridTasks = taskService.tasks.filter { task in
            task.listIds?.contains(listId) == true || task.lists?.contains(where: { $0.id == listId }) == true
        }

        // Filter out completed tasks if option is disabled
        if !includeCompleted {
            astridTasks = astridTasks.filter { !$0.completed }
        }

        // Get existing mappings
        let mappings = fetchMappings(forListId: listId)
        let mappingByTaskId = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping -> (String, CDReminderMapping)? in
            guard let taskId = mapping.astridTaskId else { return nil }
            return (taskId, mapping)
        })

        var syncedCount = 0
        var wroteAny = false

        for task in astridTasks {
            do {
                if let mapping = mappingByTaskId[task.id],
                   let reminderIdentifier = mapping.reminderIdentifier,
                   let existingReminder = fetchReminder(withIdentifier: reminderIdentifier) {
                    // Dirty check: writing an unchanged reminder bumps its
                    // lastModifiedDate (re-opens the import gate) and the
                    // commit fires EKEventStoreChanged for our OWN write,
                    // rescheduling auto-sync forever — the My Tasks flicker
                    // loop. A quiescent pair must be a no-op.
                    if AppleExportPlanner.needsWrite(
                        current: currentSnapshot(of: existingReminder),
                        desired: desiredSnapshot(for: task)) {
                        updateReminder(existingReminder, from: task)
                        try eventStore.save(existingReminder, commit: false)
                        wroteAny = true

                        // Update mapping timestamps
                        updateMappingTimestamps(
                            astridTaskId: task.id,
                            astridUpdatedAt: task.updatedAt,
                            reminderUpdatedAt: existingReminder.lastModifiedDate
                        )
                    }
                } else {
                    // Create new reminder
                    let reminder = try createReminder(from: task, in: calendar)
                    try eventStore.save(reminder, commit: false)
                    wroteAny = true
                    saveMapping(
                        astridTaskId: task.id,
                        listId: listId,
                        reminderIdentifier: reminder.calendarItemIdentifier,
                        calendarId: calendar.calendarIdentifier,
                        astridUpdatedAt: task.updatedAt,
                        reminderUpdatedAt: reminder.lastModifiedDate
                    )
                }
                syncedCount += 1
            } catch {
                print("❌ [AppleRemindersService] Failed to sync task '\(task.title)': \(error)")
            }
        }

        if wroteAny {
            try eventStore.commit()
        }
        syncedTaskCount = syncedCount
        print("✅ [AppleRemindersService] Exported \(syncedCount) tasks to Reminders (\(wroteAny ? "wrote changes" : "no changes"))")
    }

    // MARK: - Import (Reminders -> Astrid)

    private func importFromReminders(listId: String, calendar: EKCalendar) async throws {
        // Get the link config to check includeCompletedTasks
        let link = linkedLists[listId]
        let includeCompleted = link?.includeCompletedTasks ?? true

        var reminders = try await fetchReminders(in: calendar)

        // Complete id set BEFORE any filtering — absence-based deletion below
        // must never be judged against a filtered list.
        let allReminderIds = Set(reminders.map { $0.calendarItemIdentifier })

        // Filter out completed reminders if option is disabled
        if !includeCompleted {
            reminders = reminders.filter { !$0.isCompleted }
        }

        // Get existing mappings
        let mappings = fetchMappings(forListId: listId)
        let mappingByReminderId = Dictionary(uniqueKeysWithValues: mappings.compactMap { mapping -> (String, CDReminderMapping)? in
            guard let reminderId = mapping.reminderIdentifier else { return nil }
            return (reminderId, mapping)
        })

        var importedCount = 0
        var updatedCount = 0

        for reminder in reminders {
            // Check if already mapped
            if let mapping = mappingByReminderId[reminder.calendarItemIdentifier],
               let astridTaskId = mapping.astridTaskId {
                // Update existing Astrid task's completion state if changed
                if let existingTask = taskService.tasks.first(where: { $0.id == astridTaskId }) {
                    // Check if Reminders is newer based on timestamps
                    let reminderUpdatedAt = reminder.lastModifiedDate ?? Date.distantPast
                    let astridUpdatedAt = existingTask.updatedAt ?? Date.distantPast

                    // Sync completion state if Reminders was updated more recently.
                    // MUST go through completeTask (canonical control point) so a
                    // repeating task rolls forward instead of just closing —
                    // updateTask(completed:) skips rollover (CLAUDE.md rule).
                    if reminderUpdatedAt > astridUpdatedAt && existingTask.completed != reminder.isCompleted {
                        do {
                            _ = try await taskService.completeTask(id: astridTaskId, completed: reminder.isCompleted, task: existingTask, source: .apple, completedAt: reminder.completionDate)
                            print("🔄 [AppleRemindersService] Updated completion state for '\(existingTask.title)' to \(reminder.isCompleted)")
                            updatedCount += 1

                            // Update mapping timestamps
                            updateMappingTimestamps(
                                astridTaskId: astridTaskId,
                                astridUpdatedAt: Date(),
                                reminderUpdatedAt: reminderUpdatedAt
                            )
                        } catch {
                            print("❌ [AppleRemindersService] Failed to update completion state: \(error)")
                        }
                    }

                    // Pull FIELD edits (title/notes/due) when the reminder changed
                    // since the stamp we recorded at the last sync — previously
                    // only completion flowed Apple→Astrid for mapped reminders.
                    if AppleEditPull.shouldPullFields(
                        reminderModified: reminder.lastModifiedDate,
                        lastSyncedReminderStamp: mapping.reminderUpdatedAt) {
                        let newTitle = reminder.title ?? existingTask.title
                        let newNotes = reminder.notes ?? ""
                        let (newDue, newIsAllDay) = mapDueDateFromApple(reminder.dueDateComponents)
                        let dueChanged = existingTask.dueDateTime != newDue || existingTask.isAllDay != newIsAllDay
                        if newTitle != existingTask.title || newNotes != existingTask.description || dueChanged {
                            _ = try? await taskService.updateTask(
                                taskId: astridTaskId,
                                title: newTitle == existingTask.title ? nil : newTitle,
                                description: newNotes == existingTask.description ? nil : newNotes,
                                dueDateTime: dueChanged ? (newDue ?? Date.distantPast) : nil,
                                isAllDay: dueChanged ? newIsAllDay : nil,
                                source: .apple)
                            updatedCount += 1
                        }
                        updateMappingTimestamps(
                            astridTaskId: astridTaskId,
                            astridUpdatedAt: Date(),
                            reminderUpdatedAt: reminder.lastModifiedDate)
                    }
                }
                continue
            }

            // Skip completed reminders for new imports if option is disabled
            if !includeCompleted && reminder.isCompleted {
                continue
            }

            // Extract data from reminder for new task
            let title = reminder.title ?? "Untitled"
            let description = reminder.notes
            let priority = mapPriorityFromApple(reminder.priority).rawValue
            let (dueDate, isAllDay) = mapDueDateFromApple(reminder.dueDateComponents)

            do {
                // Create new Astrid task using TaskService
                // Reminders are personal — imported tasks belong to the
                // syncing user (unassigned tasks vanish from My Tasks).
                let newTask = try await taskService.createTask(
                    listIds: [listId],
                    title: title,
                    description: description,
                    priority: priority,
                    whenDate: isAllDay ? dueDate : nil,
                    whenTime: isAllDay ? nil : dueDate,
                    assigneeId: AuthManager.shared.userId,
                    isPrivate: nil,
                    repeating: nil,
                    source: .apple
                )

                // If the reminder is completed, mark the new task as completed too
                // Use completeTask() to properly handle repeating task logic
                if reminder.isCompleted {
                    _ = try await taskService.completeTask(id: newTask.id, completed: true, task: newTask, source: .apple, completedAt: reminder.completionDate)
                }

                saveMapping(
                    astridTaskId: newTask.id,
                    listId: listId,
                    reminderIdentifier: reminder.calendarItemIdentifier,
                    calendarId: calendar.calendarIdentifier,
                    astridUpdatedAt: newTask.updatedAt,
                    reminderUpdatedAt: reminder.lastModifiedDate
                )
                importedCount += 1
            } catch {
                print("❌ [AppleRemindersService] Failed to import reminder '\(title)': \(error)")
            }
        }

        // Reminder deleted in Apple → delete the mapped Astrid task. Judged
        // against the COMPLETE unfiltered reminder set (SyncDeletionPolicy
        // invariant: never infer deletion from a filtered/partial listing).
        let deletionLinks = mappings.compactMap { mapping -> SyncDeletionPolicy.Link? in
            guard let taskId = mapping.astridTaskId, let reminderId = mapping.reminderIdentifier else { return nil }
            return SyncDeletionPolicy.Link(taskId: taskId, remoteId: reminderId)
        }
        let toDelete = SyncDeletionPolicy.localDeletions(
            links: deletionLinks, fullRemoteIds: allReminderIds,
            truncated: false, explicitlyDeletedRemoteIds: [])
        for link in toDelete {
            if taskService.tasks.contains(where: { $0.id == link.taskId }) {
                try? await taskService.deleteTask(id: link.taskId)
            }
            if let mapping = mappingByReminderId[link.remoteId] {
                deleteMapping(mapping)
            }
        }

        syncedTaskCount = importedCount + updatedCount
        print("✅ [AppleRemindersService] Imported \(importedCount) new reminders, updated \(updatedCount) existing tasks")
    }

    // MARK: - Bidirectional Sync

    private func syncBidirectional(listId: String, calendar: EKCalendar) async throws {
        // For bidirectional sync:
        // 1. Export new/updated Astrid tasks to Reminders
        // 2. Import new Reminders to Astrid
        // 3. Handle conflicts (Astrid wins for ties)

        try await exportToReminders(listId: listId, calendar: calendar)
        try await importFromReminders(listId: listId, calendar: calendar)
    }

    // MARK: - Reminder CRUD

    /// Fetch a reminder by its identifier
    func fetchReminder(withIdentifier identifier: String) -> EKReminder? {
        return eventStore.calendarItem(withIdentifier: identifier) as? EKReminder
    }

    /// Fetch all reminders in a calendar
    /// The user deleted an Astrid task: remove its mapped reminder (and the
    /// mapping) so Reminders mirrors the deletion and import can't resurrect it.
    func noteTaskDeleted(taskId: String) async {
        let request = CDReminderMapping.fetchRequest()
        request.predicate = NSPredicate(format: "astridTaskId == %@", taskId)
        guard let mapping = try? coreDataManager.viewContext.fetch(request).first else { return }
        if let reminderId = mapping.reminderIdentifier,
           let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder {
            do {
                try eventStore.remove(reminder, commit: true)
            } catch {
                // Keep the mapping: a live-but-unmapped reminder would be
                // re-imported as a brand-new task on the next pass.
                print("⚠️ [AppleRemindersService] Failed to remove reminder for deleted task: \(error)")
                return
            }
        }
        coreDataManager.viewContext.delete(mapping)
        try? coreDataManager.viewContext.save()
    }

    private func deleteMapping(_ mapping: CDReminderMapping) {
        coreDataManager.viewContext.delete(mapping)
        try? coreDataManager.viewContext.save()
    }

    func fetchReminders(in calendar: EKCalendar) async throws -> [EKReminder] {
        let predicate = eventStore.predicateForReminders(in: [calendar])

        return try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                if let reminders {
                    continuation.resume(returning: reminders)
                } else {
                    // nil = EventKit failure (permission revoked / store error) —
                    // MUST throw, or the empty set feeds absence-based deletion
                    // and mass-deletes every mapped task.
                    continuation.resume(throwing: AppleRemindersError.syncFailed(
                        NSError(domain: "AppleReminders", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "Reminder fetch returned no result"])))
                }
            }
        }
    }

    /// Create a new EKReminder from an Astrid Task
    func createReminder(from task: Task, in calendar: EKCalendar) throws -> EKReminder {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.calendar = calendar
        updateReminder(reminder, from: task)
        return reminder
    }

    /// Update an EKReminder with data from an Astrid Task
    /// Desired export state for a task — MUST mirror `updateReminder`'s
    /// transformations field-for-field (the dirty check compares these).
    func desiredSnapshot(for task: Task) -> AppleReminderSnapshot {
        var dueComponents: DateComponents?
        if let dueDateTime = task.dueDateTime {
            if task.isAllDay {
                var utc = Calendar.current
                utc.timeZone = TimeZone(identifier: "UTC")!
                var components = utc.dateComponents([.year, .month, .day], from: dueDateTime)
                components.calendar = nil
                dueComponents = components
            } else {
                dueComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: dueDateTime)
            }
        }
        return AppleReminderSnapshot(
            title: task.title,
            notes: task.description.isEmpty ? nil : task.description,
            isCompleted: task.completed,
            priority: mapPriorityToApple(task.priority),
            dueKey: AppleExportPlanner.dueKey(dueComponents),
            recurrenceKey: AppleExportPlanner.recurrenceKey(
                mapRecurrenceToApple(task.repeating, data: task.repeatingData)),
            alarmKey: AppleExportPlanner.alarmKey(reminderTime: task.reminderTime))
    }

    func currentSnapshot(of reminder: EKReminder) -> AppleReminderSnapshot {
        AppleReminderSnapshot(
            title: reminder.title ?? "",
            notes: (reminder.notes?.isEmpty ?? true) ? nil : reminder.notes,
            isCompleted: reminder.isCompleted,
            priority: reminder.priority,
            dueKey: AppleExportPlanner.dueKey(reminder.dueDateComponents),
            recurrenceKey: AppleExportPlanner.recurrenceKey(reminder.recurrenceRules?.first),
            alarmKey: AppleExportPlanner.alarmKey(reminder.alarms))
    }

    func updateReminder(_ reminder: EKReminder, from task: Task) {
        reminder.title = task.title
        reminder.notes = task.description.isEmpty ? nil : task.description
        reminder.isCompleted = task.completed
        reminder.priority = mapPriorityToApple(task.priority)

        // Due date. All-day dues are stored at UTC midnight — read their
        // calendar day in UTC, or the reminder lands on the previous local day
        // for anyone west of UTC.
        if let dueDateTime = task.dueDateTime {
            if task.isAllDay {
                var utc = Calendar.current
                utc.timeZone = TimeZone(identifier: "UTC")!
                var components = utc.dateComponents([.year, .month, .day], from: dueDateTime)
                components.calendar = nil
                reminder.dueDateComponents = components
            } else {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: dueDateTime)
            }
        } else {
            reminder.dueDateComponents = nil
        }

        // Recurrence
        reminder.recurrenceRules = nil
        if let recurrenceRule = mapRecurrenceToApple(task.repeating, data: task.repeatingData) {
            reminder.addRecurrenceRule(recurrenceRule)
        }

        // Alarm for reminder time (if different from due date)
        reminder.alarms?.forEach { reminder.removeAlarm($0) }
        if let reminderTime = task.reminderTime {
            let alarm = EKAlarm(absoluteDate: reminderTime)
            reminder.addAlarm(alarm)
        }
    }

    /// Create an Astrid Task from an EKReminder
    func createTask(from reminder: EKReminder, listId: String) -> Task {
        let (dueDate, isAllDay) = mapDueDateFromApple(reminder.dueDateComponents)
        let (repeating, repeatingData) = mapRecurrenceFromApple(reminder.recurrenceRules?.first)

        return Task(
            id: "temp_reminder_\(UUID().uuidString)",
            title: reminder.title ?? "Untitled",
            description: reminder.notes ?? "",
            dueDateTime: dueDate,
            isAllDay: isAllDay,
            repeating: repeating,
            repeatingData: repeatingData,
            priority: mapPriorityFromApple(reminder.priority),
            listIds: [listId],
            completed: reminder.isCompleted,
            createdAt: reminder.creationDate,
            updatedAt: reminder.lastModifiedDate
        )
    }

    // MARK: - Field Mapping

    /// Map Astrid priority to Apple Reminders priority
    func mapPriorityToApple(_ priority: Task.Priority) -> Int {
        switch priority {
        case .none: return 0
        case .low: return 9
        case .medium: return 5
        case .high: return 1
        }
    }

    /// Map Apple Reminders priority to Astrid priority
    func mapPriorityFromApple(_ priority: Int) -> Task.Priority {
        switch priority {
        case 1...4: return .high
        case 5: return .medium
        case 6...9: return .low
        default: return .none
        }
    }

    /// Map Astrid recurrence to Apple recurrence rule
    func mapRecurrenceToApple(_ repeating: Task.Repeating?, data: CustomRepeatingPattern?) -> EKRecurrenceRule? {
        guard let repeating = repeating else { return nil }

        switch repeating {
        case .never:
            return nil
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)
        case .custom:
            return buildCustomRecurrenceRule(from: data)
        }
    }

    private func buildCustomRecurrenceRule(from pattern: CustomRepeatingPattern?) -> EKRecurrenceRule? {
        guard let pattern = pattern else { return nil }

        let frequency: EKRecurrenceFrequency
        switch pattern.unit {
        case "days": frequency = .daily
        case "weeks": frequency = .weekly
        case "months": frequency = .monthly
        case "years": frequency = .yearly
        default: return nil
        }

        let interval = pattern.interval ?? 1
        var end: EKRecurrenceEnd?

        if pattern.endCondition == "after_occurrences", let count = pattern.endAfterOccurrences {
            end = EKRecurrenceEnd(occurrenceCount: count)
        } else if pattern.endCondition == "until_date", let date = pattern.endUntilDate {
            end = EKRecurrenceEnd(end: date)
        }

        return EKRecurrenceRule(recurrenceWith: frequency, interval: interval, end: end)
    }

    /// Map Apple recurrence rule to Astrid recurrence
    func mapRecurrenceFromApple(_ rule: EKRecurrenceRule?) -> (Task.Repeating?, CustomRepeatingPattern?) {
        guard let rule = rule else { return (.never, nil) }

        // Simple patterns
        if rule.interval == 1 {
            switch rule.frequency {
            case .daily: return (.daily, nil)
            case .weekly: return (.weekly, nil)
            case .monthly: return (.monthly, nil)
            case .yearly: return (.yearly, nil)
            @unknown default: return (.never, nil)
            }
        }

        // Custom pattern
        let unit: String
        switch rule.frequency {
        case .daily: unit = "days"
        case .weekly: unit = "weeks"
        case .monthly: unit = "months"
        case .yearly: unit = "years"
        @unknown default: return (.never, nil)
        }

        var endCondition = "never"
        var endAfterOccurrences: Int?
        var endUntilDate: Date?

        if let recurrenceEnd = rule.recurrenceEnd {
            if recurrenceEnd.occurrenceCount > 0 {
                endCondition = "after_occurrences"
                endAfterOccurrences = recurrenceEnd.occurrenceCount
            } else if let endDate = recurrenceEnd.endDate {
                endCondition = "until_date"
                endUntilDate = endDate
            }
        }

        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: unit,
            interval: rule.interval,
            endCondition: endCondition,
            endAfterOccurrences: endAfterOccurrences,
            endUntilDate: endUntilDate
        )

        return (.custom, pattern)
    }

    /// Map Apple due date components to Astrid date and isAllDay
    func mapDueDateFromApple(_ components: DateComponents?) -> (Date?, Bool) {
        guard let components = components else { return (nil, true) }

        let isAllDay = components.hour == nil && components.minute == nil
        if isAllDay {
            // All-day dues live at UTC midnight (CLAUDE.md contract) — building
            // with the local calendar shifts the visible date for non-UTC users.
            var utc = Calendar.current
            utc.timeZone = TimeZone(identifier: "UTC")!
            return (utc.date(from: components), true)
        }
        return (Calendar.current.date(from: components), false)
    }

    // MARK: - Mapping Persistence (CoreData)

    func saveMapping(astridTaskId: String, listId: String, reminderIdentifier: String, calendarId: String, astridUpdatedAt: Date? = nil, reminderUpdatedAt: Date? = nil) {
        let context = coreDataManager.viewContext

        // Check for existing mapping
        let request = CDReminderMapping.fetchRequest()
        request.predicate = NSPredicate(format: "astridTaskId == %@", astridTaskId)

        do {
            let existing = try context.fetch(request)
            let mapping: CDReminderMapping
            if let existingMapping = existing.first {
                mapping = existingMapping
            } else {
                mapping = CDReminderMapping(context: context)
            }

            mapping.astridTaskId = astridTaskId
            mapping.astridListId = listId
            mapping.reminderIdentifier = reminderIdentifier
            mapping.reminderCalendarIdentifier = calendarId
            mapping.lastSyncedAt = Date()
            mapping.astridUpdatedAt = astridUpdatedAt
            mapping.reminderUpdatedAt = reminderUpdatedAt

            try context.save()
        } catch {
            print("❌ [AppleRemindersService] Failed to save mapping: \(error)")
        }
    }

    func updateMappingTimestamps(astridTaskId: String, astridUpdatedAt: Date?, reminderUpdatedAt: Date?) {
        let context = coreDataManager.viewContext

        let request = CDReminderMapping.fetchRequest()
        request.predicate = NSPredicate(format: "astridTaskId == %@", astridTaskId)

        do {
            if let mapping = try context.fetch(request).first {
                mapping.astridUpdatedAt = astridUpdatedAt
                mapping.reminderUpdatedAt = reminderUpdatedAt
                mapping.lastSyncedAt = Date()
                try context.save()
            }
        } catch {
            print("❌ [AppleRemindersService] Failed to update mapping timestamps: \(error)")
        }
    }

    func fetchMappings(forListId listId: String) -> [CDReminderMapping] {
        let request = CDReminderMapping.fetchRequest()
        request.predicate = NSPredicate(format: "astridListId == %@", listId)

        do {
            return try coreDataManager.viewContext.fetch(request)
        } catch {
            print("❌ [AppleRemindersService] Failed to fetch mappings: \(error)")
            return []
        }
    }

    func clearMappingsForList(_ listId: String) {
        let context = coreDataManager.viewContext
        let request = CDReminderMapping.fetchRequest()
        request.predicate = NSPredicate(format: "astridListId == %@", listId)

        do {
            let mappings = try context.fetch(request)
            for mapping in mappings {
                context.delete(mapping)
            }
            try context.save()
        } catch {
            print("❌ [AppleRemindersService] Failed to clear mappings: \(error)")
        }
    }
}

// MARK: - Supporting Types

/// Represents a link between an Astrid list and a Reminders calendar
struct ReminderListLink: Codable, Identifiable {
    var id: String { astridListId }

    let astridListId: String
    let astridListName: String
    let reminderCalendarId: String
    let reminderCalendarTitle: String
    var syncDirection: SyncDirection
    let createdAt: Date
    var lastSyncedAt: Date?
    var includeCompletedTasks: Bool = true  // Option to sync completed tasks
}

/// Sync direction for a linked list
enum SyncDirection: String, Codable, CaseIterable {
    case export = "export"           // Astrid -> Reminders only
    case import_ = "import"          // Reminders -> Astrid only
    case bidirectional = "bidirectional"  // Two-way sync

    var displayName: String {
        switch self {
        case .export: return "Export to Reminders"
        case .import_: return "Import from Reminders"
        case .bidirectional: return "Two-way Sync"
        }
    }

    var description: String {
        switch self {
        case .export: return "Push Astrid tasks to Apple Reminders"
        case .import_: return "Pull Apple Reminders into Astrid"
        case .bidirectional: return "Keep both apps in sync"
        }
    }
}

// MARK: - Errors

enum AppleRemindersError: LocalizedError {
    case notAuthorized
    case noCalendarSource
    case listNotFound
    case listNotLinked
    case calendarNotFound
    case syncFailed(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Reminders access not authorized. Please enable in Settings."
        case .noCalendarSource:
            return "No calendar source available for creating reminders."
        case .listNotFound:
            return "Astrid list not found."
        case .listNotLinked:
            return "List is not linked to Apple Reminders."
        case .calendarNotFound:
            return "Linked Reminders calendar not found."
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        }
    }
}
