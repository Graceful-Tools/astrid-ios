import AstridCore
import XCTest

final class CoreRulesTests: XCTestCase {
    private func at(_ text: String) -> Date {
        try! Date.ISO8601FormatStyle().parse(text)
    }

    /// A stand-in for the app's own `Task`: any Encodable in the wire shape crosses the door.
    private struct WireTask: Encodable {
        var id = "t1"
        var repeating: String?
        var repeatFrom: String?
        var dueDateTime: Date?
        var isAllDay = false
        var occurrenceCount: Int?
        var repeatingData: Pattern?
        struct Pattern: Encodable { var endCondition: String; var endAfterOccurrences: Int }
        var completed = false
    }

    func testAOneOffTaskIsJustToggled() throws {
        XCTAssertEqual(
            try CoreRules.completion(of: WireTask(), completed: true, at: at("2026-09-28T12:00:00Z")),
            .toggle(completed: true, clearClosedReason: false))
    }

    func testAWeeklyTaskRollsForwardAWeekAndCountsTheOccurrence() throws {
        let weekly = WireTask(repeating: "weekly", repeatFrom: "DUE_DATE", dueDateTime: at("2026-09-28T09:00:00Z"))
        XCTAssertEqual(
            try CoreRules.completion(of: weekly, completed: true, at: at("2026-09-28T12:00:00Z"),
                                     in: TimeZone(identifier: "UTC")!),
            .rollForward(dueDateTime: at("2026-10-05T09:00:00Z"), isAllDay: false, occurrenceCount: 1))
    }

    func testTheLastOccurrenceEndsTheSeries() throws {
        let limited = WireTask(
            repeating: "daily", repeatFrom: "DUE_DATE", dueDateTime: at("2026-09-28T09:00:00Z"),
            occurrenceCount: 2,
            repeatingData: .init(endCondition: "after_occurrences", endAfterOccurrences: 3))
        XCTAssertEqual(
            try CoreRules.completion(of: limited, completed: true, at: at("2026-09-28T12:00:00Z")),
            .seriesEnded)
    }

    func testAnUnknownRuleIsAFailureNotACrash() {
        struct Nonsense: Encodable { let kind = "somethingLater" }
        XCTAssertThrowsError(try CoreRules.ask(Nonsense(), as: Bool.self)) { error in
            XCTAssertEqual((error as? CoreFailure)?.kind, .badRequest)
        }
    }

    /// The boundary is a JSON encode, a call and a decode per question. A view asks rules while
    /// it draws, so the round trip has to stay far below a frame.
    func testARuleRoundTripIsWellUnderAFrame() throws {
        let weekly = WireTask(repeating: "weekly", repeatFrom: "DUE_DATE", dueDateTime: at("2026-09-28T09:00:00Z"))
        let count = 2_000
        let start = ContinuousClock.now
        for _ in 0..<count {
            _ = try CoreRules.completion(of: weekly, completed: true)
        }
        let perCall = (ContinuousClock.now - start) / count
        print("rule round trip: \(perCall)")
        XCTAssertLessThan(perCall, .milliseconds(1))
    }
}

final class CoreCommandTests: XCTestCase {
    /// Absent leaves a field alone; null clears it. Both have to survive encoding.
    func testAClearedFieldIsNullAndAnUnsetOneIsAbsent() throws {
        var changes = CoreFields()
        changes.set("title", "Buy milk")
        changes.clear("dueDateTime")
        changes.set("priority", Optional<Int>.none)
        let command = CoreCommand(kind: "updateTask", ["taskId": .value("t1"), "changes": .value(changes)])
        let json = try CoreJSON.encode(command)
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        XCTAssertEqual(object["kind"] as? String, "updateTask")
        let sent = object["changes"] as! [String: Any]
        XCTAssertEqual(sent["title"] as? String, "Buy milk")
        XCTAssertTrue(sent["dueDateTime"] is NSNull)
        XCTAssertNil(sent["priority"])
    }
}
