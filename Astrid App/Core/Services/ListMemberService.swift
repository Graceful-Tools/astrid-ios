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

            // Convert to User objects (legacy format)
            members = response.members.map { memberData in
                User(
                    id: memberData.id,
                    email: memberData.email,
                    name: memberData.name,
                    image: memberData.image
                )
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

    /// Add a member to a list (optimistic)
    /// Returns immediately with optimistic member, syncs in background
    func addMember(listId: String, email: String, role: String = "member") async throws -> ListMember {
        print("⚡️ [ListMemberService] Adding member (optimistic): \(email)")

        // 1. Generate temp ID for optimistic member
        let tempId = "temp_\(UUID().uuidString)"

        // 2. Create optimistic member (without user info yet)
        let optimisticMember = ListMember(
            id: tempId,
            listId: listId,
            userId: tempId, // Will be replaced after server response
            role: role,
            createdAt: Date(),
            updatedAt: Date(),
            user: User(id: tempId, email: email, name: nil, image: nil)
        )

        // 3. Update UI immediately
        var currentMembers = membersByList[listId] ?? []
        currentMembers.append(optimisticMember)
        membersByList[listId] = currentMembers
        members = currentMembers.compactMap { $0.user }

        // 4. Save to Core Data as "pending"
        _Concurrency.Task.detached { [weak self] in
            do {
                try await self?.coreDataManager.saveInBackground { context in
                    let cdMember = CDMember(context: context)
                    cdMember.id = tempId
                    cdMember.listId = listId
                    cdMember.userId = tempId
                    cdMember.role = role
                    cdMember.syncStatus = "pending"
                    cdMember.pendingOperation = "create"
                    cdMember.syncAttempts = 0
                    // Store email for sync (we'll need it for API call)
                    cdMember.pendingRole = email // Temporary storage of email
                }

                await self?.updatePendingOperationsCount()
            } catch {
                print("⚠️ [ListMemberService] Failed to save pending member: \(error)")
            }
        }

        // 5. Trigger background sync
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingOperations()
            }
        }

        return optimisticMember
    }

    /// Update a member's role (optimistic)
    func updateMemberRole(listId: String, userId: String, role: String) async throws {
        print("✏️ [ListMemberService] Updating member role (optimistic): \(userId) → \(role)")

        // 1. Update in-memory immediately
        if var currentMembers = membersByList[listId] {
            if let index = currentMembers.firstIndex(where: { $0.userId == userId }) {
                // Create new member with updated role
                let oldMember = currentMembers[index]
                let updatedMember = ListMember(
                    id: oldMember.id,
                    listId: oldMember.listId,
                    userId: oldMember.userId,
                    role: role, // New role
                    createdAt: oldMember.createdAt,
                    updatedAt: Date(),
                    user: oldMember.user
                )
                currentMembers[index] = updatedMember
                membersByList[listId] = currentMembers
            }
        }

        // 2. Save pending update to Core Data
        _Concurrency.Task.detached { [weak self] in
            do {
                try await self?.coreDataManager.saveInBackground { context in
                    guard let cdMember = try CDMember.fetchById(userId, context: context) else {
                        return
                    }

                    cdMember.pendingRole = role
                    cdMember.syncStatus = "pending_update"
                    cdMember.pendingOperation = "update"
                    cdMember.syncAttempts = 0
                }

                await self?.updatePendingOperationsCount()
            } catch {
                print("⚠️ [ListMemberService] Failed to save pending update: \(error)")
            }
        }

        // 3. Trigger background sync
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingOperations()
            }
        }
    }

    /// Remove a member from a list (optimistic)
    func removeMember(listId: String, userId: String) async throws {
        print("🗑️ [ListMemberService] Removing member (optimistic): \(userId)")

        // 1. Remove from UI immediately
        if var currentMembers = membersByList[listId] {
            currentMembers.removeAll { $0.userId == userId }
            membersByList[listId] = currentMembers
            members = currentMembers.compactMap { $0.user }
        }

        // 2. Mark as pending delete in Core Data
        _Concurrency.Task.detached { [weak self] in
            do {
                try await self?.coreDataManager.saveInBackground { context in
                    guard let cdMember = try CDMember.fetchById(userId, context: context) else {
                        return
                    }

                    cdMember.syncStatus = "pending_delete"
                    cdMember.pendingOperation = "delete"
                    cdMember.syncAttempts = 0
                }

                await self?.updatePendingOperationsCount()
            } catch {
                print("⚠️ [ListMemberService] Failed to mark for deletion: \(error)")
            }
        }

        // 3. Trigger background sync
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingOperations()
            }
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
