//  CommentServiceWritePathTests.swift
//  CommentService's writes against the unit host's in-memory astrid-core (AITD-535): a post, an
//  edit, a delete, the attach chain a staged photo takes, and the outbox counts the thread's
//  banner shows. Nothing reaches a server; each write lands in the core's cache and journal.
//
//  The service is built on its own AttachmentService, on a temp directory and defaults suite, so
//  staging a file never touches the shared one or `UserDefaults.standard`.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class CommentServiceWritePathTests: XCTestCase {
    private var attachments: AttachmentService!
    private var service: CommentService!
    private var caches: URL!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        caches = FileManager.default.temporaryDirectory
            .appendingPathComponent("CommentServiceWritePathTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        suiteName = "CommentServiceWritePathTests-\(UUID().uuidString)"
        attachments = AttachmentService(session: StubURLProtocol.session(), cachesDirectory: caches,
                                        defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
        service = CommentService(attachments: attachments)
    }

    override func tearDown() async throws {
        service = nil
        attachments = nil
        try? FileManager.default.removeItem(at: caches)
        UserDefaults().removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeTask() async throws -> String {
        try await TaskService.shared.createTask(listIds: [], title: "Comments \(UUID().uuidString)").id
    }

    // MARK: Post

    func testAPostLandsInTheTaskBucketUnderTheRowIdTheViewDrew_AITD535() async throws {
        let taskId = try await makeTask()

        let posted = try await service.createComment(taskId: taskId, content: "First", clientRequestId: "temp_row-1")

        XCTAssertEqual(posted.id, "temp_row-1", "until the server answers, the comment keeps the drawn row's id")
        XCTAssertEqual(posted.content, "First")
        XCTAssertEqual(posted.taskId, taskId)
        XCTAssertEqual(service.cachedComments[taskId]?.map(\.id), ["temp_row-1"])
    }

    func testPostingTheSameRowTwiceKeepsOneCopyInTheBucket_AITD535() async throws {
        let taskId = try await makeTask()

        _ = try await service.createComment(taskId: taskId, content: "Once", clientRequestId: "temp_row-2")
        _ = try await service.createComment(taskId: taskId, content: "Once", clientRequestId: "temp_row-2")

        XCTAssertEqual(service.cachedComments[taskId]?.map(\.id), ["temp_row-2"])
    }

    func testAReplyCarriesItsParent_AITD535() async throws {
        let taskId = try await makeTask()
        let parent = try await service.createComment(taskId: taskId, content: "Parent")

        let reply = try await service.createComment(taskId: taskId, content: "Reply", parentCommentId: parent.id)

        XCTAssertEqual(reply.parentCommentId, parent.id)
        XCTAssertEqual(service.cachedComments[taskId]?.map(\.id), [parent.id, reply.id])
    }

    // MARK: Edit and delete

    func testAnEditChangesTheCommentInTheBucket_AITD535() async throws {
        let taskId = try await makeTask()
        let posted = try await service.createComment(taskId: taskId, content: "Before")

        let edited = try await service.updateComment(id: posted.id, content: "After")

        XCTAssertEqual(edited.content, "After")
        XCTAssertNotNil(edited.updatedAt)
        XCTAssertEqual(service.cachedComments[taskId]?.first?.content, "After")
    }

    func testEditingACommentNoBucketHoldsThrows_AITD535() async throws {
        let taskId = try await makeTask()
        let posted = try await service.createComment(taskId: taskId, content: "Held elsewhere")
        service.clearCache()

        do {
            _ = try await service.updateComment(id: posted.id, content: "Lost")
            XCTFail("an edit with no row to update must say so")
        } catch {
        }
    }

    func testADeleteRemovesTheCommentFromTheBucket_AITD535() async throws {
        let taskId = try await makeTask()
        let keep = try await service.createComment(taskId: taskId, content: "Keep")
        let drop = try await service.createComment(taskId: taskId, content: "Drop")

        try await service.deleteComment(id: drop.id)

        XCTAssertEqual(service.cachedComments[taskId]?.map(\.id), [keep.id])
    }

    // MARK: The attach chain

    /// A staged file goes as one `attachFile` — the core copies the bytes, uploads them and posts
    /// the comment once the upload answers — rather than a post naming a file the server never got.
    func testAStagedFileIsAttachedThroughTheCoreNotPostedByTempId_AITD535() async throws {
        let taskId = try await makeTask()
        let tempId = attachments.saveLocallyAndUploadAsync(
            fileData: Data("receipt".utf8), fileName: "receipt.txt", mimeType: "text/plain",
            context: ["taskId": taskId])

        let before = try await queuedWrites()

        let posted = try await service.createComment(
            taskId: taskId, content: "See attached", fileId: tempId, clientRequestId: "temp_row-3")

        XCTAssertEqual(posted.id, "temp_row-3")
        XCTAssertEqual(service.cachedComments[taskId]?.map(\.id), ["temp_row-3"])
        let added = try await queuedWrites() - before
        XCTAssertEqual(added, 2, "the upload and the comment that waits on it are both journaled")
    }

    // MARK: Outbox counts

    func testShowOutboxCountsPublishesWhatTheCoreGave_AITD535() {
        service.showOutboxCounts(pending: 3, failed: 1)

        XCTAssertEqual(service.pendingOperationsCount, 3)
        XCTAssertEqual(service.failedOperationsCount, 1)
    }

    func testAWriteRefreshesThePendingCountFromTheCore_AITD535() async throws {
        let taskId = try await makeTask()

        _ = try await service.createComment(taskId: taskId, content: "Queued")

        let deadline = Date().addingTimeInterval(5)
        while service.pendingOperationsCount == 0, Date() < deadline {
            try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(service.pendingOperationsCount, 0, "a write the server has not taken is counted")
    }

    func testClearCacheEmptiesWhatTheViewsRead_AITD535() async throws {
        let taskId = try await makeTask()
        _ = try await service.createComment(taskId: taskId, content: "Gone on sign-out")
        service.typingAgent[taskId] = "claude"

        service.clearCache()

        XCTAssertTrue(service.cachedComments.isEmpty)
        XCTAssertTrue(service.typingAgent.isEmpty)
    }

    private struct OutboxStats: Decodable { let pending: Int; let running: Int; let failed: Int }

    /// Writes the shared core holds and has not delivered — read before and after, since other
    /// tests in the host journal into the same core.
    private func queuedWrites() async throws -> Int {
        let stats = try await AppCore.shared.session.run(CoreCommand(kind: "outboxStats"), as: OutboxStats.self)
        return stats.pending + stats.running + stats.failed
    }
}
