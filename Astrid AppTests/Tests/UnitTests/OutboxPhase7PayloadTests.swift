import XCTest
@testable import Astrid_App

/// Round-trip coverage for the Phase 7 dual-write payloads (chat + updateTask).
/// They're persisted in the journal and replayed (possibly after relaunch), so a
/// dropped field would corrupt the retried write.
final class OutboxPhase7PayloadTests: XCTestCase {

    func testChatPayloadRoundTrips() throws {
        let p = SendChatMessageOutboxPayload(
            channelId: "chan-1", content: "hello", type: "TEXT",
            fileId: "temp_file", replyToId: "msg-9"
        )
        let decoded = try JSONDecoder().decode(
            SendChatMessageOutboxPayload.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(decoded, p)
    }

    func testUpdateTaskPayloadRoundTripsAndPreservesOnlySetFields() throws {
        // Only `completed` + `priority` set — the encoder must emit just those.
        let updates = UpdateTaskRequest(priority: 3, completed: true)
        let p = UpdateTaskOutboxPayload(taskId: "temp_1", updates: updates)

        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(UpdateTaskOutboxPayload.self, from: data)

        XCTAssertEqual(decoded.taskId, "temp_1")
        XCTAssertEqual(decoded.updates, updates, "the update body must replay identically")

        // The replayed body must not invent fields the caller didn't set.
        let bodyJSON = String(decoding: try JSONEncoder().encode(decoded.updates), as: UTF8.self)
        XCTAssertTrue(bodyJSON.contains("\"completed\""))
        XCTAssertTrue(bodyJSON.contains("\"priority\""))
        XCTAssertFalse(bodyJSON.contains("\"title\""), "unset fields must not appear in the PUT body")
    }
}
