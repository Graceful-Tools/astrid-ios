import AstridCore
import XCTest

/// AITD-655 (AITD-621): the reminder triage deck through the rule door, replacing the app's
/// `ReminderTriage.deck` copy (core `rows::triage::deck`).
final class ReminderTriageRulesTests: XCTestCase {

    private struct WireTask: Encodable {
        let id: String
        let title: String
        var assigneeId: String?
        var dueDateTime: Date?
        var isAllDay = true
        var completed = false
    }

    private let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

    private func task(_ id: String, _ assignee: String?, _ due: String?, completed: Bool = false) -> WireTask {
        WireTask(id: id, title: id, assigneeId: assignee, dueDateTime: due.map(date), completed: completed)
    }

    private func deck(_ tasks: [WireTask], userId: String? = "me", reminded: String? = nil) throws -> [String] {
        try CoreRules.reminderTriage(tasks: tasks, userId: userId, remindedTaskId: reminded,
                                     now: now, timeZone: utc)
    }

    func testAITD655_theDeckIsMyOpenTasksDueTodayOrOverdue_soonestFirst() throws {
        let tasks = [
            task("today", "me", "2026-06-15T00:00:00Z"),
            task("late", "me", "2000-01-01T00:00:00Z"),
            task("theirs", "bo", "2000-01-01T00:00:00Z"),
            task("done", "me", "2000-01-01T00:00:00Z", completed: true),
            task("later", "me", "2099-01-01T00:00:00Z"),
            task("undated", "me", nil),
            task("nobody", nil, "2000-01-01T00:00:00Z"),
        ]
        XCTAssertEqual(try deck(tasks), ["late", "today"])
    }

    func testAITD655_theRemindedTaskLeadsOnce_evenWhenNotDue() throws {
        let tasks = [task("late", "me", "2000-01-01T00:00:00Z"), task("soon", "me", "2026-06-20T00:00:00Z")]
        XCTAssertEqual(try deck(tasks, reminded: "soon"), ["soon", "late"])
        XCTAssertEqual(try deck(tasks, reminded: "late"), ["late"])
    }

    func testAITD655_someoneElsesRemindedTaskIsNotDealt_andNobodySignedInIsEmpty() throws {
        let theirs = [task("theirs", "bo", "2026-06-15T00:00:00Z")]
        XCTAssertEqual(try deck(theirs, reminded: "theirs"), [])
        XCTAssertEqual(try deck([task("late", "me", "2000-01-01T00:00:00Z")], userId: nil), [])
    }
}
