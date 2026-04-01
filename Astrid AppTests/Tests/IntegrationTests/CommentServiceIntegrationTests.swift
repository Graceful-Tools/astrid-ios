import XCTest
import CoreData
@testable import Astrid_App

/// Integration tests for CommentService local-first functionality
/// Tests offline → online flows, optimistic updates, and background sync
///
/// NOTE: These tests require dependency injection to work properly.
/// Currently the services use singletons with real implementations.
/// Tests that depend on mocks are skipped until DI is implemented.
@MainActor
final class CommentServiceIntegrationTests: XCTestCase {
    var service: CommentService!
    var mockAPIClient: MockAPIClient!
    var mockNetworkMonitor: MockNetworkMonitor!
    var coreDataManager: CoreDataManager!

    /// Flag to skip tests that require mock injection (not yet implemented)
    private var skipMockDependentTests: Bool { true }

    override func setUp() async throws {
        // Setup test environment
        coreDataManager = CoreDataManager.shared
        service = CommentService.shared

        // Use mock clients for testing
        // NOTE: These mocks are NOT injected into the services - they use real implementations
        mockAPIClient = MockAPIClient()
        mockNetworkMonitor = MockNetworkMonitor()

        // Clear any existing data
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
            let fetchRequest = CDComment.fetchRequest()
            let comments = try context.fetch(fetchRequest)
            comments.forEach { context.delete($0) }
        }
    }

    // MARK: - Optimistic Create Tests

    func testOptimisticCreate_ReturnsImmediately() async throws {
        // Given: Network is online
        mockNetworkMonitor.simulateOnline()

        // When: Creating a comment
        let startTime = Date()
        let createdComment = try await service.createComment(
            taskId: "task-123",
            content: "Test comment",
            type: .TEXT
        )
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should return instantly (< 100ms)
        XCTAssertLessThan(elapsed, 0.1, "Optimistic create should be instant")

        // Then: Should have temp ID indicating optimistic creation
        XCTAssertTrue(createdComment.id.hasPrefix("temp_"), "Comment should have temp ID")
    }

    func testOptimisticCreate_SavesToCoreDataAsPending() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Online mode
        mockNetworkMonitor.simulateOnline()

        // When: Creating a comment
        let comment = try await service.createComment(
            taskId: "task-123",
            content: "Test comment",
            type: .TEXT
        )

        // Wait for background save
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // Then: Should be saved to Core Data
        let cdComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDComment.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", comment.id)
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdComments.count, 1, "Comment should be saved to Core Data")
        XCTAssertEqual(cdComments.first?.syncStatus, "pending")
        XCTAssertEqual(cdComments.first?.pendingOperation, "create")
    }

    // MARK: - Offline → Online Sync Tests

    func testOfflineCreate_SyncsWhenOnline() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Offline mode
        mockNetworkMonitor.simulateOffline()

        // When: Creating a comment offline
        let comment = try await service.createComment(
            taskId: "task-123",
            content: "Offline comment",
            type: .TEXT
        )

        let tempId = comment.id
        XCTAssertTrue(tempId.hasPrefix("temp_"))

        // Wait for background save
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Configure mock API to return real ID
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextCommentId = "comment-real-123"

        // When: Going online and syncing
        mockNetworkMonitor.simulateOnline()

        // Manually trigger sync (simulating SyncManager or network observer)
        try await service.syncPendingComments()

        // Wait for sync to complete
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1s

        // Then: Temp ID should be replaced with real ID
        let cdComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDComment.fetchRequest()
                    request.predicate = NSPredicate(format: "taskId == %@", "task-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdComments.count, 1)
        XCTAssertEqual(cdComments.first?.id, "comment-real-123", "Temp ID should be replaced")
        XCTAssertEqual(cdComments.first?.syncStatus, "synced")
        XCTAssertNil(cdComments.first?.pendingOperation)
    }

    func testPendingOperationsCount_TracksCorrectly() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Offline mode
        mockNetworkMonitor.simulateOffline()

        // When: Creating multiple comments offline
        _ = try await service.createComment(taskId: "task-1", content: "Comment 1", type: .TEXT)
        _ = try await service.createComment(taskId: "task-1", content: "Comment 2", type: .TEXT)
        _ = try await service.createComment(taskId: "task-2", content: "Comment 3", type: .TEXT)

        // Wait for background saves
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000) // 1s

        // Then: Pending count should be 3
        XCTAssertEqual(service.pendingOperationsCount, 3)
    }

    // MARK: - Retry Logic Tests

    func testSyncRetry_RetriesUpTo3Times() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Comment in pending state
        mockNetworkMonitor.simulateOffline()
        let comment = try await service.createComment(
            taskId: "task-123",
            content: "Test",
            type: .TEXT
        )
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Given: API configured to fail
        mockAPIClient.shouldFailRequests = true
        mockNetworkMonitor.simulateOnline()

        // When: Attempting to sync 3 times
        for attempt in 1...3 {
            try await service.syncPendingComments()
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

            // Check attempt count
            let cdComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let request = CDComment.fetchRequest()
                        request.predicate = NSPredicate(format: "id == %@", comment.id)
                        let results = try context.fetch(request)
                        continuation.resume(returning: results)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            XCTAssertEqual(cdComments.first?.syncAttempts, Int16(attempt))
        }

        // Then: After 3 attempts, should be marked as failed
        let finalComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDComment.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", comment.id)
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(finalComments.first?.syncStatus, "failed")
        XCTAssertEqual(finalComments.first?.syncAttempts, 3)
    }

    // MARK: - Update Tests

    func testOptimisticUpdate_UpdatesImmediately() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Synced comment
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextCommentId = "comment-123"

        _ = try await service.createComment(
            taskId: "task-123",
            content: "Original",
            type: .TEXT
        )
        try await service.syncPendingComments()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // When: Updating comment
        let startTime = Date()
        _ = try await service.updateComment(id: "comment-123", content: "Updated")
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should update instantly
        XCTAssertLessThan(elapsed, 0.1)

        // Then: Should be marked as pending_update
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        let cdComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDComment.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", "comment-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdComments.first?.syncStatus, "pending_update")
        XCTAssertEqual(cdComments.first?.pendingContent, "Updated")
    }

    // MARK: - Delete Tests

    func testOptimisticDelete_RemovesImmediately() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Synced comment
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextCommentId = "comment-123"

        _ = try await service.createComment(
            taskId: "task-123",
            content: "To delete",
            type: .TEXT
        )
        try await service.syncPendingComments()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // When: Deleting comment
        let startTime = Date()
        try await service.deleteComment(id: "comment-123")
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should delete instantly from UI
        XCTAssertLessThan(elapsed, 0.1)

        // Then: Should be marked as pending_delete in Core Data
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        let cdComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDComment.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", "comment-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdComments.first?.syncStatus, "pending_delete")
    }

    func testDelete_RemovesFromCoreDataAfterSync() async throws {
        // Given: Comment marked for deletion
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false
        mockAPIClient.nextCommentId = "comment-123"

        _ = try await service.createComment(
            taskId: "task-123",
            content: "To delete",
            type: .TEXT
        )
        try await service.syncPendingComments()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        try await service.deleteComment(id: "comment-123")
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // When: Syncing deletion
        try await service.syncPendingComments()
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // Then: Should be completely removed from Core Data
        let cdComments: [CDComment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let request = CDComment.fetchRequest()
                    request.predicate = NSPredicate(format: "id == %@", "comment-123")
                    let results = try context.fetch(request)
                    continuation.resume(returning: results)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        XCTAssertEqual(cdComments.count, 0, "Deleted comment should be removed from Core Data")
    }

    // MARK: - Network Observer Tests

    func testNetworkRestoration_TriggersAutoSync() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Comments created offline
        mockNetworkMonitor.simulateOffline()
        _ = try await service.createComment(taskId: "task-1", content: "Offline 1", type: .TEXT)
        _ = try await service.createComment(taskId: "task-1", content: "Offline 2", type: .TEXT)
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        XCTAssertEqual(service.pendingOperationsCount, 2)

        // Configure mock API
        mockAPIClient.shouldFailRequests = false

        // When: Network restored (simulates NotificationCenter post)
        mockNetworkMonitor.simulateOnline()
        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)

        // Wait for auto-sync to complete
        try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000) // 2s

        // Then: All comments should be synced
        XCTAssertEqual(service.pendingOperationsCount, 0, "All pending operations should be synced")
    }
}
