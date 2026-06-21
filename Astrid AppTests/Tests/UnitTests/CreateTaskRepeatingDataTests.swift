import XCTest
@testable import Astrid_App

/// Regression tests for the "weekly Monday" NLP bug: `SmartTaskParser` correctly
/// parsed "weekly Monday exercise" into a `.custom` repeating pattern, but the
/// create path (`QuickAddTaskView` → `TaskService.createTask` →
/// `AstridAPIClient.createTask`) dropped `customRepeatingData`, hardcoding
/// `repeatingData: nil` in the wire request. The task was therefore created with a
/// Monday due date but NO recurrence.
///
/// These tests lock the contract that a parsed custom pattern survives into the
/// `CreateTaskRequest` body that is sent to the server. The request builder is
/// extracted from `AstridAPIClient.createTask` so the wire shape is testable
/// without a network round-trip.
final class CreateTaskRepeatingDataTests: XCTestCase {

    /// End-to-end intent: parsing "weekly Monday exercise" and building the create
    /// request must produce a repeating request, not just a due date.
    func testWeeklyMondayParsedPatternReachesCreateRequest() {
        let parsed = SmartTaskParser.parse("weekly Monday exercise", lists: [])

        // Sanity: the parser already gets this right.
        XCTAssertEqual(parsed.repeating, .custom)
        XCTAssertEqual(parsed.customRepeatingData?.weekdays, ["monday"])

        let request = AstridAPIClient.makeCreateTaskRequest(
            title: parsed.title,
            description: nil,
            priority: parsed.priority,
            assigneeId: nil,
            dueDateTimeString: nil,
            isAllDay: true,
            isPrivate: nil,
            repeating: parsed.repeating?.rawValue,
            repeatingData: parsed.customRepeatingData,
            clientRequestId: "test-req-id"
        )

        XCTAssertEqual(request.repeating, "custom",
                       "repeating string must reach the create request")
        XCTAssertEqual(request.repeatingData?.weekdays, ["monday"],
                       "customRepeatingData must reach the create request (was hardcoded nil)")
        XCTAssertEqual(request.repeatingData?.unit, "weeks")
    }

    /// Regression for the hardcoded `repeatingData: nil` — a provided pattern must
    /// not be silently dropped by the builder.
    func testBuilderPreservesProvidedRepeatingData() {
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: 1,
            endCondition: "never",
            weekdays: ["monday", "wednesday", "friday"]
        )

        let request = AstridAPIClient.makeCreateTaskRequest(
            title: "exercise",
            description: nil,
            priority: nil,
            assigneeId: nil,
            dueDateTimeString: nil,
            isAllDay: true,
            isPrivate: nil,
            repeating: "custom",
            repeatingData: pattern,
            clientRequestId: nil
        )

        XCTAssertEqual(request.repeatingData, pattern)
    }

    /// The repeatingData must survive JSON encoding so the server actually receives it.
    func testRepeatingDataEncodesIntoRequestJSON() throws {
        let pattern = CustomRepeatingPattern(
            type: "custom",
            unit: "weeks",
            interval: 1,
            endCondition: "never",
            weekdays: ["monday"]
        )
        let request = AstridAPIClient.makeCreateTaskRequest(
            title: "exercise",
            description: nil,
            priority: nil,
            assigneeId: nil,
            dueDateTimeString: nil,
            isAllDay: true,
            isPrivate: nil,
            repeating: "custom",
            repeatingData: pattern,
            clientRequestId: nil
        )

        let data = try JSONEncoder().encode(request)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"repeatingData\""),
                      "encoded request must carry repeatingData")
        XCTAssertTrue(json.contains("monday"),
                      "encoded repeatingData must include the parsed weekday")
    }

    /// Non-repeating tasks must be unaffected: nil in, nil out.
    func testNilRepeatingDataStaysNil() {
        let request = AstridAPIClient.makeCreateTaskRequest(
            title: "buy milk",
            description: nil,
            priority: nil,
            assigneeId: nil,
            dueDateTimeString: nil,
            isAllDay: false,
            isPrivate: nil,
            repeating: nil,
            repeatingData: nil,
            clientRequestId: nil
        )
        XCTAssertNil(request.repeatingData)
        XCTAssertNil(request.repeating)
    }
}
