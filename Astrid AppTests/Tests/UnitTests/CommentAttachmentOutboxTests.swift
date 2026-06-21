import XCTest
@testable import Astrid_App

/// Tests the pure pieces of the comment-with-attachment Outbox migration: the
/// id resolver (real task id + uploaded fileId come from dependency outputs) and
/// the payload codecs (journal entries replay intact after relaunch).
final class CommentAttachmentOutboxTests: XCTestCase {

    private func context(_ outputs: [String: [String: String]]) -> OutboxContext {
        OutboxContext(dependencyOutputs: outputs)
    }

    // MARK: - Resolver

    func testUsesDependencyTaskIdOverTempPayloadId() {
        let resolved = CommentOutboxResolver.resolve(
            payloadTaskId: "temp_123",
            context: context(["taskDep": ["taskId": "real-task"]])
        )
        XCTAssertEqual(resolved.taskId, "real-task")
        XCTAssertFalse(resolved.taskUnresolved)
    }

    func testReadsFileIdFromUploadDependency() {
        let resolved = CommentOutboxResolver.resolve(
            payloadTaskId: "real-task",
            context: context(["uploadDep": ["fileId": "file-9"]])
        )
        XCTAssertEqual(resolved.fileId, "file-9")
    }

    func testTempTaskWithNoDependencyIsUnresolved() {
        let resolved = CommentOutboxResolver.resolve(payloadTaskId: "temp_x", context: context([:]))
        XCTAssertTrue(resolved.taskUnresolved, "must wait, not POST to a temp task id")
        XCTAssertNil(resolved.fileId)
    }

    func testRealTaskWithNoDependenciesPassesThrough() {
        let resolved = CommentOutboxResolver.resolve(payloadTaskId: "real-1", context: context([:]))
        XCTAssertEqual(resolved.taskId, "real-1")
        XCTAssertFalse(resolved.taskUnresolved)
        XCTAssertNil(resolved.fileId)
    }

    // MARK: - Payload round-trips

    func testCommentPayloadRoundTrips() throws {
        let p = CreateCommentOutboxPayload(
            taskId: "temp_1", content: "hi", type: "ATTACHMENT",
            parentCommentId: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let decoded = try JSONDecoder().decode(
            CreateCommentOutboxPayload.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    func testAttachmentPayloadRoundTrips() throws {
        let p = UploadAttachmentOutboxPayload(
            localPath: "/tmp/x.jpg", fileName: "x.jpg", mimeType: "image/jpeg",
            context: ["taskId": "temp_1"]
        )
        let decoded = try JSONDecoder().decode(
            UploadAttachmentOutboxPayload.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }
}
