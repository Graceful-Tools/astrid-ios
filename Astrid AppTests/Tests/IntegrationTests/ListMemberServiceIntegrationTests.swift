import XCTest
import CoreData
@testable import Astrid_App

/// Integration tests for ListMemberService local-first functionality
/// Tests offline member management, email-based invitations, and background sync
///
/// NOTE: These tests require dependency injection to work properly.
/// Currently the services use singletons with real implementations.
/// Tests that depend on mocks are skipped until DI is implemented.
@MainActor
final class ListMemberServiceIntegrationTests: XCTestCase {
    var service: ListMemberService!
    var mockAPIClient: MockAPIClient!
    var mockNetworkMonitor: MockNetworkMonitor!
    var coreDataManager: CoreDataManager!

    /// Flag to skip tests that require mock injection (not yet implemented)
    private var skipMockDependentTests: Bool { true }

    override func setUp() async throws {
        coreDataManager = CoreDataManager.shared
        service = ListMemberService.shared

        // NOTE: These mocks are NOT injected into the services - they use real implementations
        mockAPIClient = MockAPIClient()
        mockNetworkMonitor = MockNetworkMonitor()

        try await clearTestData()
    }

    override func tearDown() async throws {
        try await clearTestData()
        mockAPIClient = nil
        mockNetworkMonitor = nil
    }

    // MARK: - Test Helpers

    private func clearTestData() async throws {
        try await coreDataManager.saveInBackground { context in
            let fetchRequest = CDMember.fetchRequest()
            let members = try context.fetch(fetchRequest)
            members.forEach { context.delete($0) }
        }
    }

    // MARK: - Optimistic Add Member Tests

    func testOptimisticAddMember_ReturnsImmediately() async throws {
        // Given: Online mode
        mockNetworkMonitor.simulateOnline()

        // When: Adding a member
        let startTime = Date()
        let addedMember = try await service.addMember(
            listId: "list-123",
            email: "newuser@example.com",
            role: "member"
        )
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should return instantly
        XCTAssertLessThan(elapsed, 0.1, "Optimistic add should be instant")

        // Then: Should have temp ID
        XCTAssertTrue(addedMember.id.hasPrefix("temp_"))
        XCTAssertEqual(addedMember.role, "member")
    }

    func testOptimisticAddMember_SavesToCoreDataAsPending() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Online mode
        mockNetworkMonitor.simulateOnline()

        // When: Adding a member
        let member = try await service.addMember(
            listId: "list-123",
            email: "test@example.com",
            role: "member"
        )

        // Wait for background save
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Then: Should be saved as pending
        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", member.id)
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.count, 1)
        XCTAssertEqual(cdMembers.first?.syncStatus, "pending")
        XCTAssertEqual(cdMembers.first?.pendingOperation, "create")
        XCTAssertEqual(cdMembers.first?.pendingRole, "test@example.com", "Email should be stored for API call")
    }

    // MARK: - Email-Based Invitation Flow Tests

    func testAddMember_HandlesInvitationResponse() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Online mode, API returns invitation (user doesn't exist)
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextMemberInvitation = InvitationData(
            email: "newuser@example.com",
            role: "member",
            status: "pending"
        )

        // When: Adding member and syncing
        _ = try await service.addMember(
            listId: "list-123",
            email: "newuser@example.com",
            role: "member"
        )
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // Then: Should be marked as synced (invitation sent successfully)
        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "listId == %@", "list-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.first?.syncStatus, "synced", "Invitation sent successfully")
    }

    func testAddMember_HandlesMemberResponse() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Online mode, API returns member (user exists)
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextMember = ListMemberData(
            id: "user-real-123",
            name: "John Doe",
            email: "john@example.com",
            image: nil,
            role: "member",
            isOwner: false,
            isAdmin: false
        )

        // When: Adding member and syncing
        _ = try await service.addMember(
            listId: "list-123",
            email: "john@example.com",
            role: "member"
        )
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // Then: Temp ID should be replaced with real user ID
        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "listId == %@", "list-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.first?.id, "user-real-123", "Temp ID replaced with real user ID")
        XCTAssertEqual(cdMembers.first?.userId, "user-real-123")
        XCTAssertEqual(cdMembers.first?.syncStatus, "synced")
    }

    // MARK: - Offline → Online Tests

    func testOfflineAddMember_SyncsWhenOnline() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Offline mode
        mockNetworkMonitor.simulateOffline()

        // When: Adding member offline
        let member = try await service.addMember(
            listId: "list-123",
            email: "offline@example.com",
            role: "member"
        )
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(member.id.hasPrefix("temp_"))
        XCTAssertEqual(service.pendingOperationsCount, 1)

        // Configure API
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextMember = ListMemberData(
            id: "user-456",
            name: "Offline User",
            email: "offline@example.com",
            image: nil,
            role: "member",
            isOwner: false,
            isAdmin: false
        )

        // When: Going online and syncing
        mockNetworkMonitor.simulateOnline()
        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // Then: Should be synced with real ID
        XCTAssertEqual(service.pendingOperationsCount, 0)

        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "listId == %@", "list-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.first?.id, "user-456")
        XCTAssertEqual(cdMembers.first?.syncStatus, "synced")
    }

    // MARK: - Update Role Tests

    func testUpdateMemberRole_UpdatesOptimistically() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Synced member
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextMember = ListMemberData(
            id: "user-123",
            name: "Test User",
            email: "test@example.com",
            image: nil,
            role: "member",
            isOwner: false,
            isAdmin: false
        )

        _ = try await service.addMember(listId: "list-123", email: "test@example.com", role: "member")
        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // When: Updating role
        let startTime = Date()
        try await service.updateMemberRole(listId: "list-123", userId: "user-123", role: "admin")
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should update instantly
        XCTAssertLessThan(elapsed, 0.1)

        // Then: Should be marked as pending_update
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "userId == %@", "user-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.first?.syncStatus, "pending_update")
        XCTAssertEqual(cdMembers.first?.pendingRole, "admin")
    }

    // MARK: - Remove Member Tests

    func testRemoveMember_RemovesOptimistically() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Synced member
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextMember = ListMemberData(
            id: "user-123",
            name: "Test User",
            email: "test@example.com",
            image: nil,
            role: "member",
            isOwner: false,
            isAdmin: false
        )

        _ = try await service.addMember(listId: "list-123", email: "test@example.com", role: "member")
        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // When: Removing member
        let startTime = Date()
        try await service.removeMember(listId: "list-123", userId: "user-123")
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should remove instantly from UI
        XCTAssertLessThan(elapsed, 0.1)

        // Then: Should be marked as pending_delete
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "userId == %@", "user-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.first?.syncStatus, "pending_delete")
    }

    func testRemoveMember_DeletesAfterSync() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Member marked for deletion
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextMember = ListMemberData(
            id: "user-123",
            name: "Test User",
            email: "test@example.com",
            image: nil,
            role: "member",
            isOwner: false,
            isAdmin: false
        )

        _ = try await service.addMember(listId: "list-123", email: "test@example.com", role: "member")
        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        try await service.removeMember(listId: "list-123", userId: "user-123")
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // When: Syncing deletion
        try await service.syncPendingOperations()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // Then: Should be removed from Core Data
        let cdMembers: [CDMember] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDMember.fetchRequest()
                    request.predicate = NSPredicate(format: "userId == %@", "user-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdMembers.count, 0, "Removed member should be deleted from Core Data")
    }

    // MARK: - Cache Tests

    func testLoadFromCache_LoadsImmediately() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Members saved to Core Data
        try await coreDataManager.saveInBackground { context in
            let cdMember = CDMember(context: context)
            cdMember.id = "user-cached"
            cdMember.listId = "list-123"
            cdMember.userId = "user-cached"
            cdMember.role = "member"
            cdMember.syncStatus = "synced"
        }

        // When: Loading from cache
        await service.fetchMembersLocalFirst(listId: "list-123")

        // Then: Should load immediately
        XCTAssertEqual(service.membersByList["list-123"]?.count, 1)
        XCTAssertEqual(service.membersByList["list-123"]?.first?.userId, "user-cached")
    }

    // MARK: - Network Observer Tests

    func testNetworkRestoration_TriggersAutoSync() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Members added offline
        mockNetworkMonitor.simulateOffline()
        _ = try await service.addMember(listId: "list-123", email: "user1@example.com", role: "member")
        _ = try await service.addMember(listId: "list-123", email: "user2@example.com", role: "member")
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(service.pendingOperationsCount, 2)

        // Configure mock API
        mockAPIClient.shouldFailRequests = false

        // When: Network restored
        mockNetworkMonitor.simulateOnline()
        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)

        // Wait for auto-sync
        try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)

        // Then: All members should be synced
        XCTAssertEqual(service.pendingOperationsCount, 0)
    }
}
