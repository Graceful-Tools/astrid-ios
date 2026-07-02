import Foundation
import Combine
import CoreData
import UIKit

/// Task service using API v1 with offline support via CoreData
/// Handles task operations and syncing across all user's lists
@MainActor
class TaskService: ObservableObject {
    static let shared = TaskService()

    @Published var tasks: [Task] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0
    @Published var isSyncingPendingOperations = false
    @Published var hasCompletedInitialLoad = false  // Track if initial data load is done

    private let apiClient = AstridAPIClient.shared
    private let notificationManager = NotificationManager.shared
    private let badgeManager = BadgeManager.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cachedTasks: [String: Task] = [:]
    private var syncTimer: Timer?
    private var networkObserver: NSObjectProtocol?

    /// Mapping of temp list IDs to their real server IDs (populated when lists sync)
    private var tempListIdMapping: [String: String] = [:]

    /// Mapping of temp task IDs to their real server IDs.
    /// Used to redirect edits from stale task detail views that still hold the temp ID.
    private var tempTaskIdMapping: [String: String] = TempTaskMappingStore.load()

    /// Real server id for a temporary (offline-created) task id, once it has
    /// synced; nil if the task hasn't been created on the server yet. Used by
    /// CommentService so a photo/comment attached to an offline-created task is
    /// posted to the real task instead of 404'ing against the temp id.
    func mappedRealTaskId(for tempId: String) -> String? {
        tempTaskIdMapping[tempId]
    }

    /// Records that an offline-created task's temporary id now corresponds to a
    /// real server id. MUST be called from every temp→real transition (online
    /// create AND offline sync) so callers like CommentService can re-target
    /// pending children (e.g. a photo-comment) onto the real task.
    func recordTempTaskMapping(tempId: String, realId: String) {
        guard tempId.hasPrefix("temp_"), tempId != realId else { return }
        // Persist durably so a relaunch between the task syncing and a child
        // (photo/comment) syncing doesn't strand the child.
        tempTaskIdMapping = TempTaskMappingStore.recording(tempTaskIdMapping, temp: tempId, real: realId)
        TempTaskMappingStore.save(tempTaskIdMapping)
        // Let pending children (e.g. a photo-comment queued offline) re-sync now
        // that the parent task has a real id — closes the race where the
        // attachment finished uploading before the task synced.
        NotificationCenter.default.post(
            name: .taskTempIdResolved,
            object: nil,
            userInfo: ["tempId": tempId, "realId": realId]
        )
    }

    /// Reconcile the optimistic temp task with the server task once the Outbox
    /// `createTask` handler succeeds — the Outbox-authoritative equivalent of the
    /// post-server block in `createTask`. Owns: temp→real mapping, cache/`tasks`
    /// swap, CoreData temp-delete + real-save (marked synced), and clearing the
    /// `pendingCreates` guard.
    ///
    /// Idempotent by design: during dual-write the legacy path usually reconciles
    /// first (temp already gone), so this only ensures the mapping and returns.
    func reconcileOutboxCreatedTask(tempId: String, serverTask: Task) async {
        // Always ensure the mapping — a dependent comment/update may target it.
        recordTempTaskMapping(tempId: tempId, realId: serverTask.id)

        guard cachedTasks[tempId] != nil || tasks.contains(where: { $0.id == tempId }) else {
            return  // Legacy path already reconciled (or nothing to swap).
        }
        let temp = cachedTasks[tempId] ?? tasks.first(where: { $0.id == tempId })

        // Carry forward client-side fields the server response may not echo.
        var reconciled = serverTask
        reconciled.clientRequestId = temp?.clientRequestId ?? serverTask.clientRequestId
        var mergedListIds = serverTask.listIds ?? []
        for id in temp?.listIds ?? [] where !mergedListIds.contains(id) { mergedListIds.append(id) }
        reconciled.listIds = mergedListIds

        // Swap temp → real in the in-memory caches.
        cachedTasks.removeValue(forKey: tempId)
        cachedTasks[serverTask.id] = reconciled
        if let idx = tasks.firstIndex(where: { $0.id == tempId }) {
            tasks[idx] = reconciled
        }

        // Persist: remove temp row, save real. If any list ids are still temp
        // (offline-created list), keep it pending_list_sync like the legacy path.
        let hasTempListIds = mergedListIds.contains { $0.hasPrefix("temp_") }
        try? await deleteTaskFromCoreData(tempId)
        try? await saveTaskToCoreData(reconciled, syncStatus: hasTempListIds ? "pending_list_sync" : "synced")

        pendingCreates.remove(tempId)
    }

    /// Mark a task's CoreData row synced once the Outbox `updateTask` handler
    /// succeeds (the Outbox-authoritative equivalent of the post-PUT block in
    /// `updateTask`). Uses the current in-memory task, so a newer optimistic edit
    /// simply stays queued as its own Outbox entry and re-reconciles on success.
    func reconcileOutboxUpdatedTask(taskId: String) async {
        guard let task = cachedTasks[taskId] ?? tasks.first(where: { $0.id == taskId }) else { return }
        try? await saveTaskToCoreData(task, syncStatus: "synced")
        updatePendingOperationsCount()
    }

    /// Tracks temp IDs with an in-flight createTask API call to prevent
    /// syncPendingOperations from creating a duplicate on the server.
    private var pendingCreates: Set<String> = []

    /// IDs of tasks deleted locally. Persisted to UserDefaults so it survives app restarts.
    /// Without persistence, closing the app after deleting tasks loses the delete tracking:
    /// syncPendingOperations pushes the delete and clears CoreData, but if the server still
    /// returns the task briefly, there's nothing left to filter it → deleted tasks reappear.
    private static let recentlyDeletedIdsKey = "recentlyDeletedTaskIds"
    private var recentlyDeletedIds: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.recentlyDeletedIdsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.recentlyDeletedIdsKey) }
    }

    private init() {
        setupNetworkObserver()
        startBackgroundSync()
        // REMOVED: setupAppLifecycleObserver() - Saving all tasks to Core Data freezes the app

        // Load cached tasks synchronously to ensure data is available before any UI renders
        // This is CRITICAL for offline mode - tasks must be in memory before network calls fail
        loadCachedTasks()
    }

    // MARK: - Initialization

    /// Load cached tasks from CoreData on startup (synchronous, blocking)
    /// CRITICAL: This must be synchronous to ensure tasks are loaded before UI renders
    /// Without this, opening the app offline shows no tasks even though they're cached
    private func loadCachedTasks() {
        do {
            // Load from viewContext synchronously on main thread
            // This is safe because init() already runs on MainActor and reads are fast
            let fetchRequest = CDTask.fetchRequest()
            let cdTasks = try coreDataManager.viewContext.fetch(fetchRequest)

            // Convert to domain models, excluding tasks pending deletion.
            // Also exclude tasks tracked in recentlyDeletedIds (persisted in UserDefaults)
            // in case CoreData status was lost from a previous bug.
            let deletedIds = recentlyDeletedIds
            self.tasks = cdTasks
                .filter { $0.syncStatus != "pending_delete" && !deletedIds.contains($0.id) }
                .map { $0.toDomainModel() }
            for task in self.tasks {
                cachedTasks[task.id] = task
            }
            updatePendingOperationsCount()
            print("✅ [TaskService] Loaded \(tasks.count) tasks from cache synchronously (\(pendingOperationsCount) pending)")
            // Mark as loaded IMMEDIATELY so UI shows cached data right away
            // This is critical for offline mode - user sees data even before network sync
            self.hasCompletedInitialLoad = true
        } catch {
            print("❌ [TaskService] Failed to load cached tasks: \(error)")
            self.hasCompletedInitialLoad = true  // Mark as loaded even on error to not block UI
        }
    }

    /// Setup network observer to sync when connection is restored
    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                print("🔄 [TaskService] Network restored - syncing pending operations")
                try? await self?.syncPendingOperations()
            }
        }
    }

    /// Start background sync timer (every 60 seconds)
    private func startBackgroundSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                guard let self = self else { return }
                // Only sync if we have pending operations and network is available
                if self.pendingOperationsCount > 0 && self.networkMonitor.isConnected {
                    try? await self.syncPendingOperations()
                }
            }
        }
    }

    deinit {
        syncTimer?.invalidate()
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Task Operations

    func fetchTask(id: String, forceRefresh: Bool = false) async throws -> Task {
        // Return cached if available and not forcing refresh
        if !forceRefresh, let cached = cachedTasks[id] {
            return cached
        }

        let task = try await apiClient.getTask(id: id)
        cachedTasks[id] = task

        // Update in the tasks array if it exists there
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index] = task
        }

        return task
    }

    func createTask(
        listIds: [String],
        title: String,
        description: String? = nil,
        priority: Int? = nil,
        whenDate: Date? = nil,     // The date (maps to backend 'when')
        whenTime: Date? = nil,     // The time (maps to backend 'dueDateTime', nil for all-day)
        assigneeId: String? = nil,
        isPrivate: Bool? = nil,
        repeating: String? = nil,
        repeatingData: CustomRepeatingPattern? = nil
    ) async throws -> Task {
        // OPTIMISTIC UPDATE: Create temporary task immediately
        let tempId = "temp_\(UUID().uuidString)"
        let clientRequestId = UUID().uuidString  // Idempotency key for server dedup
        let currentUserId = AuthManager.shared.userId

        // Determine dueDateTime and isAllDay based on provided dates
        let dueDateTime: Date?
        let isAllDay: Bool
        if let whenTime = whenTime {
            // Timed task - use time
            dueDateTime = whenTime
            isAllDay = false
        } else if let whenDate = whenDate {
            // All-day task - use date
            dueDateTime = whenDate
            isAllDay = true
        } else {
            // No date set
            dueDateTime = nil
            isAllDay = false
        }

        // Resolve full TaskList objects from ListService cache so the row
        // can render list badges immediately (works offline too)
        let resolvedLists: [TaskList]? = listIds.isEmpty ? nil : listIds.compactMap { listId in
            ListService.shared.lists.first { $0.id == listId }
        }

        let optimisticTask = Task(
            id: tempId,
            title: title,
            description: description ?? "",
            assigneeId: assigneeId,
            assignee: nil,
            creatorId: currentUserId, // Set creator to current user for permission checks
            creator: nil,
            dueDateTime: dueDateTime,
            isAllDay: isAllDay,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: repeating.flatMap { Task.Repeating(rawValue: $0) } ?? .never,
            repeatingData: repeatingData,
            priority: priority.flatMap { Task.Priority(rawValue: $0) } ?? .none,
            lists: resolvedLists,
            listIds: listIds,
            isPrivate: isPrivate ?? true,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: Date(),
            updatedAt: Date(),
            originalTaskId: nil,
            sourceListId: nil,
            clientRequestId: clientRequestId
        )

        // Update UI immediately
        cachedTasks[tempId] = optimisticTask
        tasks.insert(optimisticTask, at: 0)
        print("⚡️ [TaskService] Optimistically created task: \(title)")

        // Save to CoreData with pending status for offline support (CRITICAL: await to ensure persistence)
        // This blocks until save completes, preventing data loss on force close
        // clientRequestId is persisted via CDTask.update(from:) since optimisticTask carries it
        do {
            try await saveTaskToCoreData(optimisticTask, syncStatus: "pending")
            print("✅ [TaskService] Persisted new task to CoreData (clientRequestId: \(clientRequestId))")
        } catch {
            print("⚠️ [TaskService] Failed to save to CoreData, but task is in memory: \(error)")
        }

        // Track this create so syncPendingOperations won't duplicate it
        pendingCreates.insert(tempId)

        // Make server call in background
        do {
            // CRITICAL: Filter out temp_ list IDs - server doesn't know about them
            // Tasks with temp list IDs will be synced later when lists get real IDs
            let serverListIds = listIds.filter { !$0.hasPrefix("temp_") }
            let hasTempListIds = listIds.count != serverListIds.count

            if hasTempListIds {
                print("⚠️ [TaskService] Filtering out temp_ list IDs for API call. Original: \(listIds), Filtered: \(serverListIds)")
            }

            // Unified Outbox dual-write (no-op unless OutboxConfig.dualWriteEnabled).
            // Sends the same create through the Outbox with the SAME clientRequestId
            // so the server dedupes — lets us verify the Outbox path in production
            // before cutting over, with zero risk of duplicates.
            OutboxManager.shared.enqueueCreateTask(
                CreateTaskOutboxPayload(
                    title: title,
                    listIds: serverListIds.isEmpty ? nil : serverListIds,
                    description: description,
                    priority: priority,
                    assigneeId: assigneeId,
                    dueDateTime: dueDateTime,
                    isAllDay: isAllDay,
                    isPrivate: isPrivate,
                    repeating: repeating,
                    repeatingData: repeatingData,
                    tempId: tempId
                ),
                clientRequestId: clientRequestId
            )

            // CUTOVER (flag-gated): when the Outbox is authoritative for
            // createTask, skip the legacy inline server call entirely. The Outbox
            // handler does the server create + reconciliation (temp→real swap,
            // mark synced) when it drains — online now, or on reconnect if offline.
            if OutboxConfig.sourceOfTruthEnabled {
                return optimisticTask
            }

            // Send dueDateTime and isAllDay to backend
            // For all-day tasks: dueDateTime=date at UTC midnight, isAllDay=true
            // For timed tasks: dueDateTime=date+time, isAllDay=false
            let task = try await apiClient.createTask(
                title: title,
                listIds: serverListIds.isEmpty ? nil : serverListIds,  // Use filtered list IDs
                description: description,
                priority: priority,
                assigneeId: assigneeId,
                dueDateTime: dueDateTime,  // Already computed above based on whenDate/whenTime
                isAllDay: isAllDay,        // Already computed above
                isPrivate: isPrivate,
                repeating: repeating,
                repeatingData: repeatingData,
                clientRequestId: clientRequestId  // Idempotency key for server dedup
            )

            // NOTE: pendingCreates.remove(tempId) is deferred until AFTER CoreData is updated
            // to prevent syncPendingOperations() from re-creating the task at an await suspension point.

            // Part C: Check if the user edited the temp task while the API call was in flight.
            // If so, overlay local editable fields onto the server response so edits aren't lost.
            let currentLocal = cachedTasks[tempId]
            let wasEditedDuringFlight = currentLocal != nil
                && currentLocal!.updatedAt != optimisticTask.updatedAt

            // Replace temporary task with server response
            cachedTasks.removeValue(forKey: tempId)

            // CRITICAL: Preserve clientRequestId so that if this task is re-saved to
            // CoreData as "pending" (e.g. user edited during flight), the idempotency
            // key survives for sync retries. The server response typically doesn't echo
            // clientRequestId back, so we must carry it forward from the original create.
            var taskWithListIds = task
            taskWithListIds.clientRequestId = clientRequestId

            // CRITICAL: Preserve listIds from the original request
            // The server response may not include listIds (or may have them in a different format)
            // So we merge our original listIds with whatever the server returns
            var mergedListIds = task.listIds ?? []
            for originalListId in listIds {
                if !mergedListIds.contains(originalListId) {
                    mergedListIds.append(originalListId)
                }
            }
            taskWithListIds.listIds = mergedListIds

            // Overlay local edits onto server response if user edited during flight
            if wasEditedDuringFlight, let editedLocal = currentLocal {
                taskWithListIds.title = editedLocal.title
                taskWithListIds.description = editedLocal.description
                taskWithListIds.priority = editedLocal.priority
                taskWithListIds.dueDateTime = editedLocal.dueDateTime
                taskWithListIds.isAllDay = editedLocal.isAllDay
                taskWithListIds.assigneeId = editedLocal.assigneeId
                taskWithListIds.repeating = editedLocal.repeating
                taskWithListIds.repeatingData = editedLocal.repeatingData
                taskWithListIds.completed = editedLocal.completed
                taskWithListIds.isPrivate = editedLocal.isPrivate
                if let editedListIds = editedLocal.listIds {
                    taskWithListIds.listIds = editedListIds
                }
                print("🔀 [TaskService] Preserved local edits made during create flight")
            }

            cachedTasks[task.id] = taskWithListIds

            // Map temp ID → real ID so stale detail views can route edits correctly
            recordTempTaskMapping(tempId: tempId, realId: task.id)

            if let index = tasks.firstIndex(where: { $0.id == tempId }) {
                tasks[index] = taskWithListIds
            }

            // Update CoreData with server response (CRITICAL: await to ensure persistence)
            // If task has temp list IDs, mark as "pending_list_sync" so we can update later
            // If user edited during flight, mark as "pending" so edits sync on next cycle
            let syncStatus = wasEditedDuringFlight ? "pending" : (hasTempListIds ? "pending_list_sync" : "synced")
            do {
                try await deleteTaskFromCoreData(tempId)  // Remove temp task
                try await saveTaskToCoreData(taskWithListIds, syncStatus: syncStatus)
                print("✅ [TaskService] Updated CoreData with server response")
            } catch {
                print("⚠️ [TaskService] Failed to update CoreData after task creation: \(error)")
            }

            // Create is done AND CoreData is updated — now safe to stop guarding against duplicate syncs.
            // This MUST happen after CoreData update to prevent syncPendingOperations() from finding
            // the temp task with "pending" status while pendingCreates no longer guards it.
            pendingCreates.remove(tempId)

            print("✅ [TaskService] Server confirmed task: \(task.title)")

            // Schedule notification if task has due date
            if task.dueDateTime != nil {
                do {
                    try await notificationManager.scheduleNotification(for: task)
                } catch {
                    print("⚠️ [TaskService] Failed to schedule notification: \(error)")
                }
            }

            updatePendingOperationsCount()

            // Update app badge with new task count
            await badgeManager.updateBadge(with: self.tasks)

            return task
        } catch {
            // Create failed — allow syncPendingOperations to retry later
            pendingCreates.remove(tempId)

            // DON'T ROLLBACK: Keep task as "pending" for offline support
            print("⚠️ [TaskService] Failed to sync task to server, keeping as pending: \(error)")
            updatePendingOperationsCount()

            // Update badge even for pending tasks
            await badgeManager.updateBadge(with: self.tasks)

            // Return the optimistic task so UI shows it
            return optimisticTask
        }
    }

    func updateTask(
        taskId: String,
        title: String? = nil,
        description: String? = nil,
        priority: Int? = nil,
        completed: Bool? = nil,
        when: Date? = nil,  // DEPRECATED: Use dueDateTime instead
        whenTime: Date? = nil,  // DEPRECATED: Use isAllDay instead
        dueDateTime: Date? = nil,  // NEW: The due date/time
        isAllDay: Bool? = nil,  // NEW: All-day task flag
        assigneeId: String? = nil,
        repeating: String? = nil,
        repeatingData: CustomRepeatingPattern? = nil,
        repeatFrom: String? = nil,
        timerDuration: Int? = nil,
        lastTimerValue: String? = nil,
        listIds: [String]? = nil,
        task: Task? = nil  // Optional: provide task if not in cache (e.g., from featured lists)
    ) async throws -> Task {
        // Resolve stale temp ID → real server ID.
        // When a user opens a task detail view for a newly created task, the view
        // captures the temp_ ID.  If createTask() completes and swaps to the real
        // ID while the view is still open, subsequent edits arrive here with the
        // old temp_ ID.  Without this resolution those edits would re-create the
        // temp task in CoreData → duplicates on next sync.
        let resolvedId = tempTaskIdMapping[taskId] ?? taskId

        // OPTIMISTIC UPDATE: Store old task for rollback
        // First check cache, then provided task parameter (for featured/public list tasks)
        guard let originalTask = cachedTasks[resolvedId] ?? tasks.first(where: { $0.id == resolvedId }) ?? task else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        // Create optimistic updated task
        var optimisticTask = originalTask
        if let title = title { optimisticTask.title = title }
        if let description = description { optimisticTask.description = description }
        if let priority = priority { optimisticTask.priority = Task.Priority(rawValue: priority) ?? .none }
        if let completed = completed { optimisticTask.completed = completed }

        // Handle new dueDateTime + isAllDay OR legacy when/whenTime parameters
        if let dueDateTime = dueDateTime {
            optimisticTask.dueDateTime = (dueDateTime == Date.distantPast) ? nil : dueDateTime
        } else if let whenTime = whenTime {
            // Legacy: whenTime parameter (Date.distantPast means clear)
            optimisticTask.dueDateTime = (whenTime == Date.distantPast) ? nil : whenTime
            optimisticTask.isAllDay = false
        } else if let when = when {
            // Legacy: when parameter (date only, all-day)
            optimisticTask.dueDateTime = (when == Date.distantPast) ? nil : when
            optimisticTask.isAllDay = true
        }

        if let isAllDay = isAllDay {
            optimisticTask.isAllDay = isAllDay
        }
        // Handle assigneeId: empty string means unassign, nil means don't update
        if let assigneeId = assigneeId {
            optimisticTask.assigneeId = assigneeId.isEmpty ? nil : assigneeId
        }
        if let repeating = repeating { optimisticTask.repeating = Task.Repeating(rawValue: repeating) }
        if let repeatingData = repeatingData { optimisticTask.repeatingData = repeatingData }
        if let repeatFrom = repeatFrom { optimisticTask.repeatFrom = Task.RepeatFromMode(rawValue: repeatFrom) }
        if let timerDuration = timerDuration { optimisticTask.timerDuration = timerDuration }
        if let lastTimerValue = lastTimerValue { optimisticTask.lastTimerValue = lastTimerValue }
        if let listIds = listIds { optimisticTask.listIds = listIds }

        // CRITICAL: Update updatedAt to current time for optimistic update
        // This ensures completed tasks immediately pass the "recently completed" filter
        // Without this, tasks disappear when completed and reappear when server responds
        optimisticTask.updatedAt = Date()

        // Update UI immediately
        cachedTasks[resolvedId] = optimisticTask
        if let index = tasks.firstIndex(where: { $0.id == resolvedId }) {
            tasks[index] = optimisticTask
        } else {
            // Add to tasks array if not already there (e.g., featured list tasks)
            tasks.append(optimisticTask)
            print("➕ [TaskService] Added task to tasks array: \(optimisticTask.title)")
        }
        print("⚡️ [TaskService] Optimistically updated task: \(optimisticTask.title)")

        // Save to CoreData with pending status for offline support (CRITICAL: await to ensure persistence)
        // This blocks until save completes, preventing data loss on force close
        do {
            try await saveTaskToCoreData(optimisticTask, syncStatus: "pending")
            print("✅ [TaskService] Persisted update to CoreData")
        } catch {
            print("⚠️ [TaskService] Failed to save to CoreData, but task is updated in memory: \(error)")
        }

        // Part B: Don't fire a doomed API call for temp tasks — the server
        // doesn't know this ID yet.  Edits are already saved in CoreData and
        // will be picked up when createTask() finishes or syncPendingOperations runs.
        if resolvedId.hasPrefix("temp_") {
            print("⏭️ [TaskService] Skipping API update for temp task \(resolvedId) — edits saved locally")
            updatePendingOperationsCount()
            return optimisticTask
        }

        // Make server call in background
        do {
            // Convert date/time to ISO8601 string for API
            // Backend expects:
            // - 'dueDateTime' = datetime (UTC midnight for all-day, specific time for timed)
            // - 'isAllDay' = boolean flag
            var dueDateTimeString: String?
            var isAllDayValue: Bool?

            // CRITICAL: Use UTC calendar for all-day task normalization
            var utcCalendar = Calendar.current
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!

            // Determine dueDateTime and isAllDay from either new or legacy parameters
            if let dueDateTime = dueDateTime {
                // New parameter path
                if dueDateTime == Date.distantPast {
                    // Clear due date
                    dueDateTimeString = ""
                    isAllDayValue = nil
                } else {
                    // Set due date (normalize to UTC midnight if all-day)
                    if let isAllDay = isAllDay, isAllDay {
                        let startOfDay = utcCalendar.startOfDay(for: dueDateTime)
                        dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)
                    } else {
                        dueDateTimeString = ISO8601DateFormatter().string(from: dueDateTime)
                    }
                    isAllDayValue = isAllDay
                }
            } else if let when = when, when == Date.distantPast,
                      let whenTime = whenTime, whenTime == Date.distantPast {
                // Legacy: Clear both date and time
                dueDateTimeString = ""
                isAllDayValue = nil
            } else if let when = when, when != Date.distantPast {
                // Legacy: Set date (all-day task)
                let startOfDay = utcCalendar.startOfDay(for: when)
                dueDateTimeString = ISO8601DateFormatter().string(from: startOfDay)

                // Check if time component is also being set
                if let whenTime = whenTime, whenTime != Date.distantPast {
                    // Time is set - timed task
                    dueDateTimeString = ISO8601DateFormatter().string(from: whenTime)
                    isAllDayValue = false
                } else if let whenTime = whenTime, whenTime == Date.distantPast {
                    // Explicitly clear time (all-day)
                    isAllDayValue = true
                } else {
                    // All-day by default
                    isAllDayValue = true
                }
            } else if let whenTime = whenTime, whenTime != Date.distantPast {
                // Legacy: Only time provided (timed task)
                dueDateTimeString = ISO8601DateFormatter().string(from: whenTime)
                isAllDayValue = false
            } else {
                // No date/time updates
                dueDateTimeString = nil
                isAllDayValue = nil
            }

            let updates = UpdateTaskRequest(
                title: title,
                description: description,
                priority: priority,
                repeating: repeating,
                repeatingData: repeatingData,
                repeatFrom: repeatFrom,
                isPrivate: nil,
                completed: completed,
                dueDateTime: dueDateTimeString,
                isAllDay: isAllDayValue,
                reminderTime: nil,
                reminderType: nil,
                listIds: listIds,
                assigneeId: assigneeId,
                timerDuration: timerDuration,
                lastTimerValue: lastTimerValue
            )

            // Unified Outbox dual-write (no-op unless OutboxConfig.dualWriteEnabled).
            // PUT is value-idempotent and carries no If-Unmodified-Since, so the
            // Outbox replaying the same body alongside the legacy PUT is safe.
            OutboxManager.shared.enqueueUpdateTask(
                UpdateTaskOutboxPayload(taskId: resolvedId, updates: updates),
                clientRequestId: UUID().uuidString
            )

            // CUTOVER (flag-gated): when the Outbox is authoritative, skip the
            // legacy inline PUT — the Outbox handler performs the update and marks
            // the row synced when it drains (online now, or on reconnect). The
            // optimistic in-memory/CoreData update already happened above.
            if OutboxConfig.sourceOfTruthEnabled {
                updatePendingOperationsCount()
                await badgeManager.updateBadge(with: self.tasks)
                return optimisticTask
            }

            let task = try await apiClient.updateTask(id: resolvedId, updates: updates)

            // Only replace in-memory if server response is newer than current version.
            // A concurrent edit may have written a newer optimistic version while our
            // API call was in flight — don't overwrite it.
            let currentLocal = cachedTasks[resolvedId]
            let localUpdated = currentLocal?.updatedAt ?? Date.distantPast
            let serverUpdated = task.updatedAt ?? Date.distantPast
            if serverUpdated >= localUpdated {
                cachedTasks[resolvedId] = task
                if let index = tasks.firstIndex(where: { $0.id == resolvedId }) {
                    tasks[index] = task
                } else {
                    tasks.append(task)
                }

                // Persist to CoreData
                do {
                    try await saveTaskToCoreData(task, syncStatus: "synced")
                } catch {
                    print("⚠️ [TaskService] Failed to update CoreData after task update: \(error)")
                }
            }

            print("✅ [TaskService] Server confirmed update: \(task.title)")

            // Handle notification updates
            if let completed = completed, completed {
                // Cancel notification if task is completed
                await notificationManager.cancelNotification(for: resolvedId)
            } else if when != nil || whenTime != nil || task.dueDateTime != nil {
                // Reschedule notification if date or time changed or still exists
                do {
                    try await notificationManager.rescheduleNotification(for: task)
                } catch {
                    print("⚠️ [TaskService] Failed to reschedule notification: \(error)")
                }
            }

            updatePendingOperationsCount()

            // Update app badge after task update
            await badgeManager.updateBadge(with: self.tasks)

            return task
        } catch {
            // DON'T ROLLBACK: Keep task as "pending" for offline support
            print("⚠️ [TaskService] Failed to sync update to server, keeping as pending: \(error)")
            updatePendingOperationsCount()

            // Update badge even for pending updates
            await badgeManager.updateBadge(with: self.tasks)

            // Return the optimistic task so UI shows it
            return optimisticTask
        }
    }

    /// Server-first update for callers that cannot use the normal optimistic
    /// flow because the view hierarchy is sensitive to intermediate state
    /// changes. This keeps those exceptional paths inside TaskService instead
    /// of letting views call AstridAPIClient directly.
    func updateTaskOnServer(
        taskId: String,
        updates: UpdateTaskRequest
    ) async throws -> Task {
        let resolvedId = tempTaskIdMapping[taskId] ?? taskId
        guard !resolvedId.hasPrefix("temp_") else {
            throw NSError(
                domain: "TaskService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Cannot server-update a task before its temp ID is synced"]
            )
        }

        let updatedTask = try await apiClient.updateTask(id: resolvedId, updates: updates)
        updateTaskInCache(updatedTask)

        do {
            try await saveTaskToCoreData(updatedTask, syncStatus: "synced")
        } catch {
            print("⚠️ [TaskService] Failed to persist server-first update: \(error)")
        }

        await badgeManager.updateBadge(with: self.tasks)
        return updatedTask
    }

    /// Fetch tasks for a list through the v1 TaskService boundary. Used by
    /// featured/public list views that need a network snapshot without
    /// reaching into AstridAPIClient from SwiftUI.
    func fetchTasksForListFromServer(_ listId: String) async throws -> [Task] {
        try await apiClient.getAllTasks(listId: listId)
    }

    func completeTask(id: String, completed: Bool, task: Task? = nil, timerDuration: Int? = nil, lastTimerValue: String? = nil) async throws -> Task {
        // Get the current task - prefer the passed task (what user sees on screen) over cache
        // The cache might be stale if the task was updated on web
        guard let currentTask = task ?? cachedTasks[id] ?? tasks.first(where: { $0.id == id }) else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        // Handle repeating task roll-forward locally (offline support)
        // Only process when marking as complete (not un-complete) and task is repeating
        if completed && !currentTask.completed,
           let repeating = currentTask.repeating,
           repeating != .never {

            print("🔄 [TaskService] Rolling forward repeating task: \(currentTask.title)")
            print("  - Current dueDateTime: \(currentTask.dueDateTime?.description ?? "nil")")
            print("  - repeatFrom: \(currentTask.repeatFrom?.rawValue ?? "nil")")

            // Calculate next due date
            let (nextDueDate, shouldTerminate) = calculateNextOccurrence(for: currentTask)

            if shouldTerminate {
                print("🏁 [TaskService] Repeating series terminated")
                // Series ended - keep completed, clear repeating
                return try await updateTask(
                    taskId: id,
                    completed: true,
                    repeating: "never",
                    repeatingData: nil,
                    timerDuration: timerDuration,
                    lastTimerValue: lastTimerValue,
                    task: task
                )
            } else if let nextDue = nextDueDate {
                print("📅 [TaskService] Next occurrence: \(nextDue)")
                return try await updateTask(
                    taskId: id,
                    completed: false,
                    dueDateTime: nextDue,
                    isAllDay: currentTask.isAllDay,
                    timerDuration: timerDuration,
                    lastTimerValue: lastTimerValue,
                    task: task
                )
            }
        }

        // Non-repeating task or un-completing - use normal update
        return try await updateTask(taskId: id, completed: completed, timerDuration: timerDuration, lastTimerValue: lastTimerValue, task: task)
    }

    /// Calculate the next occurrence date for a repeating task.
    ///
    /// Delegates to `RepeatingTaskCalculator`, which is the canonical
    /// implementation shared with `astrid-web` and exercised by
    /// `RepeatingTaskCalculatorTests` and `CustomRepeatingPatternTests`.
    /// Do NOT reintroduce pattern logic here — it caused a regression where
    /// weekly patterns with selected weekdays jumped a full week instead of
    /// picking the next selected weekday.
    ///
    /// Marked `internal` so tests can lock down the completion path.
    func calculateNextOccurrence(for task: Task) -> (nextDate: Date?, shouldTerminate: Bool) {
        let currentDueDate = task.dueDateTime
        let repeatFrom = task.repeatFrom ?? .COMPLETION_DATE
        let currentOccurrenceCount = task.occurrenceCount ?? 0

        // For all-day tasks in COMPLETION_DATE mode, normalize completion to
        // the user's LOCAL date at UTC midnight (how all-day tasks are stored).
        // This matches the web's `localCompletionDate` behavior: completing at
        // 9pm PST (= 5am UTC next day) should anchor to the local date, not the
        // UTC date that crossed midnight.
        let completionDate = effectiveCompletionDate(for: task, repeatFrom: repeatFrom)

        // Custom patterns: weekdays, monthly same_date/same_weekday, yearly
        if task.repeating == .custom, let pattern = task.repeatingData {
            let result = RepeatingTaskCalculator.calculateCustomNextOccurrence(
                pattern: pattern,
                currentDueDate: currentDueDate,
                completionDate: completionDate,
                repeatFrom: repeatFrom,
                currentOccurrenceCount: currentOccurrenceCount
            )
            return (result.nextDueDate, result.shouldTerminate)
        }

        // Simple patterns with optional end conditions piggybacked on repeatingData
        guard let repeating = task.repeating, repeating != .never else {
            return (nil, false)
        }
        var endData: SimplePatternEndCondition? = nil
        if let pattern = task.repeatingData, let endCondition = pattern.endCondition {
            endData = SimplePatternEndCondition(
                endCondition: endCondition,
                endAfterOccurrences: pattern.endAfterOccurrences,
                endUntilDate: pattern.endUntilDate
            )
        }
        let result = RepeatingTaskCalculator.calculateSimpleNextOccurrence(
            repeatingType: repeating,
            currentDueDate: currentDueDate,
            completionDate: completionDate,
            repeatFrom: repeatFrom,
            currentOccurrenceCount: currentOccurrenceCount,
            endData: endData
        )
        return (result.nextDueDate, result.shouldTerminate)
    }

    /// Adjust completion date for all-day + COMPLETION_DATE mode so the
    /// anchor is the user's local date (stored as UTC midnight). Timed tasks
    /// and DUE_DATE mode pass through unchanged.
    private func effectiveCompletionDate(for task: Task, repeatFrom: Task.RepeatFromMode) -> Date {
        let now = Date()
        guard task.isAllDay, repeatFrom == .COMPLETION_DATE else { return now }

        let localComponents = Calendar.current.dateComponents([.year, .month, .day], from: now)
        var utcComponents = DateComponents()
        utcComponents.year = localComponents.year
        utcComponents.month = localComponents.month
        utcComponents.day = localComponents.day
        utcComponents.hour = 0
        utcComponents.minute = 0
        utcComponents.second = 0
        utcComponents.timeZone = TimeZone(identifier: "UTC")
        var utcCalendar = Calendar.current
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
        return utcCalendar.date(from: utcComponents) ?? now
    }

    func updateTaskLists(taskId: String, listIds: [String]) async throws -> Task {
        return try await updateTask(taskId: taskId, listIds: listIds)
    }

    func deleteTask(id: String, task: Task? = nil) async throws {
        // Resolve stale temp ID → real server ID (same reason as updateTask)
        let resolvedId = tempTaskIdMapping[id] ?? id

        // OPTIMISTIC UPDATE: Store task for potential recovery
        // Check cache first, then provided task parameter (for featured/public list tasks)
        guard let deletedTask = cachedTasks[resolvedId] ?? tasks.first(where: { $0.id == resolvedId }) ?? task else {
            throw NSError(domain: "TaskService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Task not found"])
        }

        // Remove from UI immediately and track for sync filtering
        cachedTasks.removeValue(forKey: resolvedId)
        tasks.removeAll { $0.id == resolvedId }
        recentlyDeletedIds.insert(resolvedId)
        print("⚡️ [TaskService] Optimistically deleted task: \(deletedTask.title)")

        // Mark as deleted in CoreData for offline support (CRITICAL: await to ensure persistence)
        // This blocks until save completes, preventing data loss on force close
        do {
            var deletedTaskCopy = deletedTask
            deletedTaskCopy.completed = true  // Mark as completed for now
            try await saveTaskToCoreData(deletedTaskCopy, syncStatus: "pending_delete")
            print("✅ [TaskService] Persisted deletion to CoreData")
        } catch {
            print("⚠️ [TaskService] Failed to save deletion to CoreData, but task is removed from memory: \(error)")
        }

        // Cancel notification
        await notificationManager.cancelNotification(for: resolvedId)

        // Update app badge after task deletion
        await badgeManager.updateBadge(with: self.tasks)

        // Make server call in background
        do {
            do {
                try await apiClient.deleteTask(id: resolvedId)
                print("✅ [TaskService] Server confirmed deletion: \(resolvedId)")
            } catch {
                // 404/410 means already deleted on server — treat as success
                let nsError = error as NSError
                let isAlreadyDeleted = nsError.code == 404 || nsError.code == 410
                    || "\(error)".contains("404") || "\(error)".contains("not found")
                if isAlreadyDeleted {
                    print("✅ [TaskService] Task already deleted on server: \(resolvedId)")
                } else {
                    throw error
                }
            }

            // Remove from CoreData after successful deletion (CRITICAL: await to ensure persistence)
            do {
                try await deleteTaskFromCoreData(resolvedId)
                updatePendingOperationsCount()
                print("✅ [TaskService] Removed from CoreData after successful deletion")
            } catch {
                print("⚠️ [TaskService] Failed to remove from CoreData after deletion: \(error)")
            }
        } catch {
            // DON'T ROLLBACK: Keep task as "pending_delete" for offline support
            print("⚠️ [TaskService] Failed to sync deletion to server, keeping as pending: \(error)")
            updatePendingOperationsCount()
            // Badge already updated above after optimistic delete
            // Don't re-add to UI, let it stay deleted locally
        }
    }

    func copyTask(
        id: String,
        targetListId: String?,
        includeComments: Bool = false,
        preserveDueDate: Bool = false,
        preserveAssignee: Bool = false
    ) async throws -> Task {
        // Fetch the original task
        print("📋 [TaskService] Fetching original task to copy: \(id)")
        let originalTask = try await fetchTask(id: id)

        // Determine target list IDs
        // Allow empty listIds for "My Tasks (only)" - tasks without lists are valid
        let listIds: [String]
        if let targetListId = targetListId, !targetListId.isEmpty {
            // Specific list selected
            listIds = [targetListId]
        } else if targetListId == nil || targetListId == "" {
            // "My Tasks (only)" selected - use empty array (no lists)
            listIds = []
        } else if let originalListIds = originalTask.listIds, !originalListIds.isEmpty {
            // Fallback: Use original list IDs if available
            listIds = originalListIds
        } else {
            // Default: No lists (My Tasks only)
            listIds = []
        }

        // Determine assignee for copied task
        // When copying to a list: make task unassigned
        // When copying to "My Tasks (only)" (no lists): assign to current user
        let copyAssigneeId: String?
        if listIds.isEmpty {
            // "My Tasks (only)" - always assign to current user so it appears in My Tasks
            copyAssigneeId = AuthManager.shared.userId
            print("📋 [TaskService] Copying to My Tasks (only) - assigning to current user")
        } else {
            // Copying to a list - make task unassigned
            copyAssigneeId = nil
            print("📋 [TaskService] Copying to list - making task unassigned")
        }

        // Copy the task using createTask (no [copy] suffix, just copy as-is)
        print("📋 [TaskService] Creating copy of task in list(s): \(listIds)")
        let copiedTask = try await createTask(
            listIds: listIds,
            title: originalTask.title,
            description: originalTask.description,
            priority: originalTask.priority.rawValue,
            whenDate: preserveDueDate ? (originalTask.isAllDay ? originalTask.dueDateTime : nil) : nil,
            whenTime: preserveDueDate ? (!originalTask.isAllDay ? originalTask.dueDateTime : nil) : nil,
            assigneeId: copyAssigneeId,
            isPrivate: originalTask.isPrivate,
            repeating: originalTask.repeating?.rawValue
        )

        print("✅ [TaskService] Task copied successfully: \(copiedTask.title)")

        // Copy comments if requested
        if includeComments {
            do {
                // Fetch comments from the original task
                print("📋 [TaskService] Fetching comments for task: \(id)")
                let comments = try await CommentService.shared.fetchComments(taskId: id)

                if !comments.isEmpty {
                    // Filter out system comments (authorId is nil)
                    let userComments = comments.filter { $0.authorId != nil }

                    if !userComments.isEmpty {
                        print("📋 [TaskService] Copying \(userComments.count) user comments...")

                        for comment in userComments {
                            do {
                                // Preserve the original comment author when copying
                                _ = try await CommentService.shared.createComment(
                                    taskId: copiedTask.id,
                                    content: comment.content,
                                    type: comment.type,
                                    authorId: comment.authorId
                                )
                            } catch {
                                print("⚠️ [TaskService] Failed to copy comment: \(error) ")
                                // Continue copying other comments even if one fails
                            }
                        }

                        print("✅ [TaskService] Comments copied")
                    } else {
                        print("ℹ️ [TaskService] No user comments to copy")
                    }
                } else {
                    print("ℹ️ [TaskService] No comments to copy")
                }
            } catch {
                print("⚠️ [TaskService] Failed to fetch comments for copying: \(error)")
                // Don't fail the entire copy operation if comment copying fails
            }
        }

        return copiedTask
    }

    // MARK: - Filtering

    func getTasksForList(_ listId: String) -> [Task] {
        return tasks.filter { task in
            task.listIds?.contains(listId) == true ||
            task.lists?.contains(where: { $0.id == listId }) == true
        }
    }

    func getCompletedTasks() -> [Task] {
        return tasks.filter { $0.completed }
    }

    func getIncompleteTasks() -> [Task] {
        return tasks.filter { !$0.completed }
    }

    // MARK: - CoreData Persistence

    /// Save multiple tasks to CoreData with optimized batch operations
    private func saveTasksToCoreData(_ tasks: [Task]) async throws {
        print("💾 [TaskService] Saving \(tasks.count) tasks to Core Data...")

        try await coreDataManager.saveInBackground { context in
            // Fetch all existing tasks in ONE batch query instead of 394 individual queries
            let taskIds = tasks.map { $0.id }
            let fetchRequest = CDTask.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", taskIds)
            let existingTasks = try context.fetch(fetchRequest)

            // Create dictionary for O(1) lookup
            var existingTasksDict = [String: CDTask]()
            for cdTask in existingTasks {
                existingTasksDict[cdTask.id] = cdTask
            }

            print("💾 [TaskService] Found \(existingTasks.count) existing tasks, creating \(tasks.count - existingTasks.count) new tasks")

            // Update or create tasks
            for task in tasks {
                let cdTask = existingTasksDict[task.id] ?? CDTask(context: context)
                let existingStatus = existingTasksDict[task.id]?.syncStatus

                // Don't overwrite tasks with pending local operations — those edits
                // need to be pushed to the server first via syncPendingOperations()
                if existingStatus == "pending" || existingStatus == "pending_delete" || existingStatus == "pending_list_sync" {
                    continue
                }

                cdTask.id = task.id
                cdTask.update(from: task)
                cdTask.syncStatus = "synced"
                cdTask.lastSyncedAt = Date()
            }

            // Clean up orphaned CDTasks: tasks the server no longer returns
            // Delete "synced" tasks AND "pending_delete" tasks not on server
            // (pending_delete tasks not on server = already deleted server-side, safe to clean up)
            // Preserve "pending" and "pending_list_sync" (local edits not yet pushed)
            let serverIds = Set(tasks.map { $0.id })
            let orphanRequest = CDTask.fetchRequest()
            orphanRequest.predicate = NSPredicate(
                format: "NOT (id IN %@) AND (syncStatus == %@ OR syncStatus == %@)",
                Array(serverIds), "synced", "pending_delete"
            )
            let orphanedTasks = try context.fetch(orphanRequest)
            if !orphanedTasks.isEmpty {
                for orphan in orphanedTasks {
                    context.delete(orphan)
                }
                print("🧹 [TaskService] Removed \(orphanedTasks.count) orphaned tasks from CoreData")
            }

            print("💾 [TaskService] Core Data save completed")
        }

        print("✅ [TaskService] Successfully saved \(tasks.count) tasks to Core Data")
    }

    /// Save single task to CoreData with sync status
    private func saveTaskToCoreData(_ task: Task, syncStatus: String) async throws {
        try await coreDataManager.saveInBackground { context in
            let cdTask = try CDTask.fetchById(task.id, context: context) ?? CDTask(context: context)
            cdTask.id = task.id
            cdTask.update(from: task)
            cdTask.syncStatus = syncStatus
            if syncStatus == "synced" {
                cdTask.lastSyncedAt = Date()
            }
        }
    }

    /// Delete task from CoreData
    private func deleteTaskFromCoreData(_ id: String) async throws {
        try await coreDataManager.saveInBackground { context in
            if let cdTask = try CDTask.fetchById(id, context: context) {
                context.delete(cdTask)
            }
        }
    }

    /// Update pending operations count
    private func updatePendingOperationsCount() {
        do {
            let context = coreDataManager.viewContext
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@ OR syncStatus == %@", "pending", "pending_delete")
            let count = try context.count(for: request)
            pendingOperationsCount = count
            print("📊 [TaskService] Pending operations: \(count)")

            // Also update failed count
            updateFailedOperationsCount()
        } catch {
            print("❌ [TaskService] Failed to count pending operations: \(error)")
        }
    }

    /// Update failed operations count
    private func updateFailedOperationsCount() {
        do {
            let context = coreDataManager.viewContext
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@", "failed")
            let count = try context.count(for: request)
            failedOperationsCount = count
        } catch {
            print("❌ [TaskService] Failed to count failed operations: \(error)")
        }
    }

    /// Get IDs of tasks that are pending deletion locally (not yet confirmed by server)
    private func getPendingDeleteIds() -> Set<String> {
        do {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@", "pending_delete")
            let cdTasks = try coreDataManager.viewContext.fetch(request)
            return Set(cdTasks.map { $0.id })
        } catch {
            print("⚠️ [TaskService] Failed to fetch pending delete IDs: \(error)")
            return []
        }
    }

    /// Get IDs of tasks with pending local edits (non-temp, non-delete)
    private func getPendingEditIds() -> Set<String> {
        do {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(
                format: "(syncStatus == %@ OR syncStatus == %@) AND NOT (id BEGINSWITH %@)",
                "pending", "pending_list_sync", "temp_"
            )
            let cdTasks = try coreDataManager.viewContext.fetch(request)
            return Set(cdTasks.map { $0.id })
        } catch {
            print("⚠️ [TaskService] Failed to fetch pending edit IDs: \(error)")
            return []
        }
    }

    /// Retry all failed operations
    func retryFailedOperations() async {
        print("🔄 [TaskService] Retrying failed operations...")

        do {
            try await coreDataManager.saveInBackground { context in
                let failedTasks = try CDTask.fetchFailedTasks(context: context)
                for task in failedTasks {
                    task.syncAttempts = 0
                    task.syncStatus = "pending"
                    task.lastSyncError = nil
                }
                print("📊 [TaskService] Reset \(failedTasks.count) failed tasks to pending")
            }

            // Trigger sync
            try await syncPendingOperations()
        } catch {
            print("❌ [TaskService] Failed to retry operations: \(error)")
        }
    }

    // MARK: - Cache Management

    /// Clear all in-memory task data (used on logout)
    func clearCache() {
        tasks = []
        cachedTasks = [:]
        recentlyDeletedIds = []
        pendingOperationsCount = 0
        print("🗑️ [TaskService] In-memory task cache cleared")
    }

    /// Update a single task in the cache (used when bypassing normal update flow)
    func updateTaskInCache(_ task: Task) {
        cachedTasks[task.id] = task
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
        }
        print("📝 [TaskService] Updated task in cache: \(task.title)")
    }

    /// Update tasks from sync manager (used by list-based sync)
    /// Awaitable — callers MUST await this to ensure data is fully committed
    /// before continuing with other sync operations.
    func updateTasksFromSync(_ newTasks: [Task]) async {
        // Use ALL current in-memory tasks for merge (not just "pending" ones).
        // The merge uses timestamp comparison to decide: if local is newer, keep it.
        // This is resilient to syncPendingOperations marking edits as "synced" before
        // the server fetch returns — stale server data can't overwrite newer local data.
        let localTasks = self.tasks

        // Filter out tasks deleted locally. Use BOTH CoreData pending_delete records
        // AND the in-memory recentlyDeletedIds set (survives CoreData cleanup by syncPendingOps).
        let pendingDeleteIds = getPendingDeleteIds().union(recentlyDeletedIds)
        let filteredNewTasks = pendingDeleteIds.isEmpty ? newTasks : newTasks.filter { !pendingDeleteIds.contains($0.id) }

        // Merge and sort (background CPU work, awaited)
        let sortedTasks = await Self.mergeAndSortTasksInBackground(
            newTasks: filteredNewTasks,
            pendingTasks: localTasks
        )

        // Only clear recentlyDeletedIds for tasks whose delete has actually been confirmed
        // (no longer pending in CoreData). Keep IDs that are still pending_delete — they haven't
        // been deleted from the server yet and must remain filtered on subsequent syncs.
        let stillPendingDeleteIds = getPendingDeleteIds()
        recentlyDeletedIds = recentlyDeletedIds.intersection(stillPendingDeleteIds)

        // Update UI on main actor
        self.tasks = sortedTasks
        self.cachedTasks = Dictionary(uniqueKeysWithValues: sortedTasks.map { ($0.id, $0) })
        print("✅ [TaskService] Updated \(self.tasks.count) tasks from sync")

        // Update app badge
        await self.badgeManager.updateBadge(with: self.tasks)

        // Save to CoreData (awaited — no detached fire-and-forget)
        do {
            let tasksToSave = self.tasks.filter { !$0.id.hasPrefix("temp_") }
            try await self.saveTasksToCoreData(tasksToSave)
            print("✅ [TaskService] Saved \(tasksToSave.count) synced tasks to CoreData for offline use")
        } catch {
            print("⚠️ [TaskService] Failed to save synced tasks to CoreData: \(error)")
        }
    }

    /// Merge and sort tasks in background to avoid blocking main thread
    static nonisolated func mergeAndSortTasksInBackground(
        newTasks: [Task],
        pendingTasks: [Task]
    ) async -> [Task] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Merge server tasks with pending tasks using dictionary
                var mergedDict: [String: Task] = [:]
                for task in newTasks {
                    mergedDict[task.id] = task
                }

                // Only keep pending tasks that DON'T already have a server counterpart.
                // Primary match: clientRequestId (survives title edits during create flight).
                // Fallback match: same title + listIds + createdAt within 60 seconds.
                let deduplicationWindow: TimeInterval = 60

                for task in pendingTasks {
                    // Non-temp tasks: compare timestamps to decide local vs server.
                    // If local is newer → keep local (edit not yet reflected on server).
                    // If server is newer or same → keep server (server has latest data).
                    // This is resilient to syncPendingOperations marking edits as "synced"
                    // before the server fetch returns stale data.
                    if !task.id.hasPrefix("temp_") {
                        if let serverVersion = mergedDict[task.id] {
                            let localUpdated = task.updatedAt ?? Date.distantPast
                            let serverUpdated = serverVersion.updatedAt ?? Date.distantPast
                            if localUpdated > serverUpdated {
                                mergedDict[task.id] = task
                            }
                        }
                        // If task not on server (deleted remotely), don't re-add it
                        continue
                    }

                    // Primary: match by clientRequestId (robust even when title is edited)
                    if let pendingCRID = task.clientRequestId, !pendingCRID.isEmpty {
                        if let matchingServer = newTasks.first(where: { $0.clientRequestId == pendingCRID }) {
                            // Server confirmed this task — overlay local edits if newer
                            let localUpdated = task.updatedAt ?? Date.distantPast
                            let serverUpdated = matchingServer.updatedAt ?? Date.distantPast
                            if localUpdated > serverUpdated {
                                // Local has edits the server doesn't know about yet — preserve them
                                var merged = matchingServer
                                merged.title = task.title
                                merged.description = task.description
                                merged.priority = task.priority
                                merged.dueDateTime = task.dueDateTime
                                merged.isAllDay = task.isAllDay
                                merged.assigneeId = task.assigneeId
                                merged.repeating = task.repeating
                                merged.repeatingData = task.repeatingData
                                merged.completed = task.completed
                                merged.isPrivate = task.isPrivate
                                if let editedListIds = task.listIds {
                                    merged.listIds = editedListIds
                                }
                                mergedDict[matchingServer.id] = merged
                            }
                            // Either way, don't also add the temp_ version
                            continue
                        }
                    }

                    // Fallback: title + listIds + createdAt window (for tasks without clientRequestId)
                    let pendingTitle = task.title.lowercased()
                    let pendingLists = Set(task.listIds ?? [])
                    let pendingDate = task.createdAt ?? Date()

                    let hasServerMatch = newTasks.first { serverTask in
                        guard serverTask.title.lowercased() == pendingTitle else { return false }
                        let serverLists = Set(serverTask.listIds ?? [])
                        guard !pendingLists.isEmpty && !pendingLists.isDisjoint(with: serverLists) else { return false }
                        let serverDate = serverTask.createdAt ?? Date()
                        return abs(pendingDate.timeIntervalSince(serverDate)) < deduplicationWindow
                    }

                    if let matchingServer = hasServerMatch {
                        // Server confirmed this task — overlay local edits if newer
                        let localUpdated = task.updatedAt ?? Date.distantPast
                        let serverUpdated = matchingServer.updatedAt ?? Date.distantPast
                        if localUpdated > serverUpdated {
                            var merged = matchingServer
                            merged.title = task.title
                            merged.description = task.description
                            merged.priority = task.priority
                            merged.dueDateTime = task.dueDateTime
                            merged.isAllDay = task.isAllDay
                            merged.assigneeId = task.assigneeId
                            merged.repeating = task.repeating
                            merged.repeatingData = task.repeatingData
                            merged.completed = task.completed
                            merged.isPrivate = task.isPrivate
                            if let editedListIds = task.listIds {
                                merged.listIds = editedListIds
                            }
                            mergedDict[matchingServer.id] = merged
                        }
                        continue
                    }
                    mergedDict[task.id] = task // Truly pending, keep it
                }

                // Sort by due date, then by creation date
                let sorted = Array(mergedDict.values).sorted { task1, task2 in
                    if let date1 = task1.dueDateTime, let date2 = task2.dueDateTime {
                        return date1 < date2
                    }
                    if task1.dueDateTime != nil {
                        return true
                    }
                    if task2.dueDateTime != nil {
                        return false
                    }
                    return (task1.createdAt ?? Date()) > (task2.createdAt ?? Date())
                }

                continuation.resume(returning: sorted)
            }
        }
    }

    // MARK: - Offline Sync

    /// Sync all pending operations to server
    func syncPendingOperations() async throws {
        guard !isSyncingPendingOperations else {
            print("⏳ [TaskService] Sync already in progress")
            return
        }

        isSyncingPendingOperations = true
        defer { isSyncingPendingOperations = false }

        print("🔄 [TaskService] Starting sync of pending operations...")
        print("📊 [TaskService] Before sync: \(tasks.count) tasks in memory, \(cachedTasks.count) in cache")

        let context = coreDataManager.viewContext

        // Fetch pending tasks (excludes "failed" — those are permanently abandoned)
        let request = CDTask.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@ OR syncStatus == %@", "pending", "pending_delete")
        let pendingTasks = try context.fetch(request)

        print("📤 [TaskService] Found \(pendingTasks.count) pending operations")

        var syncedCount = 0
        var failedCount = 0

        for cdTask in pendingTasks {
            // Skip tasks that have an in-flight createTask() call — Part A guard
            if pendingCreates.contains(cdTask.id) {
                print("⏭️ [TaskService] Skipping \(cdTask.id) — createTask() in flight")
                continue
            }

            do {
                if cdTask.syncStatus == "pending_delete"
                    || (cdTask.syncStatus == "failed" && recentlyDeletedIds.contains(cdTask.id)) {
                    // Handle pending deletions (including legacy "failed" records that were deletes)
                    do {
                        try await apiClient.deleteTask(id: cdTask.id)
                    } catch {
                        // If server returns 404/410, the task is already gone — that's success
                        let nsError = error as NSError
                        let isAlreadyDeleted = nsError.code == 404 || nsError.code == 410
                            || "\(error)".contains("404") || "\(error)".contains("not found")
                        if !isAlreadyDeleted {
                            throw error  // Real error — let outer catch handle it
                        }
                        print("✅ [TaskService] Task already deleted on server: \(cdTask.id)")
                    }
                    try await deleteTaskFromCoreData(cdTask.id)
                    print("✅ [TaskService] Synced deletion: \(cdTask.id)")
                } else {
                    // Handle pending creates/updates
                    let task = cdTask.toDomainModel()

                    // Check if task exists on server by attempting update first
                    // If it fails with 404, create it instead
                    do {
                        // Convert dueDateTime to ISO8601 string for API
                        let dueDateTimeString: String? = task.dueDateTime.map { date in
                            ISO8601DateFormatter().string(from: date)
                        }

                        let updates = Self.makeSyncUpdateRequest(
                            task: task,
                            dueDateTimeString: dueDateTimeString,
                            listIds: task.listIds
                        )

                        let updatedTask = try await apiClient.updateTask(id: task.id, updates: updates)

                        // Update with server response
                        try await saveTaskToCoreData(updatedTask, syncStatus: "synced")

                        // Only replace in-memory if server response is newer than current version.
                        // A concurrent updateTask() call may have written a newer optimistic version
                        // while our API call was in flight — don't overwrite it.
                        let currentLocal = cachedTasks[updatedTask.id]
                        let localUpdated = currentLocal?.updatedAt ?? Date.distantPast
                        let serverUpdated = updatedTask.updatedAt ?? Date.distantPast
                        if serverUpdated >= localUpdated {
                            cachedTasks[updatedTask.id] = updatedTask
                            if let index = tasks.firstIndex(where: { $0.id == updatedTask.id }) {
                                tasks[index] = updatedTask
                            } else {
                                tasks.insert(updatedTask, at: 0)
                            }
                        }

                        print("✅ [TaskService] Synced update: \(updatedTask.title)")
                    } catch {
                        // If update failed (likely 404), try creating instead
                        if task.id.hasPrefix("temp_") {
                            // CRITICAL: Filter out temp_ list IDs and resolve any mapped IDs
                            let resolvedListIds = resolveListIds(task.listIds ?? [])
                            let serverListIds = resolvedListIds.filter { !$0.hasPrefix("temp_") }

                            // Read stored clientRequestId from CoreData for idempotent retry
                            let storedClientRequestId = cdTask.clientRequestId

                            var createdTask = try await apiClient.createTask(
                                title: task.title,
                                listIds: serverListIds.isEmpty ? nil : serverListIds,  // Filter temp_ IDs
                                description: task.description.isEmpty ? nil : task.description,
                                priority: task.priority.rawValue,
                                assigneeId: task.assigneeId,
                                dueDateTime: task.dueDateTime,
                                isAllDay: task.isAllDay,
                                isPrivate: task.isPrivate,
                                repeating: task.repeating?.rawValue,
                                repeatingData: task.repeatingData,  // Don't drop custom recurrence on offline replay
                                clientRequestId: storedClientRequestId  // Reuse same key for dedup
                            )

                            // CRITICAL: If server returned an idempotent response (task already existed),
                            // it may have stale data (e.g. missing priority/date/recurrence edits the user
                            // made locally). Compare and push an UPDATE if they differ.
                            let localDiffersFromServer = Self.taskDiffersForSync(local: task, server: createdTask)

                            if localDiffersFromServer {
                                print("🔀 [TaskService] Local edits differ from server response — pushing UPDATE")
                                let syncDueDateTimeString: String? = task.dueDateTime.map { date in
                                    if task.isAllDay {
                                        var utcCalendar = Calendar.current
                                        utcCalendar.timeZone = TimeZone(identifier: "UTC")!
                                        let startOfDay = utcCalendar.startOfDay(for: date)
                                        return ISO8601DateFormatter().string(from: startOfDay)
                                    } else {
                                        return ISO8601DateFormatter().string(from: date)
                                    }
                                }
                                let syncUpdates = Self.makeSyncUpdateRequest(
                                    task: task,
                                    dueDateTimeString: syncDueDateTimeString,
                                    listIds: serverListIds.isEmpty ? nil : serverListIds
                                )
                                let updatedFromServer = try await apiClient.updateTask(id: createdTask.id, updates: syncUpdates)
                                createdTask = updatedFromServer
                                print("✅ [TaskService] Pushed local edits to server for task \(createdTask.id)")
                            }

                            // Replace temp task with server task
                            try await deleteTaskFromCoreData(task.id)
                            try await saveTaskToCoreData(createdTask, syncStatus: "synced")

                            // Update in-memory arrays
                            cachedTasks.removeValue(forKey: task.id)
                            cachedTasks[createdTask.id] = createdTask
                            if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                                tasks[index] = createdTask
                            }

                            // Record temp→real so pending children created offline
                            // (e.g. a photo-comment) can re-target the real task on
                            // sync instead of 404'ing against the temp id and being
                            // dropped.
                            recordTempTaskMapping(tempId: task.id, realId: createdTask.id)

                            print("✅ [TaskService] Synced creation: \(createdTask.title)")
                        } else {
                            throw error
                        }
                    }
                }

                syncedCount += 1
            } catch {
                print("❌ [TaskService] Failed to sync task \(cdTask.id): \(error)")
                failedCount += 1

                // Detect permanent HTTP errors (403/404/410) — no point retrying these
                let isPermanent: Bool
                if case APIError.httpError(let code, _) = error, [403, 404, 410].contains(code) {
                    isPermanent = true
                } else if case AstridAPIError.httpError(let code, _) = error, [403, 404, 410].contains(code) {
                    isPermanent = true
                } else {
                    isPermanent = false
                }

                if cdTask.syncStatus == "pending_delete" {
                    // pending_delete must NOT become "failed" — that breaks delete filtering
                    // and lets deleted tasks reappear. Will retry on next sync cycle.
                } else if isPermanent {
                    cdTask.syncStatus = "failed"
                    cdTask.syncAttempts = CDTask.maxSyncAttempts
                    cdTask.lastSyncError = "\(error)"
                    print("🚫 [TaskService] Permanently failed task \(cdTask.id) — will not retry")
                } else {
                    cdTask.recordSyncFailure(error: "\(error)")
                }
            }
        }

        updatePendingOperationsCount()
        print("✅ [TaskService] Sync complete: \(syncedCount) synced, \(failedCount) failed")
        print("📊 [TaskService] After sync: \(tasks.count) tasks in memory, \(cachedTasks.count) in cache")

        // NOTE: Don't call fetchAllTasks() here - sync loop already updated in-memory tasks
        // Calling fetchAllTasks() would replace local tasks with server tasks and could lose data
    }

    // MARK: - Temp List ID Resolution

    /// Called by ListService when a temp list ID gets its real server ID
    /// Updates all tasks that reference the temp ID to use the real ID
    func onListSynced(tempListId: String, realListId: String) async {
        print("🔄 [TaskService] List synced: \(tempListId) → \(realListId)")

        // Store the mapping for future reference
        tempListIdMapping[tempListId] = realListId

        // Find all tasks that have the temp list ID
        var tasksToUpdate: [Task] = []
        for task in tasks {
            if let listIds = task.listIds, listIds.contains(tempListId) {
                tasksToUpdate.append(task)
            }
        }

        if tasksToUpdate.isEmpty {
            print("ℹ️ [TaskService] No tasks found with temp list ID: \(tempListId)")
            return
        }

        print("📝 [TaskService] Found \(tasksToUpdate.count) tasks to update with new list ID")

        // Update each task
        for task in tasksToUpdate {
            // Replace temp ID with real ID in listIds
            var updatedListIds = task.listIds ?? []
            updatedListIds = updatedListIds.map { $0 == tempListId ? realListId : $0 }

            // Remove any duplicates (in case real ID was already there)
            updatedListIds = Array(Set(updatedListIds))

            do {
                // Update task on server with new list ID
                let updatedTask = try await updateTask(taskId: task.id, listIds: updatedListIds)
                print("✅ [TaskService] Updated task '\(updatedTask.title)' with real list ID")
            } catch {
                print("⚠️ [TaskService] Failed to update task '\(task.title)' with real list ID: \(error)")
                // Task stays with the updated local listIds, will retry on next sync
            }
        }
    }

    /// Compare two optional dates, treating them as equal if within 1 second
    /// (handles minor serialization/timezone rounding differences)
    nonisolated static func datesMatch(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case (nil, _), (_, nil): return false
        case let (a?, b?): return abs(a.timeIntervalSince(b)) < 1.0
        }
    }

    /// Builds the wire payload for replaying an offline task edit. Centralized so
    /// recurrence fields (repeating/repeatingData/repeatFrom) are ALWAYS carried —
    /// a prior inline version sent repeatingData: nil and erased custom patterns
    /// after offline replay.
    nonisolated static func makeSyncUpdateRequest(task: Task, dueDateTimeString: String?, listIds: [String]?) -> UpdateTaskRequest {
        UpdateTaskRequest(
            title: task.title,
            description: task.description,
            priority: task.priority.rawValue,
            repeating: task.repeating?.rawValue,
            repeatingData: task.repeatingData,
            repeatFrom: task.repeatFrom?.rawValue,
            isPrivate: task.isPrivate,
            completed: task.completed,
            dueDateTime: dueDateTimeString,
            isAllDay: task.isAllDay,
            reminderTime: nil,
            reminderType: nil,
            listIds: listIds,
            assigneeId: task.assigneeId
        )
    }

    /// Whether a locally-edited task differs from the server's response enough to
    /// warrant a follow-up update push. Includes recurrence so a recurrence-only
    /// edit (or an idempotent create that returned a stale/plain task) isn't lost.
    nonisolated static func taskDiffersForSync(local: Task, server: Task) -> Bool {
        local.priority != server.priority
        || local.title != server.title
        || local.isAllDay != server.isAllDay
        || local.isPrivate != server.isPrivate
        || local.completed != server.completed
        || !datesMatch(local.dueDateTime, server.dueDateTime)
        || local.description != server.description
        || local.assigneeId != server.assigneeId
        || local.repeating != server.repeating
        || local.repeatingData != server.repeatingData
    }

    private func resolveListIds(_ listIds: [String]) -> [String] {
        return listIds.map { listId in
            if listId.hasPrefix("temp_"), let realId = tempListIdMapping[listId] {
                return realId
            }
            return listId
        }
    }
}
