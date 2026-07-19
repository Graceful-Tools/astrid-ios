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
    private var syncTimer: Timer?
    private var networkObserver: NSObjectProtocol?

    private init() {
        setupNetworkObserver()
        startBackgroundSync()

        // Load cached lists synchronously to ensure data is available before any UI renders
        // This is CRITICAL for offline mode - lists must be in memory before network calls fail
        loadCachedLists()
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
            lists = lists.sorted { list1, list2 in
                let fav1 = list1.isFavorite ?? false
                let fav2 = list2.isFavorite ?? false
                if fav1 != fav2 {
                    return fav1
                }
                return list1.name.localizedCaseInsensitiveCompare(list2.name) == .orderedAscending
            }

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

    func fetchLists() async throws -> [TaskList] {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            print("📡 [ListService] Calling apiClient.getLists()...")
            let fetchedLists = try await apiClient.getLists()
            print("📡 [ListService] Response received with \(fetchedLists.count) lists")

            // Merge with pending lists (temp_ IDs not synced yet)
            let pendingLists = self.lists.filter { $0.id.hasPrefix("temp_") }
            // Never resurrect a deleted list from a stale in-flight response.
            let deletedIds = recentlyDeletedListIds
            let liveLists = deletedIds.isEmpty ? fetchedLists : fetchedLists.filter { !deletedIds.contains($0.id) }
            var mergedLists = liveLists.sorted { list1, list2 in
                // Favorites first, then alphabetical
                let fav1 = list1.isFavorite ?? false
                let fav2 = list2.isFavorite ?? false

                if fav1 != fav2 {
                    return fav1
                }
                return list1.name.localizedCaseInsensitiveCompare(list2.name) == .orderedAscending
            }

            // Add pending lists at the top
            for pendingList in pendingLists {
                if !mergedLists.contains(where: { $0.id == pendingList.id }) {
                    mergedLists.insert(pendingList, at: 0)
                }
            }

            self.lists = mergedLists

            // Cache lists
            for list in self.lists {
                cachedLists[list.id] = list
                print("  📋 List: \(list.name) (tasks: \(list.taskCount ?? 0))")
                print("    👥 Owner: \(list.owner?.displayName ?? "nil")")
                print("    👥 Admins: \(list.admins?.count ?? 0)")
                print("    👥 Members: \(list.members?.count ?? 0)")
            }

            // Save lists to CoreData for offline support
            _Concurrency.Task.detached { [weak self] in
                guard let self = self else { return }
                for list in fetchedLists {
                    do {
                        try await self.saveListToCoreData(list, syncStatus: "synced")
                    } catch {
                        print("⚠️ [ListService] Failed to cache list to CoreData: \(error)")
                    }
                }
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

    /// Remove a member from the cached list so the change persists across view dismissals.
    /// Called after optimistic removal in the UI — reverted if the API call fails.
    func removeMemberFromCachedList(listId: String, userId: String) {
        if let index = lists.firstIndex(where: { $0.id == listId }) {
            lists[index].admins?.removeAll { $0.id == userId }
            lists[index].members?.removeAll { $0.id == userId }
            lists[index].listMembers?.removeAll { $0.userId == userId || $0.user?.id == userId }
            cachedLists[listId] = lists[index]
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
        lists = lists.sorted { list1, list2 in
            let fav1 = list1.isFavorite ?? false
            let fav2 = list2.isFavorite ?? false
            if fav1 != fav2 {
                return fav1
            }
            return list1.name.localizedCaseInsensitiveCompare(list2.name) == .orderedAscending
        }

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
            lists = lists.sorted { list1, list2 in
                let fav1 = list1.isFavorite ?? false
                let fav2 = list2.isFavorite ?? false
                if fav1 != fav2 {
                    return fav1
                }
                return list1.name.localizedCaseInsensitiveCompare(list2.name) == .orderedAscending
            }

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
