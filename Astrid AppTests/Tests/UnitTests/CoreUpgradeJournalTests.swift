//  CoreUpgradeJournalTests.swift
//  The first launch through astrid-core moves every write still queued in the Swift Outbox
//  (`outbox.json`) into the core's journal (`CoreUpgrade`). A picture queued with its comment or
//  chat message was two entries there — the upload, and the write waiting on it — and must become
//  one core command that carries the file, or the picture is lost on upgrade.

import AstridCore
import XCTest
@testable import Astrid_App

@MainActor
final class CoreUpgradeJournalTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ id: String, kind: String, payload: some Encodable, dependsOn: [String] = []) throws -> OutboxEntry {
        OutboxEntry(id: id, kind: kind, payload: try JSONEncoder().encode(payload),
                    clientRequestId: "crid-\(id)", dependsOn: dependsOn, status: .pending, attempts: 0,
                    nextAttemptAt: t0, lastError: nil, createdAt: t0, updatedAt: t0)
    }

    private func json(_ command: CoreCommand?) throws -> [String: Any] {
        let data = try JSONEncoder().encode(try XCTUnwrap(command))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private var upload: UploadAttachmentOutboxPayload {
        UploadAttachmentOutboxPayload(localPath: "/tmp/temp_file", fileName: "IMG_1.jpg",
                                      mimeType: "image/jpeg", context: ["listId": "l1"])
    }

    func testAQueuedPictureCommentBecomesOneAttachWithItsFile() throws {
        let uploadEntry = try entry("u1", kind: "uploadAttachment", payload: upload)
        let comment = try entry("c1", kind: "createComment", payload: CreateCommentOutboxPayload(
            taskId: "t1", content: "look", type: "ATTACHMENT", parentCommentId: nil, createdAt: t0,
            fileId: "temp_file"), dependsOn: ["u1"])

        let command = try json(CoreUpgrade.importCommand(for: comment, uploads: ["u1": uploadEntry]))
        XCTAssertEqual(command["kind"] as? String, "attachFile")
        XCTAssertEqual(command["path"] as? String, "/tmp/temp_file")
        XCTAssertEqual(command["fileId"] as? String, "temp_file")
        XCTAssertEqual(command["name"] as? String, "IMG_1.jpg")
    }

    func testAQueuedPictureMessageIsSentWithItsFile() throws {
        let uploadEntry = try entry("u1", kind: "uploadAttachment", payload: upload)
        let message = try entry("m1", kind: "sendChatMessage", payload: SendChatMessageOutboxPayload(
            channelId: "c1", content: "", type: "ATTACHMENT", fileId: "temp_file", replyToId: "r1"),
            dependsOn: ["u1"])

        let command = try json(CoreUpgrade.importCommand(for: message, uploads: ["u1": uploadEntry]))
        XCTAssertEqual(command["kind"] as? String, "sendChatMessage")
        XCTAssertEqual(command["channelId"] as? String, "c1")
        XCTAssertEqual(command["type"] as? String, "ATTACHMENT")
        XCTAssertEqual(command["replyToId"] as? String, "r1")
        XCTAssertEqual(command["path"] as? String, "/tmp/temp_file")
        XCTAssertEqual(command["mimeType"] as? String, "image/jpeg")
    }

    func testAQueuedTextMessageMoves() throws {
        let message = try entry("m1", kind: "sendChatMessage", payload: SendChatMessageOutboxPayload(
            channelId: "c1", content: "on my way", type: "TEXT", fileId: nil, replyToId: nil))
        let command = try json(CoreUpgrade.importCommand(for: message))
        XCTAssertEqual(command["content"] as? String, "on my way")
        XCTAssertNil(command["path"])
    }

    // MARK: - What is left behind

    /// An upload whose comment is gone (moved, or never there) has nothing to attach to. Kept, it
    /// held the upgrade open on every launch, and the upgrade never finished.
    func testAnUploadNothingWaitsOnIsNotLeftBehind() throws {
        let orphan = try entry("u1", kind: "uploadAttachment", payload: upload)
        XCTAssertTrue(CoreUpgrade.leftBehind([orphan], consumedUploads: []).isEmpty)
    }

    func testAnUploadAWriteThatStayedWaitsOnIsKeptWithIt() throws {
        let file = try entry("u1", kind: "uploadAttachment", payload: upload)
        let waiting = try entry("x1", kind: "someFutureKind", payload: ["a": "b"], dependsOn: ["u1"])
        let left = CoreUpgrade.leftBehind([file, waiting], consumedUploads: [])
        XCTAssertEqual(left.map(\.id), ["u1", "x1"])
    }

    func testAnUploadAMovedWriteTookIsNotLeftBehind() throws {
        let file = try entry("u1", kind: "uploadAttachment", payload: upload)
        XCTAssertTrue(CoreUpgrade.leftBehind([file], consumedUploads: ["u1"]).isEmpty)
    }

    // MARK: - The core's outbox numbers

    /// `outboxStats` as astrid-core answers it — with fields Swift does not read, and a dead
    /// letter whose error is null. A decode that failed would show the Outbox screen as empty.
    func testJournalStatsReadsTheCoresAnswer() throws {
        let answer = Data("""
        {"pending":2,"running":1,"completed":9,"failed":1,"hasUnsentWork":true,
         "deadLetters":[{"kind":"createTask","error":null,"id":"e1"}]}
        """.utf8)
        let stats = try JSONDecoder().decode(JournalStats.self, from: answer)
        XCTAssertEqual(stats.pending, 2)
        XCTAssertEqual(stats.failed, 1)
        XCTAssertFalse(stats.isHealthy)
        XCTAssertEqual(stats.deadLetters, [JournalStats.DeadLetter(kind: "createTask", error: nil)])
    }
}
