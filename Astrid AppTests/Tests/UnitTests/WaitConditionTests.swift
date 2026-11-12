import AstridCore
import XCTest
@testable import Astrid_App

/// AITD-631 — Waiting needs a date or a task (Jon, 2026-11-12; astrid-core `waiting.rs`).
///
/// A move into Waiting with no condition is refused by the core with `WAITING_NEEDS_CONDITION`
/// and writes nothing. The app asks "until when, or on what?" and sends the same move again with
/// the answer. Cancel leaves the task where it was.
@MainActor
final class WaitConditionTests: XCTestCase {

    private func json(_ command: CoreCommand) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(CoreJSON.encode(command).utf8)) as? [String: Any])
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: - The keys the core reads (WaitOptions)

    /// A date is an all-day wait, as web's prompt sends it: the picked calendar day at midnight UTC.
    func testWaitingUntilADayIsAnAllDayDueDate_AITD631() throws {
        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        // 11pm local on the 20th is already the 21st in UTC; the day meant is still the 20th.
        let picked = try XCTUnwrap(pacific.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 23)))
        var command = CoreCommand(kind: "moveTaskToColumn")
        WaitCondition(kind: .until(picked), keepAssignee: false).apply(to: &command, calendar: pacific)
        let fields = try json(command)

        let due = try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(fields["dueDateTime"] as? String)))
        XCTAssertEqual(utc.dateComponents([.year, .month, .day, .hour], from: due),
                       DateComponents(year: 2026, month: 11, day: 20, hour: 0))
        XCTAssertEqual(fields["isAllDay"] as? Bool, true)
        XCTAssertEqual(fields["keepAssignee"] as? Bool, false)
        XCTAssertNil(fields["waitOnTaskId"])
    }

    func testWaitingOnATaskNamesItAndCanKeepTheAssignee_AITD631() throws {
        var command = CoreCommand(kind: "dropBoardCard")
        WaitCondition(kind: .on(taskId: "t-9", title: "Ship the API"), keepAssignee: true).apply(to: &command)
        let fields = try json(command)
        XCTAssertEqual(fields["waitOnTaskId"] as? String, "t-9")
        XCTAssertEqual(fields["keepAssignee"] as? Bool, true)
        XCTAssertNil(fields["dueDateTime"])
        XCTAssertNil(fields["isAllDay"])
    }

    /// Web's rule: the day has to be after today, or the task would wake at once.
    func testOnlyADayAfterTodayCanBeWaitedUntil_AITD631() throws {
        let now = Date()
        XCTAssertFalse(WaitCondition.isAfterToday(now, now: now))
        XCTAssertFalse(WaitCondition.isAfterToday(now.addingTimeInterval(-86_400), now: now))
        XCTAssertTrue(WaitCondition.isAfterToday(try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: now)), now: now))
    }

    // MARK: - Recognising the refusal

    func testOnlyTheCoresWaitingRefusalAsksForACondition_AITD631() {
        XCTAssertTrue(WaitCondition.needsCondition(
            CoreFailure(kind: .refused, message: "x", status: nil, id: nil, code: "WAITING_NEEDS_CONDITION")))
        // The server's 422 carries the same code through the core.
        XCTAssertTrue(WaitCondition.needsCondition(
            CoreFailure(kind: .refused, message: "x", status: 422, id: nil, code: "WAITING_NEEDS_CONDITION")))
        XCTAssertFalse(WaitCondition.needsCondition(CoreFailure(kind: .refused, message: "x", status: nil, id: nil)))
        XCTAssertFalse(WaitCondition.needsCondition(URLError(.notConnectedToInternet)))
    }

    // MARK: - Ask, then send the same move again

    private struct Moved: Error {}

    /// The first attempt goes out with no condition; refused, the prompt opens with the task, and
    /// confirming sends the move again carrying the answer.
    func testARefusedMoveAsksAndRetriesWithTheAnswer_AITD631() async throws {
        let presenter = WaitingPromptPresenter()
        var attempts: [WaitCondition?] = []
        let task = TestHelpers.createTestTask(id: "t-1", title: "Write the docs")

        try await presenter.move(task) { condition in
            attempts.append(condition)
            if condition == nil {
                throw CoreFailure(kind: .refused, message: "needs", status: nil, id: nil, code: "WAITING_NEEDS_CONDITION")
            }
        }
        XCTAssertEqual(attempts.count, 1)
        XCTAssertEqual(presenter.pending?.task.id, "t-1", "the prompt is open for the task that was moved")

        let answer = WaitCondition(kind: .on(taskId: "t-2", title: "Review"), keepAssignee: false)
        try await presenter.confirm(answer)
        XCTAssertEqual(attempts, [nil, answer])
        XCTAssertNil(presenter.pending)
    }

    func testCancellingLeavesTheTaskWhereItWas_AITD631() async throws {
        let presenter = WaitingPromptPresenter()
        var attempts = 0
        try await presenter.move(TestHelpers.createTestTask(id: "t-1", title: "x")) { _ in
            attempts += 1
            throw CoreFailure(kind: .refused, message: "needs", status: nil, id: nil, code: "WAITING_NEEDS_CONDITION")
        }
        presenter.cancel()
        XCTAssertNil(presenter.pending)
        XCTAssertEqual(attempts, 1, "cancel sends nothing more")
    }

    /// A move that needs no condition — any other column, or a task that already waits on
    /// something — just happens, with no prompt.
    func testAMoveTheCoreAcceptsNeverPrompts_AITD631() async throws {
        let presenter = WaitingPromptPresenter()
        var attempts = 0
        try await presenter.move(TestHelpers.createTestTask(id: "t-1", title: "x")) { _ in attempts += 1 }
        XCTAssertEqual(attempts, 1)
        XCTAssertNil(presenter.pending)
    }

    // MARK: - The toggle's label

    /// Any other failure is still the caller's to report; it never opens the prompt.
    func testOtherFailuresAreRethrownWithoutAPrompt_AITD631() async {
        let presenter = WaitingPromptPresenter()
        do {
            try await presenter.move(TestHelpers.createTestTask(id: "t-1", title: "x")) { _ in
                throw URLError(.notConnectedToInternet)
            }
            XCTFail("the failure should reach the caller")
        } catch {
            XCTAssertNil(presenter.pending)
        }
    }

    func testTheKeepToggleNamesWhoKeepsTheTask_AITD631() {
        XCTAssertEqual(WaitCondition.keepLabel(assigneeId: "me", assigneeName: "Jon", currentUserId: "me"),
                       NSLocalizedString("waiting.prompt.keepAssignedToMe", comment: ""))
        XCTAssertEqual(WaitCondition.keepLabel(assigneeId: "u2", assigneeName: "Sam", currentUserId: "me"),
                       String(format: NSLocalizedString("waiting.prompt.keepAssignedTo", comment: ""), "Sam"))
        XCTAssertNil(WaitCondition.keepLabel(assigneeId: nil, assigneeName: nil, currentUserId: "me"),
                     "nobody assigned: nothing to keep, no toggle")
    }
}
