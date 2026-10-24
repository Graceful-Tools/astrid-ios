import XCTest
@testable import Astrid_App

/// CommentService's local-first create, on an in-memory core of its own (AITD-534).
///
/// This used to run against `CommentService.shared` — the process-wide core cache and journal —
/// and clear Core Data's comment table around each test, which CommentService stopped writing
/// when comments moved into astrid-core. It also asserted the create took under a second, which
/// measured the machine. The temp id is the real proof that the write did not wait on a network.
@MainActor
final class CommentServiceIntegrationTests: XCTestCase {

    func testOptimisticCreate_ReturnsTheRowTheViewDraws() async throws {
        let task = TestHelpers.createTestTask(id: "task-123", title: "Discuss")
        let core = try CoreSearchFixture.session(seeding: [task])
        let service = CommentService(core: { core })

        let created = try await service.createComment(taskId: "task-123", content: "Test comment", type: .TEXT)

        XCTAssertTrue(created.id.hasPrefix("temp_"), "the comment the view draws carries a temp id until the server answers")
        XCTAssertEqual(service.cachedComments["task-123"]?.map(\.content), ["Test comment"])
    }
}
