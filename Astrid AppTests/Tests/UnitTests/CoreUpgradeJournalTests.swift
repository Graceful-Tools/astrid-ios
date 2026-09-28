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
}
