import Foundation
import Combine
import CoreData

/// Local-first service for managing list members
/// Implements optimistic updates with background synchronization
/// Follows the same pattern as CommentService (Phase 1)
@MainActor
class ListMemberService: ObservableObject {
    static let shared = ListMemberService()

    // Published state
    @Published var members: [User] = [] // Legacy format for backward compatibility
    @Published var membersByList: [String: [ListMember]] = [:] // New local-first cache
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0

    // Dependencies
    private let apiClient = AstridAPIClient.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    private var networkObserver: NSObjectProtocol?

    private init() {
        setupNetworkObserver()

        _Concurrency.Task {
            await updatePendingOperationsCount()
        }
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                print("🌐 [ListMemberService] Network restored, triggering sync...")
                try? await self?.syncPendingOperations()
            }
        }
    }

    // MARK: - Pending Operations Count

    private func updatePendingOperationsCount() async {
        do {
            let pending: [CDMember] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let items = try CDMember.fetchPending(context: context)
                        continuation.resume(returning: items)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            pendingOperationsCount = pending.count
            print("📊 [ListMemberService] Pending operations: \(pendingOperationsCount)")
        } catch {
            print("❌ [ListMemberService] Failed to count pending operations: \(error)")
        }
    }

    // MARK: - Legacy Fetch (Blocking - for backward compatibility)

    /// Legacy fetch method - loads from server and updates cache
    /// Use fetchMembersLocalFirst() for new code
    func fetchMembers(listId: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            print("📡 [ListMemberService] Fetching members for list: \(listId)")
            let response = try await apiClient.getListMembers(listId: listId)

            // Filter out invite-type entries and deduplicate by ID
            let activeMembers = response.members.filter { $0.type != "invite" }
            var seenIds = Set<String>()
            members = activeMembers.compactMap { memberData -> User? in
                guard seenIds.insert(memberData.id).inserted else {
                    print("⚠️ [ListMemberService] Skipping duplicate member: \(memberData.name ?? "unknown") (id: \(memberData.id))")
                    return nil
                }
                return User(
                    id: memberData.id,
                    email: memberData.email,
                    name: memberData.name,
                    image: memberData.image
                )
            }
            print("👥 [ListMemberService] Members: \(members.map { "\($0.displayName) (id: \($0.id), email: \($0.email ?? "nil"))" })")
            let inviteCount = response.members.filter { $0.type == "invite" }.count
            if inviteCount > 0 {
                print("📨 [ListMemberService] Filtered out \(inviteCount) pending invitations")
            }

            // Convert to ListMember objects (new format)
            let listMembers = response.members.map { memberData in
                ListMember(
                    id: memberData.id,
                    listId: listId,
                    userId: memberData.id,
                    role: memberData.role,
                    createdAt: nil,
                    updatedAt: nil,
                    user: User(
                        id: memberData.id,
                        email: memberData.email,
                        name: memberData.name,
                        image: memberData.image
                    )
                )
            }

            membersByList[listId] = listMembers

            // Save to Core Data cache
            try await saveToCache(listId: listId, members: listMembers)

            print("✅ [ListMemberService] Fetched \(members.count) members")
        } catch {
            print("❌ [ListMemberService] Failed to fetch members: \(error)")
            errorMessage = error.localizedDescription

            // Load from cache on error (offline support)
            await loadFromCache(listId: listId)
            throw error
        }
    }

    // MARK: - Local-First Fetch

    /// Local-first fetch: Returns cached data immediately, syncs in background
    func fetchMembersLocalFirst(listId: String) async {
        print("⚡️ [ListMemberService] Local-first fetch for list: \(listId)")

        // 1. Load from cache immediately
        await loadFromCache(listId: listId)

        // 2. Fetch from server in background (if online)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                do {
                    try await self?.fetchMembers(listId: listId)
                } catch {
                    print("⚠️ [ListMemberService] Background fetch failed (non-critical): \(error)")
                }
            }
        }
    }

    // MARK: - Cache Management

    private func loadFromCache(listId: String) async {
        do {
            let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let request = CDMember.fetchRequest()
                        request.predicate = NSPredicate(format: "listId == %@", listId)
                        let results = try context.fetch(request)
                        continuation.resume(returning: results)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            let listMembers = cdMembers.map { $0.toDomainModel() }
            membersByList[listId] = listMembers

            // Update legacy members array (for backward compatibility)
            members = listMembers.compactMap { $0.user }

            print("✅ [ListMemberService] Loaded \(listMembers.count) members from cache")
        } catch {
            print("❌ [ListMemberService] Failed to load from cache: \(error)")
        }
    }

    private func saveToCache(listId: String, members: [ListMember]) async throws {
        try await coreDataManager.saveInBackground { context in
            // Remove old cached members for this list
            let fetchRequest = CDMember.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "listId == %@", listId)
            let oldMembers = try context.fetch(fetchRequest)
            oldMembers.forEach { context.delete($0) }

            // Save new members
            for member in members {
                let cdMember = CDMember(context: context)
                cdMember.id = member.id
                cdMember.listId = member.listId ?? listId
                cdMember.userId = member.userId
                cdMember.role = member.role
                cdMember.syncStatus = "synced"
                cdMember.lastSyncedAt = Date()
            }
        }

        print("💾 [ListMemberService] Saved \(members.count) members to cache")
    }

    // MARK: - CRUD Operations (Optimistic)

    /// Add a member to a list.
    ///
    /// Semantics match the pre-v1.5.8 direct-API behavior exactly when
    /// online — call the API, return the response. No CoreData
    /// reconciliation dance; the caller's follow-up `fetchLists()` is the
    /// single source of truth for the updated list. When offline, save a
    /// pending CDMember + optimistic in-memory insert so
    /// `syncPendingOperations` can finish the add on reconnect.
    ///
    /// The earlier inline-CDMember variant had two problems:
    ///   1. Trying to update a pending CDMember's `id` and `userId` to the
    ///      server-issued values could conflict with CoreData's identity
    ///      model and surface as a throw *after* the API had already
    ///      succeeded — so the user saw an error even though the add
    ///      landed on the server.
    ///   2. If that reconciliation throw triggered the rollback, the
    ///      pending CDMember was deleted, masking a successful add.
    /// By keeping the online path purely networking, neither scenario is
    /// reachable.
    func addMember(listId: String, email: String, role: String = "member") async throws -> ListMember {
        print("⚡️ [ListMemberService] Adding member: \(email) (online: \(networkMonitor.isConnected))")

        if networkMonitor.isConnected {
            let response = try await apiClient.addListMember(listId: listId, email: email, role: role)

            if let memberData = response.member {
                return ListMember(
                    id: memberData.id,
                    listId: listId,
                    userId: memberData.id,
                    role: memberData.role,
                    createdAt: Date(),
                    updatedAt: Date(),
                    user: User(
                        id: memberData.id,
                        email: memberData.email,
                        name: memberData.name,
                        image: memberData.image
                    )
                )
            }
            // Invitation-only response: server queued an email but the user
            // hasn't joined yet. Return a stub so the caller can dismiss
            // the add-member sheet; fetchLists picks up the real invitation.
            let stubId = "invite_\(UUID().uuidString)"
            return ListMember(
                id: stubId, listId: listId, userId: stubId, role: role,
                createdAt: Date(), updatedAt: Date(),
                user: User(id: stubId, email: email, name: nil, image: nil)
            )
        }

        // Offline: optimistic in-memory insert + pending CDMember so the
        // add survives a relaunch and `syncPendingOperations` can finish
        // it on reconnect.
        let tempId = "temp_\(UUID().uuidString)"
        let optimisticMember = ListMember(
            id: tempId, listId: listId, userId: tempId, role: role,
            createdAt: Date(), updatedAt: Date(),
            user: User(id: tempId, email: email, name: nil, image: nil)
        )
        var currentMembers = membersByList[listId] ?? []
        currentMembers.append(optimisticMember)
        membersByList[listId] = currentMembers
        members = currentMembers.compactMap { $0.user }

        try? await coreDataManager.saveInBackground { context in
            let cdMember = CDMember(context: context)
            cdMember.id = tempId
            cdMember.listId = listId
            cdMember.userId = tempId
            cdMember.role = role
            cdMember.syncStatus = "pending"
            cdMember.pendingOperation = "create"
            cdMember.syncAttempts = 0
            cdMember.pendingRole = email
        }
        await updatePendingOperationsCount()

        return optimisticMember
    }

    /// Update a member's role.
    ///
    /// Online: just call the API and return. The caller's follow-up
    /// `fetchLists()` refreshes the authoritative list.listMembers.
    /// Offline: write a pending CDMember so `syncPendingOperations` can
    /// push the change on reconnect.
    func updateMemberRole(listId: String, userId: String, role: String) async throws {
        print("✏️ [ListMemberService] Updating member role: \(userId) → \(role) (online: \(networkMonitor.isConnected))")

        if networkMonitor.isConnected {
            _ = try await apiClient.updateListMember(listId: listId, userId: userId, role: role)
            return
        }

        // Offline: persist the pending role change.
        try? await coreDataManager.saveInBackground { context in
            guard let cdMember = try CDMember.fetchById(userId, context: context) else { return }
            cdMember.pendingRole = role
            cdMember.syncStatus = "pending_update"
            cdMember.pendingOperation = "update"
            cdMember.syncAttempts = 0
        }
        await updatePendingOperationsCount()
    }

    /// Remove a member from a list.
    ///
    /// Online: just call the API. Offline: mark the CDMember pending_delete
    /// so the removal lands on the server when the network returns.
    func removeMember(listId: String, userId: String) async throws {
        print("🗑️ [ListMemberService] Removing member: \(userId) (online: \(networkMonitor.isConnected))")

        if networkMonitor.isConnected {
            _ = try await apiClient.removeListMember(listId: listId, userId: userId)
            return
        }

        // Offline: mark pending_delete; syncPendingOperations finishes it.
        try? await coreDataManager.saveInBackground { context in
            guard let cdMember = try CDMember.fetchById(userId, context: context) else { return }
            cdMember.syncStatus = "pending_delete"
            cdMember.pendingOperation = "delete"
            cdMember.syncAttempts = 0
        }
        await updatePendingOperationsCount()
    }

    /// Cancel a pending invitation by email (optimistic).
    ///
    /// Invitations live on the `List.invitations` collection, not in CDMember,
    /// so the optimistic update is a cached-list edit rather than a CDMember
    /// pending-op. On network failure the invitation is restored to the list.
    ///
    /// Returns immediately so the view can hide the invitation row without
    /// waiting on the server.
    func cancelInvitation(listId: String, invitationId: String, email: String) async throws {
        print("🗑️ [ListMemberService] Cancelling invitation (optimistic): \(email)")

        // 1. Capture the list snapshot for rollback.
        guard let index = ListService.shared.lists.firstIndex(where: { $0.id == listId }) else {
            // List not cached — just hit the API.
            _ = try await apiClient.cancelInvitation(listId: listId, email: email)
            return
        }
        let originalList = ListService.shared.lists[index]

        // 2. Optimistic update.
        var updatedList = originalList
        updatedList.invitations?.removeAll { $0.id == invitationId }
        ListService.shared.lists[index] = updatedList

        // 3. API call in background; restore on failure.
        do {
            _ = try await apiClient.cancelInvitation(listId: listId, email: email)
            print("✅ [ListMemberService] Invitation cancelled for \(email)")
        } catch {
            print("⚠️ [ListMemberService] Cancel failed, restoring invitation: \(error)")
            if let idx = ListService.shared.lists.firstIndex(where: { $0.id == listId }) {
                ListService.shared.lists[idx] = originalList
            }
            throw error
        }
    }

    // MARK: - Background Sync

    /// Sync all pending member operations with the server
    func syncPendingOperations() async throws {
        guard networkMonitor.isConnected else {
            print("📵 [ListMemberService] Cannot sync - no network")
            return
        }

        print("🔄 [ListMemberService] Starting pending operations sync...")

        // Fetch pending operations
        let pending: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let items = try CDMember.fetchPending(context: context)
                    continuation.resume(returning: items)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        print("📊 [ListMemberService] Found \(pending.count) pending operations")

        // Process each pending operation
        for cdMember in pending {
            let operation = cdMember.pendingOperation ?? "unknown"

            do {
                switch operation {
                case "create":
                    try await syncPendingCreate(cdMember)
                case "update":
                    try await syncPendingUpdate(cdMember)
                case "delete":
                    try await syncPendingDelete(cdMember)
                default:
                    try await markAsFailed(cdMember, error: "Unknown operation: \(operation)")
                }
            } catch {
                print("❌ [ListMemberService] Failed to sync \(operation): \(error)")
                try await markAsFailed(cdMember, error: error.localizedDescription)
            }
        }

        await updatePendingOperationsCount()
        print("✅ [ListMemberService] Sync completed")
    }

    private func syncPendingCreate(_ cdMember: CDMember) async throws {
        print("⚡️ [ListMemberService] Syncing pending create: \(cdMember.id)")

        guard let email = cdMember.pendingRole else {
            throw ListMemberError.missingEmail
        }

        // Call API (email-based invitation)
        let response = try await apiClient.addListMember(
            listId: cdMember.listId,
            email: email,
            role: cdMember.role
        )

        // Update Core Data with server response
        try await coreDataManager.saveInBackground { context in
            guard let member = try CDMember.fetchById(cdMember.id, context: context) else {
                return
            }

            // If member was created (user existed)
            if let memberData = response.member {
                member.id = memberData.id
                member.userId = memberData.id
                member.syncStatus = "synced"
                member.lastSyncedAt = Date()
                member.pendingOperation = nil
                member.pendingRole = nil
                member.syncAttempts = 0
                member.syncError = nil
            } else if response.invitation != nil {
                // Invitation sent (user doesn't exist yet)
                // Keep as pending until user accepts
                member.syncStatus = "synced" // Invitation successfully sent
                member.lastSyncedAt = Date()
                member.pendingOperation = nil
                member.syncAttempts = 0
            }
        }

        print("✅ [ListMemberService] Marked as synced")
    }

    private func syncPendingUpdate(_ cdMember: CDMember) async throws {
        print("⚡️ [ListMemberService] Syncing pending update: \(cdMember.id)")

        guard let newRole = cdMember.pendingRole else {
            throw ListMemberError.missingRole
        }

        // Call API
        let response = try await apiClient.updateListMember(
            listId: cdMember.listId,
            userId: cdMember.userId,
            role: newRole
        )

        // Update Core Data
        try await coreDataManager.saveInBackground { context in
            guard let member = try CDMember.fetchById(cdMember.id, context: context) else {
                return
            }

            member.role = response.member.role
            member.syncStatus = "synced"
            member.lastSyncedAt = Date()
            member.pendingOperation = nil
            member.pendingRole = nil
            member.syncAttempts = 0
            member.syncError = nil
        }

        print("✅ [ListMemberService] Update synced")
    }

    private func syncPendingDelete(_ cdMember: CDMember) async throws {
        print("⚡️ [ListMemberService] Syncing pending delete: \(cdMember.id)")

        // Call API
        _ = try await apiClient.removeListMember(
            listId: cdMember.listId,
            userId: cdMember.userId
        )

        // Remove from Core Data
        try await coreDataManager.saveInBackground { context in
            guard let member = try CDMember.fetchById(cdMember.id, context: context) else {
                return
            }

            context.delete(member)
        }

        print("✅ [ListMemberService] Delete synced and removed from cache")
    }

    private func markAsFailed(_ cdMember: CDMember, error: String) async throws {
        try await coreDataManager.saveInBackground { context in
            guard let member = try CDMember.fetchById(cdMember.id, context: context) else {
                return
            }

            member.syncStatus = "failed"
            member.syncAttempts += 1
            member.syncError = error

            // Give up after 3 attempts
            if member.syncAttempts >= 3 {
                print("🛑 [ListMemberService] Giving up after 3 attempts: \(cdMember.id)")
            }
        }
    }

    // MARK: - Legacy Methods

    func getMember(id: String) -> User? {
        return members.first { $0.id == id }
    }

    /// Retry all failed operations
    func retryFailedOperations() async {
        print("🔄 [ListMemberService] Retrying failed operations...")

        do {
            try await coreDataManager.saveInBackground { context in
                let request = CDMember.fetchRequest()
                request.predicate = NSPredicate(format: "syncStatus == %@", "failed")
                let failedMembers = try context.fetch(request)
                for member in failedMembers {
                    member.syncAttempts = 0
                    member.syncStatus = "pending"
                    member.syncError = nil
                }
                print("📊 [ListMemberService] Reset \(failedMembers.count) failed members to pending")
            }

            // Trigger sync
            try await syncPendingOperations()
        } catch {
            print("❌ [ListMemberService] Failed to retry operations: \(error)")
        }
    }
}

// MARK: - Errors

enum ListMemberError: LocalizedError {
    case missingEmail
    case missingRole

    var errorDescription: String? {
        switch self {
        case .missingEmail:
            return "Email is required for adding member"
        case .missingRole:
            return "Role is required for updating member"
        }
    }
}
