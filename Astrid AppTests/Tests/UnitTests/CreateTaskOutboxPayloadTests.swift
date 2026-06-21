import XCTest
@testable import Astrid_App

/// The createTask Outbox payload must round-trip through JSON intact — it's
/// persisted in the journal and replayed (possibly after relaunch), so any
/// dropped field would silently corrupt the retried write.
final class CreateTaskOutboxPayloadTests: XCTestCase {

    func testRoundTripPreservesAllFields() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom", unit: "weeks", interval: 1, endCondition: "never", weekdays: ["monday"]
        )
        let payload = CreateTaskOutboxPayload(
            title: "exercise",
            listIds: ["l1", "l2"],
            description: "desc",
            priority: 2,
            assigneeId: "u1",
            dueDateTime: Date(timeIntervalSince1970: 1_700_000_000),
            isAllDay: true,
            isPrivate: false,
            repeating: "custom",
            repeatingData: pattern
        )

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(CreateTaskOutboxPayload.self, from: data)

        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded.repeatingData?.weekdays, ["monday"])
    }
}
