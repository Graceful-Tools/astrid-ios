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
    /// O(1) id → task lookup (mirrors `tasks`). Lets callers avoid an O(n)
    /// `tasks.first(where:)` scan per lookup (e.g. subtask-depth walking).
    var tasksById: [String: Task] { cachedTasks }
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
    /// swap, CoreData temp-delete + real-save (marked synced).
    ///
    /// Idempotent by design: during dual-write the legacy path usually reconciles
    /// first (temp already gone), so this only ensures the mapping and returns.
    func reconcileOutboxCreatedTask(tempId: String, serverTask: Task) async {
        // Always ensure the mapping — a dependent comment/update may target it.
        recordTempTaskMapping(tempId: tempId, realId: serverTask.id)

        guard cachedTasks[tempId] != nil || tasks.contains(where: { $0.id == tempId }) else {
            // A fetch merge already swapped temp→real in memory. It saved the
            // real row but does NOT delete the temp CoreData row — left behind
            // it stays syncStatus=="pending" forever (phantom pending count) and
            // resurrects as a duplicate on the next launch. Delete it here.
            try? await deleteTaskFromCoreData(tempId)
            return
        }
        let temp = cachedTasks[tempId] ?? tasks.first(where: { $0.id == tempId })

        // Carry forward client-side fields the server response may not echo.
        var reconciled = serverTask
        reconciled.clientRequestId = temp?.clientRequestId ?? serverTask.clientRequestId
        var mergedListIds = serverTask.listIds ?? []
        for id in temp?.listIds ?? [] where !mergedListIds.contains(id) { mergedListIds.append(id) }
        reconciled.listIds = mergedListIds

        // Overlay editable fields from the temp task: the create response only
        // echoes what was enqueued — anything changed DURING the flight
        // (completing a just-imported task, a quick title edit) lives on the
        // temp task and has its own queued update. Without this overlay the
        // reconcile visually reverts those changes (the Google "hundreds of
        // completed tasks arrive open" bug).
        if let temp {
            reconciled.title = temp.title
            reconciled.description = temp.description
            reconciled.priority = temp.priority
            reconciled.completed = temp.completed
            reconciled.dueDateTime = temp.dueDateTime
            reconciled.isAllDay = temp.isAllDay
            reconciled.assigneeId = temp.assigneeId
            reconciled.repeating = temp.repeating
            reconciled.repeatingData = temp.repeatingData
            reconciled.isPrivate = temp.isPrivate
        }

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
    }

    /// Finalize a task deletion once the Outbox `deleteTask` handler succeeds:
    /// remove the pending_delete CoreData row. The recently-deleted guard is
    /// intentionally RETAINED — a fetch that started before the server delete
    /// can still deliver the task after confirmation, and clearing the guard
    /// here let that stale response resurrect the task until restart. Task ids
    /// are never reused, so retaining them (capped) is safe.
    func finalizeOutboxDeletedTask(id: String, resolvedId: String) async {
        try? await deleteTaskFromCoreData(id)
        if resolvedId != id { try? await deleteTaskFromCoreData(resolvedId) }
        updatePendingOperationsCount()
        await badgeManager.updateBadge(with: self.tasks)
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

    /// IDs of tasks deleted locally. Persisted to UserDefaults so it survives app restarts.
    /// Without persistence, closing the app after deleting tasks loses the delete tracking:
    /// syncPendingOperations pushes the delete and clears CoreData, but if the server still
    /// returns the task briefly, there's nothing left to filter it → deleted tasks reappear.
    private static let recentlyDeletedIdsKey = "recentlyDeletedTaskIds"
    private static let recentlyDeletedCap = 500
    /// Read-only view. Mutations go through recordRecentlyDeleted — ordered,
    /// capped storage so eviction drops the OLDEST ids (a Set round-trip
    /// evicts arbitrarily and could drop the id just recorded).
    private var recentlyDeletedIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.recentlyDeletedIdsKey) ?? [])
    }

    private func recordRecentlyDeleted(_ ids: [String]) {
        let arr = Self.appendingDeletedIds(
            UserDefaults.standard.stringArray(forKey: Self.recentlyDeletedIdsKey) ?? [],
            ids, cap: Self.recentlyDeletedCap)
        UserDefaults.standard.set(arr, forKey: Self.recentlyDeletedIdsKey)
    }

    /// Pure ledger append: idempotent, ordered, oldest-first eviction at cap —
    /// eviction must never drop the id just recorded (a Set round-trip would).
    nonisolated static func appendingDeletedIds(_ existing: [String], _ ids: [String], cap: Int) -> [String] {
        var arr = existing
        for id in ids where !arr.contains(id) { arr.append(id) }
        if arr.count > cap { arr.removeFirst(arr.count - cap) }
        return arr
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
            // Only the ACTIVE (incomplete) tasks must be in memory before the
            // first render for offline mode — that's the set the lists show.
            // But converting a large active backlog to domain models on the
            // main thread still janks launch. Map only a bounded FIRST PAGE
            // synchronously (enough to fill the first screen offline); the rest
            // of the active backlog and the completed history hydrate off the
            // launch critical path.
            let deletedIds = recentlyDeletedIds
            let fetchRequest = CDTask.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "completed == NO")
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            fetchRequest.fetchLimit = Self.initialActivePageSize
            let cdTasks = try coreDataManager.viewContext.fetch(fetchRequest)

            // Convert to domain models, excluding tasks pending deletion.
            // Also exclude tasks tracked in recentlyDeletedIds (persisted in UserDefaults)
            // in case CoreData status was lost from a previous bug.
            self.tasks = cdTasks
                .filter { $0.syncStatus != "pending_delete" && !deletedIds.contains($0.id) }
                .map { $0.toDomainModel() }
            for task in self.tasks {
                cachedTasks[task.id] = task
            }
            updatePendingOperationsCount()
            print("✅ [TaskService] Loaded \(tasks.count) active tasks (first page) from cache synchronously (\(pendingOperationsCount) pending)")
            // Mark as loaded IMMEDIATELY so UI shows cached data right away
            // This is critical for offline mode - user sees data even before network sync
            self.hasCompletedInitialLoad = true

            // Hydrate the rest of the active backlog off the main thread, then
            // the completed history — both off the launch critical path.
            _Concurrency.Task { @MainActor [weak self] in
                await self?.hydrateRemainingActiveTasksFromCache()
                self?.hydrateCompletedTasksFromCache()
            }
        } catch {
            print("❌ [TaskService] Failed to load cached tasks: \(error)")
            self.hasCompletedInitialLoad = true  // Mark as loaded even on error to not block UI
        }
    }

    /// Number of active tasks mapped synchronously at launch. Enough to fill the
    /// first screen offline; the remaining active backlog hydrates off the main
    /// thread in `hydrateRemainingActiveTasksFromCache`.
    private static let initialActivePageSize = 100

    /// Convert the active tasks beyond the first page on a background CoreData
    /// context (keeps the potentially-expensive model mapping off the main
    /// thread), then merge them into memory. Never overwrites a task already in
    /// memory — a first-page entry or an in-flight edit wins. Runs off the
    /// launch critical path (see `loadCachedTasks`).
    private func hydrateRemainingActiveTasksFromCache() async {
        let deletedIds = recentlyDeletedIds
        let pageSize = Self.initialActivePageSize
        let context = coreDataManager.newBackgroundContext()
        let remaining: [Task] = await context.perform {
            let request = CDTask.fetchRequest()
            request.predicate = NSPredicate(format: "completed == NO")
            request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
            request.fetchOffset = pageSize
            guard let cdTasks = try? context.fetch(request) else { return [] }
            return cdTasks
                .filter { $0.syncStatus != "pending_delete" && !deletedIds.contains($0.id) }
                .map { $0.toDomainModel() }
        }

        let fresh = Self.freshActiveTasksToAppend(
            remaining: remaining,
            alreadyLoadedIds: Set(cachedTasks.keys)
        )
        guard !fresh.isEmpty else { return }
        for task in fresh { cachedTasks[task.id] = task }
        self.tasks.append(contentsOf: fresh)
        updatePendingOperationsCount()
        print("✅ [TaskService] Hydrated \(fresh.count) remaining active tasks from cache")
    }

    /// Pure dedup for remaining-active hydration: keep only tasks not already in
    /// memory, so hydrating the backlog never double-inserts a first-page task
    /// nor clobbers an edit that landed while the background fetch was running.
    nonisolated static func freshActiveTasksToAppend(
        remaining: [Task],
        alreadyLoadedIds: Set<String>
    ) -> [Task] {
        remaining.filter { !alreadyLoadedIds.contains($0.id) }
    }

    /// Merge cached COMPLETED tasks into memory after the initial active-task
    /// load. Runs off the launch critical path (see `loadCachedTasks`). Never
    /// overwrites a task already in memory (an active-task edit in flight wins).
    private func hydrateCompletedTasksFromCache() {
        do {
            let fetchRequest = CDTask.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "completed == YES")
            let cdTasks = try coreDataManager.viewContext.fetch(fetchRequest)
            let deletedIds = recentlyDeletedIds
            let completed = cdTasks
                .filter { $0.syncStatus != "pending_delete" && !deletedIds.contains($0.id) }
                .map { $0.toDomainModel() }
                .filter { cachedTasks[$0.id] == nil }
            guard !completed.isEmpty else { return }
            for task in completed { cachedTasks[task.id] = task }
            self.tasks.append(contentsOf: completed)
            print("✅ [TaskService] Hydrated \(completed.count) completed tasks from cache")
        } catch {
            print("⚠️ [TaskService] Failed to hydrate completed tasks: \(error)")
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
        repeatingData: CustomRepeatingPattern? = nil,
        parentTaskId: String? = nil,
        source: SyncSource? = nil,  // Origin tag for provider echo suppression
        presumeCompletedAt: Date? = nil  // Sync history imports: born completed+backdated so the optimistic temp never flashes as an open row (the caller still calls completeTask to enqueue the server-side completion)
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
            completed: presumeCompletedAt != nil,
            completedAt: presumeCompletedAt,
            completedSource: presumeCompletedAt != nil ? (source?.rawValue ?? "astrid") : nil,
            attachments: nil,
            comments: nil,
            createdAt: Date(),
            updatedAt: Date(),
            originalTaskId: nil,
            sourceListId: nil,
            clientRequestId: clientRequestId,
            parentTaskId: parentTaskId
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

        // CRITICAL: Filter out temp_ list IDs - server doesn't know about them.
        // Tasks with temp list IDs will be synced later when lists get real IDs.
        let serverListIds = listIds.filter { !$0.hasPrefix("temp_") }

        // The Outbox is authoritative for creates: its handler does the server
        // create + reconciliation (temp→real swap, mark synced) when it drains —
        // online now, or on reconnect if offline.
        await OutboxManager.shared.enqueueCreateTask(
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
                tempId: tempId,
                parentTaskId: parentTaskId,
                source: source?.rawValue
            ),
            clientRequestId: clientRequestId
        )

        return optimisticTask
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
        task: Task? = nil,  // Optional: provide task if not in cache (e.g., from featured lists)
        source: SyncSource? = nil,
        completedAt: Date? = nil  // Origin tag for provider echo suppression (persisted on the Outbox payload)
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
        if let completed = completed {
            optimisticTask.completed = completed
            optimisticTask.completedAt = completed ? (completedAt ?? Date()) : nil
            optimisticTask.completedSource = completed ? (source?.rawValue ?? "astrid") : nil
        }

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
        } else if !recentlyDeletedIds.contains(resolvedId) {
            // Add to tasks array if not already there (e.g., featured list tasks) —
            // but never resurrect a deleted task (late queued updates / SSE echoes).
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

        // Temp ids enqueue like any other update: UpdateTaskOutboxHandler
        // resolves temp→real via the mapping and returns .blocked (no attempt
        // burn) until the createTask entry drains. The old early return here
        // dropped the server write entirely once legacy replay was deleted —
        // completions of just-imported tasks (Google backfill) stayed open on
        // the server and reverted locally on the next fetch.

        // Build the update request and hand it to the Outbox
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

            // An isAllDay-only edit (no date change) must still reach the wire.
            if isAllDayValue == nil, let isAllDay = isAllDay {
                isAllDayValue = isAllDay
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
                lastTimerValue: lastTimerValue,
                completedAt: (completed == true)
                    ? ISO8601DateFormatter().string(from: completedAt ?? Date()) : nil,
                completedSource: (completed == true) ? (source?.rawValue ?? "astrid") : nil
            )

            // The Outbox is authoritative for updates: its handler performs the
            // PUT and marks the row synced when it drains (online now, or on
            // reconnect). The optimistic in-memory/CoreData update already
            // happened above.
            await OutboxManager.shared.enqueueUpdateTask(
                UpdateTaskOutboxPayload(taskId: resolvedId, updates: updates, source: source?.rawValue),
                clientRequestId: UUID().uuidString
            )

            updatePendingOperationsCount()
            await badgeManager.updateBadge(with: self.tasks)
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

        var updatedTask = try await apiClient.updateTask(id: resolvedId, updates: updates)
        // Device-monotonic stamp: the server clock can trail the device, and a
        // server timestamp <= the sync watermark would suppress this edit's
        // push to external providers.
        updatedTask.updatedAt = Date()
        updateTaskInCache(updatedTask)
        // Server-first path skips the Outbox, so nudge the providers directly.
        NotificationCenter.default.post(name: OutboxManager.didEnqueueMutation, object: nil)

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

    func completeTask(id: String, completed: Bool, task: Task? = nil, timerDuration: Int? = nil, lastTimerValue: String? = nil, source: SyncSource? = nil, completedAt: Date? = nil) async throws -> Task {
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
                    task: task,
                    source: source
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
                    task: task,
                    source: source
                )
            }
        }

        // Non-repeating task or un-completing - use normal update
        return try await updateTask(taskId: id, completed: completed, timerDuration: timerDuration, lastTimerValue: lastTimerValue, task: task, source: source, completedAt: completedAt)
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
        // Capture external sync links BEFORE the delete: the server cascades
        // ExternalTaskLink rows away with the task, so providers must record
        // the remote twin now (delete/close it next pass, tombstone forever).
        let resolvedForSync = tempTaskIdMapping[id] ?? id

        // Any open detail view for this task must close (deletes can also
        // arrive from external sync, not just the view's own delete button).
        NotificationCenter.default.post(
            name: .astridTaskDeleted, object: nil,
            userInfo: ["taskId": id, "resolvedTaskId": resolvedForSync])
        await GitHubSyncService.shared.noteTaskDeleted(taskId: resolvedForSync)
        await GoogleTasksSyncService.shared.noteTaskDeleted(taskId: resolvedForSync)
        await AppleRemindersService.shared.noteTaskDeleted(taskId: resolvedForSync)

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
        recordRecentlyDeleted([resolvedId])
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

        // The Outbox is authoritative for deletes: its handler owns the server
        // delete (404/410 = already gone = success) and the CoreData
        // finalization when it drains.
        await OutboxManager.shared.enqueueDeleteTask(
            DeleteTaskOutboxPayload(taskId: resolvedId),
            clientRequestId: UUID().uuidString
        )
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
                let existing = existingTasksDict[task.id]
                let cdTask = existing ?? CDTask(context: context)
                let existingStatus = existing?.syncStatus

                // Don't overwrite tasks with pending local operations — those edits
                // need to be pushed to the server first via syncPendingOperations()
                if existingStatus == "pending" || existingStatus == "pending_delete" || existingStatus == "pending_list_sync" {
                    continue
                }

                // Skip unchanged rows: a full sync pass re-hands every task here,
                // but `update(from:)` touches ~30 attributes and marks the managed
                // object dirty even when nothing changed, so an all-tasks save
                // rewrites the whole table each pass. When the existing row is
                // already synced and its server timestamp matches, it's identical
                // to what we'd write — leave it untouched.
                if let existing = existing,
                   existingStatus == "synced",
                   let incoming = task.updatedAt,
                   let stored = existing.updatedAt,
                   incoming == stored {
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
        UserDefaults.standard.removeObject(forKey: Self.recentlyDeletedIdsKey)
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

        // recentlyDeletedIds is intentionally NOT pruned on confirmation: a
        // fetch that started before the server delete can still deliver the
        // task after it, and pruning here let that stale response resurrect
        // the deleted task until restart. Ids are never reused; storage is
        // capped with oldest-first eviction.

        // No-op refresh guard: reassigning the @Published array re-renders
        // every observer even when the content is identical — on a large list
        // each background sync pass showed as a flicker. Skip the publish (and
        // the badge/CoreData churn) when nothing actually changed.
        if sortedTasks == self.tasks {
            return
        }

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

                // Sort by due date, then creation date, then id. The id
                // tie-break makes the order a TOTAL order: dictionary values
                // come out in arbitrary order and sort ties keep that order,
                // so without it, rows with equal keys (a batch of all-day
                // tasks due the same day) shuffled on every background
                // refresh — visible flicker on large lists.
                let sorted = Array(mergedDict.values).sorted { task1, task2 in
                    if task1.dueDateTime != task2.dueDateTime {
                        guard let date1 = task1.dueDateTime else { return false }
                        guard let date2 = task2.dueDateTime else { return true }
                        return date1 < date2
                    }
                    let created1 = task1.createdAt ?? .distantPast
                    let created2 = task2.createdAt ?? .distantPast
                    if created1 != created2 {
                        return created1 > created2
                    }
                    return task1.id < task2.id
                }

                continuation.resume(returning: sorted)
            }
        }
    }

    // MARK: - Offline Sync

    /// Sync pending operations. Every task write is Outbox-owned now, so this
    /// simply drains the Outbox journal (create/update/delete replay lives in
    /// the kind handlers, with retry/backoff and dead-lettering).
    func syncPendingOperations() async throws {
        guard !isSyncingPendingOperations else { return }
        isSyncingPendingOperations = true
        defer { isSyncingPendingOperations = false }
        await OutboxManager.shared.drain()
        updatePendingOperationsCount()
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

    private func resolveListIds(_ listIds: [String]) -> [String] {
        return listIds.map { listId in
            if listId.hasPrefix("temp_"), let realId = tempListIdMapping[listId] {
                return realId
            }
            return listId
        }
    }
}

extension Notification.Name {
    /// Posted by TaskService.deleteTask so open detail views can close.
    static let astridTaskDeleted = Notification.Name("astridTaskDeleted")
}
