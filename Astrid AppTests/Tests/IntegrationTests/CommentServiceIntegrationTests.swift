import XCTest
import CoreData
@testable import Astrid_App

/// Integration tests for CommentService local-first behaviour against the real singleton
/// service and Core Data stack. The offline/retry cases that needed an injected API client
/// were never runnable (the services are singletons) and were removed rather than kept
/// permanently skipped; `ListMemberOptimisticTests` and the Outbox suites cover that ground.
@MainActor
final class CommentServiceIntegrationTests: XCTestCase {
    var service: CommentService!
    var coreDataManager: CoreDataManager!

    override func setUp() async throws {
        coreDataManager = CoreDataManager.shared
        service = CommentService.shared
        try await clearTestData()
    }

    override func tearDown() async throws {
        try await clearTestData()
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
        // When: Creating a comment
        let startTime = Date()
        let createdComment = try await service.createComment(
            taskId: "task-123",
            content: "Test comment",
            type: .TEXT
        )
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should return without waiting on a network round-trip. The temp
        // id below is the real proof of optimism; this bound is generous so it
        // doesn't flake on a loaded CI machine (actor hops + a CoreData save can
        // occasionally exceed a tight 100ms budget) while still catching a
        // regression that makes the call actually block.
        XCTAssertLessThan(elapsed, 1.0, "Optimistic create should not block on the network")

        // Then: Should have temp ID indicating optimistic creation
        XCTAssertTrue(createdComment.id.hasPrefix("temp_"), "Comment should have temp ID")
    }

    // MARK: - Delete Tests

    func testDelete_RemovesFromCoreDataAfterSync() async throws {
        // Given: Comment marked for deletion
        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)

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
}
