import Foundation
import Combine
import CoreData

/// List service using API v1 with offline support via CoreData
/// Handles list operations and syncing
@MainActor
class ListService: ObservableObject {
    static let shared = ListService()

    @Published var lists: [TaskList] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingListsCount: Int = 0
    @Published var isSyncingPendingLists = false
    @Published var hasCompletedInitialLoad = false  // Track if initial cache load is done

    private let apiClient = AstridAPIClient.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var cachedLists: [String: TaskList] = [:]
    /// O(1) id → list lookup (mirrors TaskService.tasksById) — used by row chips etc.
    var listsById: [String: TaskList] { cachedLists }
    private var syncTimer: Timer?
    private var networkObserver: NSObjectProtocol?

    private init() {
        setupNetworkObserver()
        startBackgroundSync()

        // Load cached lists synchronously to ensure data is available before any UI renders
        // This is CRITICAL for offline mode - lists must be in memory before network calls fail
        loadCachedLists()

        subscribeToLiveListUpdates()
    }

    // MARK: - Live Updates (SSE)

    /// Subscribe to the `list_*` stream so a list renamed, created or deleted elsewhere shows up
    /// now rather than at the next 60 s pull (AITD-314).
    ///
    /// Cache-only, like the task side: no API call and no write back to the server.
    private func subscribeToLiveListUpdates() {
        _Concurrency.Task {
            let sse = SSEClient.shared

            await sse.onListCreated { list in
                _Concurrency.Task { @MainActor in ListService.shared.applyLiveListUpsert(list) }
            }
            await sse.onListUpdated { list in
                _Concurrency.Task { @MainActor in ListService.shared.applyLiveListUpsert(list) }
            }
            await sse.onListDeleted { listId in
                _Concurrency.Task { @MainActor in ListService.shared.applyLiveListDelete(listId) }
            }
        }
    }

    /// Merge a list that arrived over SSE into the cache. `LiveUpdatePolicy` decides whether it may
    /// be applied — a stale event must not clobber a newer local edit.
    func applyLiveListUpsert(_ list: TaskList) {
        let decision = LiveUpdatePolicy.listUpsert(incoming: list, cached: cachedLists[list.id])
        guard decision == .apply else {
            print("📡 [ListService] Live list \(list.id) ignored: \(decision)")
            return
        }

        cachedLists[list.id] = list

        if let index = lists.firstIndex(where: { $0.id == list.id }) {
            let sortKeysChanged = ListOrdering.isOrderedBefore(lists[index], list)
                || ListOrdering.isOrderedBefore(list, lists[index])
            if sortKeysChanged {
                // A rename or a favorite toggle moves the row; put it where a fetch would.
                lists.remove(at: index)
                lists.insert(list, at: ListOrdering.insertionIndex(for: list, in: lists))
            } else {
                lists[index] = list
            }
        } else {
            lists.insert(list, at: ListOrdering.insertionIndex(for: list, in: lists))
        }

        print("📡 [ListService] Applied live list update: \(list.name)")
    }

    /// Remove a list that was deleted elsewhere.
    func applyLiveListDelete(_ listId: String) {
        guard LiveUpdatePolicy.listDelete(id: listId) == .apply else { return }
        guard cachedLists[listId] != nil || lists.contains(where: { $0.id == listId }) else { return }

        cachedLists.removeValue(forKey: listId)
        lists.removeAll { $0.id == listId }
        print("📡 [ListService] Applied live list delete: \(listId)")
    }

    // MARK: - Initialization

    /// Load cached lists from CoreData on startup (synchronous, blocking)
    /// CRITICAL: This must be synchronous to ensure lists are loaded before UI renders
    /// Without this, opening the app offline shows no lists even though they're cached
    private func loadCachedLists() {
        do {
            // Load from viewContext synchronously on main thread
            // This is safe because init() already runs on MainActor and reads are fast
            let fetchRequest = CDTaskList.fetchRequest()
            // No predicate - get all cached lists for offline support
            let cdLists = try coreDataManager.viewContext.fetch(fetchRequest)

            // Add all cached lists to in-memory array
            for cdList in cdLists {
                let list = cdList.toDomainModel()
                cachedLists[list.id] = list
                if !lists.contains(where: { $0.id == list.id }) {
                    lists.append(list)
                }
            }

            // Sort lists (favorites first, then alphabetical)
            lists = lists.sorted(by: ListOrdering.isOrderedBefore)

            updatePendingListsCount()
            hasCompletedInitialLoad = true
            print("✅ [ListService] Loaded \(cdLists.count) lists from cache synchronously for offline support")
        } catch {
            print("❌ [ListService] Failed to load cached lists: \(error)")
            hasCompletedInitialLoad = true  // Mark as loaded even on error to not block UI
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
                print("🔄 [ListService] Network restored - syncing pending lists")
                try? await self?.syncPendingLists()
            }
        }
    }

    /// Start background sync timer (every 60 seconds)
    private func startBackgroundSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                guard let self = self else { return }
                // Only sync if we have pending lists and network is available
                if self.pendingListsCount > 0 && self.networkMonitor.isConnected {
                    try? await self.syncPendingLists()
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

    // MARK: - Initial Sync

    /// Fetch all accessible lists
    /// Deleted-list guard: retained for the session (same stale-in-flight-fetch
    /// race as tasks — a fetch that started before the delete can deliver the
    /// list after it and resurrect it in the sidebar). Cleared on sign-out.
    private static let recentlyDeletedListIdsKey = "recentlyDeletedListIds"
    private var recentlyDeletedListIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.recentlyDeletedListIdsKey) ?? [])
    }

    private func recordRecentlyDeletedList(_ id: String) {
        let arr = TaskService.appendingDeletedIds(
            UserDefaults.standard.stringArray(forKey: Self.recentlyDeletedListIdsKey) ?? [],
            [id], cap: 200)
        UserDefaults.standard.set(arr, forKey: Self.recentlyDeletedListIdsKey)
    }

    private func unrecordRecentlyDeletedList(_ id: String) {
        var arr = UserDefaults.standard.stringArray(forKey: Self.recentlyDeletedListIdsKey) ?? []
        arr.removeAll { $0 == id }
        UserDefaults.standard.set(arr, forKey: Self.recentlyDeletedListIdsKey)
    }

    /// Write a freshly-fetched list collection into the local caches — the in-memory `listsById`
    /// map, then CoreData.
    ///
    /// `merged` is what the sidebar shows: the server's lists plus any not-yet-synced `temp_`
    /// ones. `serverLists` is what the response actually contained, and it is what decides a
    /// prune — `GET /api/v1/lists` returns the whole collection, so absence from it really does
    /// mean the list was deleted elsewhere (`SyncOrphanPrune` decides which absences count, so a
    /// list created offline — absent from every response by definition — survives).
    ///
    /// AITD-324: this used to sit inside `fetchLists()`, which made that function the only thing
    /// in the app that persisted a list. `SyncManager.performFullSync` fetches the same collection
    /// at launch and assigned `lists` without caching any of it, so the CoreData store — the one
    /// thing an offline launch reads — held whatever the last view that happened to call
    /// `fetchLists()` had left behind, and a list deleted on web was never pruned from it
    /// (task 53071260). Both fetch paths now cache what they fetched.
    func cacheListsLocally(merged: [TaskList], serverLists: [TaskList]) {
        // A fetch that started before a local delete must not write its stale copy of the list
        // back (task c6615a5d). The filter lives HERE, not at the call site, so every caching
        // path inherits it: `performFullSync` does not filter its own response, and before
        // AITD-324 it did not need to, because it cached nothing.
        let deletedIds = recentlyDeletedListIds
        let liveLists = ListCachePlan.persistable(serverLists: serverLists, deletedIds: deletedIds)

        for list in ListCachePlan.inMemory(merged: merged, deletedIds: deletedIds) {
            cachedLists[list.id] = list
        }

        // A list the server has stopped returning was deleted elsewhere — drop it from the
        // in-memory cache too, or `listsById` keeps serving it for the rest of the session.
        let serverIds = Set(liveLists.map(\.id))
        for id in ListCachePlan.stale(cachedIds: cachedLists.keys, serverIds: serverIds) {
            cachedLists.removeValue(forKey: id)
        }

        // Save lists to CoreData for offline support…
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            for list in liveLists {
                do {
                    try await self.saveListToCoreData(list, syncStatus: "synced")
                } catch {
                    print("⚠️ [ListService] Failed to cache list to CoreData: \(error)")
                }
            }
            // …and remove the rows it stopped returning. Without this half, deleting a list
            // on web left its row behind and `loadCachedLists` brought it back on the next
            // launch (task 53071260).
            do {
                try await self.pruneListsMissingFromServer(serverIds: serverIds)
            } catch {
                print("⚠️ [ListService] Failed to prune deleted lists from CoreData: \(error)")
            }
        }
    }

    /// Apply a list collection that just came back from the server: drop anything deleted
    /// locally, keep unsynced local lists on top, put it on screen in the one sidebar order, and
    /// cache it.
    ///
    /// AITD-326: both fetch paths land here. `SyncManager.performFullSync` used to do all of this
    /// itself — from the raw response, with its own copy of the comparator — so a sync could show
    /// a list the user had just deleted and could order the sidebar differently from the next
    /// `fetchLists()`. The deletion filter stays inside `ListService` because
    /// `recentlyDeletedListIds` does.
    @discardableResult
    func applyFetchedLists(_ fetchedLists: [TaskList]) -> [TaskList] {
        // Never resurrect a deleted list from a stale in-flight response (task c6615a5d).
        let liveLists = ListCachePlan.persistable(serverLists: fetchedLists,
                                                  deletedIds: recentlyDeletedListIds)
        let pendingLists = lists.filter { $0.id.hasPrefix(SyncOrphanPrune.localIdPrefix) }
        let mergedLists = ListCachePlan.merged(serverLists: liveLists, pendingLists: pendingLists)

        self.lists = mergedLists
        cacheListsLocally(merged: mergedLists, serverLists: liveLists)
        return mergedLists
    }

    func fetchLists() async throws -> [TaskList] {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            print("📡 [ListService] Calling apiClient.getLists()...")
            let fetchedLists = try await apiClient.getLists()
            print("📡 [ListService] Response received with \(fetchedLists.count) lists")

            applyFetchedLists(fetchedLists)

            for list in self.lists {
                print("  📋 List: \(list.name) (tasks: \(list.taskCount ?? 0))")
                print("    👥 Owner: \(list.owner?.displayName ?? "nil")")
                print("    👥 Members: \(list.listMembers?.count ?? 0)")
            }

            print("✅ [ListService] Synced \(self.lists.count) lists")

            return self.lists

        } catch {
            errorMessage = error.localizedDescription
            print("⚠️ [ListService] Sync failed (offline mode), using cached data: \(error)")
            // Don't throw - use cached data instead
            // Lists are already loaded from cache in init()
            // Mark as loaded so UI doesn't block forever
            if !hasCompletedInitialLoad {
                hasCompletedInitialLoad = true
            }
            return self.lists
        }
    }

    // MARK: - List Operations

    func createList(
        name: String,
        description: String? = nil,
        privacy: String = "PRIVATE",
        color: String? = nil
    ) async throws -> TaskList {
        // OPTIMISTIC UPDATE: Create temporary list immediately
        let tempId = "temp_\(UUID().uuidString)"

        // CRITICAL: Set ownerId to current user so QuickAddTaskView shows for offline lists
        // Without this, canUserAddTasks() returns false because user role is .none
        let currentUserId = AuthManager.shared.userId

        let optimisticList = TaskList(
            id: tempId,
            name: name,
            color: color ?? "#3b82f6",
            imageUrl: nil,
            coverImageUrl: nil,
            privacy: TaskList.Privacy(rawValue: privacy) ?? .PRIVATE,
            publicListType: nil,
            ownerId: currentUserId,
            owner: nil,
            admins: nil,
            members: nil,
            listMembers: nil,
            invitations: nil,
            defaultAssigneeId: nil,
            defaultAssignee: nil,
            defaultPriority: nil,
            defaultRepeating: nil,
            defaultIsPrivate: nil,
            defaultDueDate: nil,
            defaultDueTime: nil,
            mcpEnabled: nil,
            mcpAccessLevel: nil,
            aiAstridEnabled: nil,
            preferredAiProvider: nil,
            fallbackAiProvider: nil,
            githubRepositoryId: nil,
            aiAgentsEnabled: nil,
            aiAgentConfiguredBy: nil,
            copyCount: nil,
            createdAt: Date(),
            updatedAt: Date(),
            description: description,
            tasks: [],
            taskCount: 0,
            isFavorite: false,
            favoriteOrder: nil,
            isVirtual: false,
            virtualListType: nil,
            sortBy: nil,
            manualSortOrder: nil,
            filterCompletion: nil,
            filterDueDate: nil,
            filterAssignee: nil,
            filterAssignedBy: nil,
            filterRepeating: nil,
            filterPriority: nil,
            filterInLists: nil
        )

        // Update UI immediately
        cachedLists[tempId] = optimisticList
        lists.insert(optimisticList, at: 0)
        print("⚡️ [ListService] Optimistically created list: \(name)")

        // Save to CoreData with pending status for offline support (fire-and-forget, non-blocking)
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.saveListToCoreData(optimisticList, syncStatus: "pending")
            } catch {
                print("⚠️ [ListService] Failed to save to CoreData, but list is in memory: \(error)")
            }
        }

        // Make server call in background
        do {
            let list = try await apiClient.createList(
                name: name,
                description: description,
                color: color,
                privacy: privacy
            )

            // Replace temporary list with server response
            cachedLists.removeValue(forKey: tempId)
            cachedLists[list.id] = list

            if let index = lists.firstIndex(where: { $0.id == tempId }) {
                lists[index] = list
            }

            // Update CoreData with server response and synced status (fire-and-forget)
            _Concurrency.Task.detached { [weak self] in
                guard let self = self else { return }
                do {
                    try await self.deleteListFromCoreData(tempId)  // Remove temp list
                    try await self.saveListToCoreData(list, syncStatus: "synced")
                } catch {
                    print("⚠️ [ListService] Failed to update CoreData after list creation: \(error)")
                }
            }

            print("✅ [ListService] Server confirmed list: \(list.name)")

            // CRITICAL: Notify TaskService to update any tasks created with the temp list ID
            // This handles the case where tasks were created on this list before server confirmed
            await TaskService.shared.onListSynced(tempListId: tempId, realListId: list.id)

            updatePendingListsCount()

            return list
        } catch {
            // DON'T ROLLBACK: Keep list as "pending" for offline support
            print("⚠️ [ListService] Failed to sync list to server, keeping as pending: \(error)")
            updatePendingListsCount()

            // Return the optimistic list so UI shows it
            return optimisticList
        }
    }

    /// Apply an optimistic membership edit to the cached list so the change survives
    /// a view dismissal and every surface reading `ListService.lists` sees it at once
    /// (task 33fc21fc). `ListMemberOptimistic` owns what each edit means; this only
    /// decides where the result is written.
    func applyMemberChange(listId: String, _ transform: (TaskList) -> TaskList) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            let updated = transform(lists[index])
            lists[index] = updated
            cachedLists[listId] = updated
        } else if let cached = cachedLists[listId] {
            // Not in the visible array (a list the user isn't currently browsing)
            // but still cached — keep the two from drifting apart.
            cachedLists[listId] = transform(cached)
        }
    }

    /// Remove a member from the cached list so the change persists across view dismissals.
    /// Called after optimistic removal in the UI — reverted if the API call fails.
    func removeMemberFromCachedList(listId: String, userId: String) {
        applyMemberChange(listId: listId) {
            ListMemberOptimistic.applyingRemoval($0, userId: userId)
        }
    }

    /// Restore a member to the cached list (used when API removal fails and we need to revert).
    func restoreCachedList(listId: String, from original: TaskList) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index] = original
            cachedLists[listId] = original
        }
    }

    func updateList(
        listId: String,
        name: String? = nil,
        description: String? = nil
    ) async throws -> TaskList {
        // OPTIMISTIC UPDATE: Store original list for rollback
        guard let originalList = cachedLists[listId] ?? lists.first(where: { $0.id == listId }) else {
            throw NSError(domain: "ListService", code: 404, userInfo: [NSLocalizedDescriptionKey: "List not found"])
        }

        // Create optimistic updated list
        var optimisticList = originalList
        if let name = name { optimisticList.name = name }
        if let description = description { optimisticList.description = description }

        // Update UI immediately
        cachedLists[listId] = optimisticList
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index] = optimisticList
        }
        print("⚡️ [ListService] Optimistically updated list: \(optimisticList.name)")

        // Make server call in background
        do {
            let updates = UpdateListRequest(
                name: name,
                description: description,
                color: nil,
                imageUrl: nil,
                privacy: nil,
                isFavorite: nil,
                defaultAssigneeId: nil,
                defaultPriority: nil,
                defaultRepeating: nil,
                defaultIsPrivate: nil,
                defaultDueDate: nil
            )

            let list = try await apiClient.updateList(id: listId, updates: updates)

            // Replace with server response
            cachedLists[listId] = list
            if let index = lists.firstIndex(where: { $0.id == listId }) {
                lists[index] = list
            }

            print("✅ [ListService] Server confirmed list update: \(list.name)")

            return list
        } catch {
            // ROLLBACK: Restore original list on error
            cachedLists[listId] = originalList
            if let index = lists.firstIndex(where: { $0.id == listId }) {
                lists[index] = originalList
            }
            print("❌ [ListService] Failed to update list, rolled back: \(error)")
            throw error
        }
    }

    func updateListAdvanced(listId: String, updates: [String: Any]) async throws -> TaskList {
        // OPTIMISTIC UPDATE: Store original list for rollback
        guard let originalList = cachedLists[listId] ?? lists.first(where: { $0.id == listId }) else {
            throw NSError(domain: "ListService", code: 404, userInfo: [NSLocalizedDescriptionKey: "List not found"])
        }

        print("📡 [ListService] updateListAdvanced called with updates: \(updates)")

        // Create optimistic updated list by applying changes
        var optimisticList = originalList

        // Apply updates to create optimistic list
        if let name = updates["name"] as? String { optimisticList.name = name }
        if let description = updates["description"] as? String { optimisticList.description = description }
        if let color = updates["color"] as? String { optimisticList.color = color }
        if let imageUrl = updates["imageUrl"] as? String { optimisticList.imageUrl = imageUrl }
        if let privacy = updates["privacy"] as? String, let privacyEnum = TaskList.Privacy(rawValue: privacy) {
            optimisticList.privacy = privacyEnum
        }
        if let publicListType = updates["publicListType"] as? String { optimisticList.publicListType = publicListType }
        if let isFavorite = updates["isFavorite"] as? Bool { optimisticList.isFavorite = isFavorite }
        if let showSubtasks = updates["showSubtasks"] as? Bool { optimisticList.showSubtasks = showSubtasks }

        // List defaults
        if let defaultPriority = updates["defaultPriority"] as? Int { optimisticList.defaultPriority = defaultPriority }
        if let defaultRepeating = updates["defaultRepeating"] as? String { optimisticList.defaultRepeating = defaultRepeating }
        if let defaultIsPrivate = updates["defaultIsPrivate"] as? Bool { optimisticList.defaultIsPrivate = defaultIsPrivate }
        if let defaultDueDate = updates["defaultDueDate"] as? String { optimisticList.defaultDueDate = defaultDueDate }
        if updates.keys.contains("defaultDueTime") {
            optimisticList.defaultDueTime = updates["defaultDueTime"] as? String
        }
        if updates.keys.contains("defaultAssigneeId") {
            optimisticList.defaultAssigneeId = updates["defaultAssigneeId"] as? String
        }

        // Virtual list settings
        if let isVirtual = updates["isVirtual"] as? Bool { optimisticList.isVirtual = isVirtual }
        if let virtualListType = updates["virtualListType"] as? String { optimisticList.virtualListType = virtualListType }

        // Sort and filter settings
        if let sortBy = updates["sortBy"] as? String { optimisticList.sortBy = sortBy }
        if let filterPriority = updates["filterPriority"] as? String { optimisticList.filterPriority = filterPriority }
        if let filterAssignee = updates["filterAssignee"] as? String { optimisticList.filterAssignee = filterAssignee }
        if let filterDueDate = updates["filterDueDate"] as? String { optimisticList.filterDueDate = filterDueDate }
        if let filterCompletion = updates["filterCompletion"] as? String { optimisticList.filterCompletion = filterCompletion }
        if let filterRepeating = updates["filterRepeating"] as? String { optimisticList.filterRepeating = filterRepeating }
        if let filterAssignedBy = updates["filterAssignedBy"] as? String { optimisticList.filterAssignedBy = filterAssignedBy }
        if let filterInLists = updates["filterInLists"] as? String { optimisticList.filterInLists = filterInLists }

        // Update UI immediately
        cachedLists[listId] = optimisticList
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index] = optimisticList
        }
        print("⚡️ [ListService] Optimistically updated list: \(optimisticList.name)")

        // Save to CoreData immediately for offline support
        _Concurrency.Task.detached { [weak self] in
            do {
                try await self?.coreDataManager.saveInBackground { context in
                    guard let cdList = try CDTaskList.fetchById(listId, context: context) else {
                        print("⚠️ [ListService] List not found in CoreData: \(listId)")
                        return
                    }
                    cdList.update(from: optimisticList)
                    print("💾 [ListService] Saved list updates to CoreData")
                }
            } catch {
                print("⚠️ [ListService] Failed to save to CoreData: \(error)")
            }
        }

        // Make server call in background (don't rollback if offline - keep optimistic update!)
        // Use updateListWithDictionary to properly send NSNull() as JSON null
        // This is required for clearing fields like defaultAssigneeId (Task Creator = null)
        do {
            let updatedList = try await apiClient.updateListWithDictionary(id: listId, updates: updates)

            print("📥 [ListService] Server response for list update:")
            print("  - defaultAssigneeId: \(updatedList.defaultAssigneeId ?? "nil")")
            print("  - defaultPriority: \(updatedList.defaultPriority ?? -1)")

            // Replace with server response
            cachedLists[listId] = updatedList
            if let index = lists.firstIndex(where: { $0.id == listId }) {
                lists[index] = updatedList
            }

            // Update CoreData with server response
            _Concurrency.Task.detached { [weak self] in
                do {
                    try await self?.coreDataManager.saveInBackground { context in
                        guard let cdList = try CDTaskList.fetchById(listId, context: context) else { return }
                        cdList.update(from: updatedList)
                    }
                } catch {
                    print("⚠️ [ListService] Failed to save server response to CoreData: \(error)")
                }
            }

            print("✅ [ListService] Server confirmed list update: \(updatedList.name)")

            return updatedList
        } catch {
            // DON'T ROLLBACK - Keep optimistic update for offline support
            // The update was already saved to CoreData and will persist across app restarts
            print("⚠️ [ListService] Failed to sync list update to server (offline?): \(error)")
            print("💾 [ListService] Keeping optimistic update - will sync when online")

            // Return the optimistic list instead of throwing
            return optimisticList
        }
    }

    func deleteList(listId: String) async throws {
        // OPTIMISTIC UPDATE: Store list for rollback
        guard let deletedList = cachedLists[listId] ?? lists.first(where: { $0.id == listId }) else {
            throw NSError(domain: "ListService", code: 404, userInfo: [NSLocalizedDescriptionKey: "List not found"])
        }

        // Remove from UI immediately + guard against stale-fetch resurrection
        recordRecentlyDeletedList(listId)
        cachedLists.removeValue(forKey: listId)
        lists.removeAll { $0.id == listId }
        print("⚡️ [ListService] Optimistically deleted list: \(deletedList.name)")

        // Capture a Google sync link BEFORE the delete (the server cascades it
        // away) so the all-lists auto-link can record the opt-out.
        let googleLink = GoogleTasksSyncService.shared.links.first { $0.astridListId == listId }

        // Make server call in background
        do {
            try await apiClient.deleteList(id: listId)
            print("✅ [ListService] Server confirmed list deletion: \(listId)")

            // Remove from CoreData so the list doesn't resurrect from the
            // offline cache on next launch.
            try? await deleteListFromCoreData(listId)

            // If this list mirrored a Google tasklist, remember the opt-out so
            // the all-lists sync mode doesn't immediately re-create it.
            if let googleLink {
                await GoogleTasksSyncService.shared.noteMirroredListDeleted(tasklistId: googleLink.remoteContainerId)
                await GoogleTasksSyncService.shared.refreshStatus()
            }
        } catch {
            // ROLLBACK: Restore list on error
            unrecordRecentlyDeletedList(listId)
            cachedLists[listId] = deletedList
            lists.insert(deletedList, at: 0)
            print("❌ [ListService] Failed to delete list, rolled back: \(error)")
            throw error
        }
    }

    func updateManualOrder(listId: String, order: [String]) async throws {
        // NO OPTIMISTIC UPDATE - SwiftUI's .onMove() already handles visual reordering
        // Optimistic update here causes flicker when list updates trigger re-render

        print("📡 [ListService] Updating manual order for list: \(listId)")
        print("📡 [ListService] New order: \(order)")

        // Update manualSortOrder field via API
        let updates: [String: Any] = ["manualSortOrder": order]
        _ = try await updateListAdvanced(listId: listId, updates: updates)

        print("✅ [ListService] Manual order updated successfully")
    }

    func toggleFavorite(listId: String, isFavorite: Bool) async throws {
        // OPTIMISTIC UPDATE: Store original list for rollback
        guard let originalList = cachedLists[listId] ?? lists.first(where: { $0.id == listId }) else {
            throw NSError(domain: "ListService", code: 404, userInfo: [NSLocalizedDescriptionKey: "List not found"])
        }

        // Calculate next favorite order if favoriting
        let favoriteOrder: Int? = isFavorite ? (lists.compactMap { $0.favoriteOrder }.max() ?? 0) + 1 : nil

        // Create optimistic updated list
        var optimisticList = originalList
        optimisticList.isFavorite = isFavorite
        optimisticList.favoriteOrder = favoriteOrder

        // Update UI immediately
        cachedLists[listId] = optimisticList
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index] = optimisticList
        }

        // Re-sort lists (favorites first)
        lists = lists.sorted(by: ListOrdering.isOrderedBefore)

        print("⚡️ [ListService] Optimistically toggled favorite: \(optimisticList.name)")

        // Make server call in background
        do {
            // TODO: Implement favoriteList in API v1
            // For now, use updateList with isFavorite parameter
            let updates = UpdateListRequest(
                name: nil,
                description: nil,
                color: nil,
                imageUrl: nil,
                privacy: nil,
                isFavorite: isFavorite
            )
            let updatedList = try await apiClient.updateList(id: listId, updates: updates)

            // Replace with server response
            cachedLists[listId] = updatedList
            if let index = lists.firstIndex(where: { $0.id == listId }) {
                lists[index] = updatedList
            }

            print("✅ [ListService] Server confirmed favorite toggle: \(updatedList.name)")
        } catch {
            // ROLLBACK: Restore original list and re-sort
            cachedLists[listId] = originalList
            if let index = lists.firstIndex(where: { $0.id == listId }) {
                lists[index] = originalList
            }

            // Re-sort again to restore order
            lists = lists.sorted(by: ListOrdering.isOrderedBefore)

            print("❌ [ListService] Failed to toggle favorite, rolled back: \(error)")
            throw error
        }
    }

    /// Wrapper for favoriteList to match ListServiceProtocol
    func favoriteList(listId: String, favorite: Bool) async throws -> TaskList {
        try await toggleFavorite(listId: listId, isFavorite: favorite)

        // Return updated list
        if let list = getList(id: listId) {
            return list
        } else {
            throw NSError(domain: "ListService", code: 404, userInfo: [NSLocalizedDescriptionKey: "List not found after favorite toggle"])
        }
    }

    /// Leave a shared list through the v1 service boundary.
    func leaveList(listId: String) async throws {
        try await apiClient.leaveList(id: listId)
        cachedLists.removeValue(forKey: listId)
        lists.removeAll { $0.id == listId }
        try? await deleteListFromCoreData(listId)
    }

    /// Server-first list update for settings screens that do not need the
    /// optimistic local-first flow.
    @discardableResult
    func updateListOnServer(listId: String, updates: UpdateListRequest) async throws -> TaskList {
        let updatedList = try await apiClient.updateList(id: listId, updates: updates)
        cachedLists[listId] = updatedList
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index] = updatedList
        } else {
            lists.append(updatedList)
        }
        try? await saveListToCoreData(updatedList, syncStatus: "synced")
        return updatedList
    }

    func getListMembers(listId: String) async throws -> [User] {
        // TODO: Implement getListMembers in API v1
        // For now, return empty array
        print("⚠️ [ListService] getListMembers not yet implemented in API v1")
        return []
    }

    // MARK: - Helpers

    func getList(id: String) -> TaskList? {
        return cachedLists[id] ?? lists.first(where: { $0.id == id })
    }

    var favoriteLists: [TaskList] {
        lists.filter { $0.isFavorite == true }
            .sorted { ($0.favoriteOrder ?? Int.max) < ($1.favoriteOrder ?? Int.max) }
    }

    /// Check if a user is a member of a list (owner, admin, or member)
    /// Returns true if the user has any access to the list
    func isUserMemberOfList(userId: String, listId: String) -> Bool {
        guard let list = getList(id: listId) else {
            return false
        }
        return list.isMember(userId: userId)
    }

    // MARK: - Cache Management

    /// Clear all in-memory list data (used on logout)
    func clearCache() {
        lists = []
        cachedLists = [:]
        pendingListsCount = 0
        print("🗑️ [ListService] In-memory list cache cleared")
    }

    // MARK: - CoreData Persistence

    /// Save single list to CoreData with sync status
    private func saveListToCoreData(_ list: TaskList, syncStatus: String) async throws {
        try await coreDataManager.saveInBackground { context in
            let cdList = try CDTaskList.fetchById(list.id, context: context) ?? CDTaskList(context: context)
            cdList.id = list.id
            cdList.update(from: list)
            cdList.syncStatus = syncStatus
            if syncStatus == "synced" {
                cdList.lastSyncedAt = Date()
            }
        }
    }

    /// Remove cached lists the server no longer returns (task 53071260).
    ///
    /// Which absences count as deletions is `SyncOrphanPrune`'s decision, not this function's:
    /// a list created offline has never been sent, so it is missing from every response and must
    /// survive. Mirrors `TaskService.saveTasksToCoreData`'s cleanup for tasks.
    private func pruneListsMissingFromServer(serverIds: Set<String>) async throws {
        try await coreDataManager.saveInBackground { context in
            let cdLists = try CDTaskList.fetchAll(context: context)
            let orphans = SyncOrphanPrune.orphanIds(
                cached: cdLists.map { SyncOrphanPrune.Cached(id: $0.id, syncStatus: $0.syncStatus) },
                serverIds: serverIds)
            guard !orphans.isEmpty else { return }
            let doomed = Set(orphans)
            for cdList in cdLists where doomed.contains(cdList.id) {
                context.delete(cdList)
            }
            print("🧹 [ListService] Removed \(orphans.count) lists deleted elsewhere from CoreData")
        }
    }

    /// Delete list from CoreData
    private func deleteListFromCoreData(_ id: String) async throws {
        try await coreDataManager.saveInBackground { context in
            if let cdList = try CDTaskList.fetchById(id, context: context) {
                context.delete(cdList)
            }
        }
    }

    /// Update pending lists count
    private func updatePendingListsCount() {
        do {
            let context = coreDataManager.viewContext
            let request = CDTaskList.fetchRequest()
            request.predicate = NSPredicate(format: "syncStatus == %@", "pending")
            let count = try context.count(for: request)
            pendingListsCount = count
            print("📊 [ListService] Pending lists: \(count)")
        } catch {
            print("❌ [ListService] Failed to count pending lists: \(error)")
        }
    }

    // MARK: - Offline Sync

    /// Sync all pending lists to server
    func syncPendingLists() async throws {
        guard !isSyncingPendingLists else {
            print("⏳ [ListService] Sync already in progress")
            return
        }

        isSyncingPendingLists = true
        defer { isSyncingPendingLists = false }

        print("🔄 [ListService] Starting sync of pending lists...")

        let context = coreDataManager.viewContext

        // Fetch all pending lists
        let request = CDTaskList.fetchRequest()
        request.predicate = NSPredicate(format: "syncStatus == %@", "pending")
        let pendingLists = try context.fetch(request)

        print("📤 [ListService] Found \(pendingLists.count) pending lists")

        var syncedCount = 0
        var failedCount = 0

        for cdList in pendingLists {
            do {
                let list = cdList.toDomainModel()

                // Only create if it's a temp list (hasn't been synced before)
                if list.id.hasPrefix("temp_") {
                    let tempListId = list.id  // Save temp ID before it's replaced

                    let createdList = try await apiClient.createList(
                        name: list.name,
                        description: list.description,
                        color: list.color,
                        privacy: list.privacy?.rawValue ?? "PRIVATE"
                    )

                    // Replace temp list with server list
                    try await deleteListFromCoreData(list.id)
                    try await saveListToCoreData(createdList, syncStatus: "synced")

                    // Update in-memory arrays
                    cachedLists.removeValue(forKey: list.id)
                    cachedLists[createdList.id] = createdList
                    if let index = lists.firstIndex(where: { $0.id == list.id }) {
                        lists[index] = createdList
                    }

                    print("✅ [ListService] Synced list creation: \(createdList.name)")

                    // CRITICAL: Notify TaskService to update any tasks with the temp list ID
                    // This allows tasks created on offline lists to be properly associated
                    await TaskService.shared.onListSynced(tempListId: tempListId, realListId: createdList.id)
                }

                syncedCount += 1
            } catch {
                print("❌ [ListService] Failed to sync list \(cdList.id): \(error)")
                failedCount += 1
                // Mark as failed for retry later
                cdList.syncStatus = "failed"
                try? coreDataManager.save()
            }
        }

        updatePendingListsCount()
        print("✅ [ListService] Sync complete: \(syncedCount) synced, \(failedCount) failed")
    }
}
