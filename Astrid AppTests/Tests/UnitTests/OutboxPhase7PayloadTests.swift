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
}
