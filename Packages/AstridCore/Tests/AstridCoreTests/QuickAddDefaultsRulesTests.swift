import AstridCore
import XCTest

/// AITD-646 (core `317e546` + `60b8aa8`): a new task's defaults through the rule door, replacing
/// the app's `NewTaskDefaults.swift`.
final class QuickAddDefaultsRulesTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z")!
    private let california = TimeZone(secondsFromGMT: -7 * 3600)!

    private func ask(_ list: QuickAddList?, userId: String? = "jon", priority: Int? = nil,
                     assigneeId: String? = nil, now: Date? = nil) throws -> QuickAddDefaults {
        try CoreRules.quickAddDefaults(list: list, userId: userId, now: now ?? self.now,
                                       timeZone: california, priority: priority, assigneeId: assigneeId)
    }

    private func iso(_ date: Date?) -> String? {
        date.map { ISO8601DateFormatter().string(from: $0) }
    }

    /// High, weekly, Dana's, due tomorrow at five — the task's own example.
    func testAITD646_aListHandsQuickAddEveryDefault() throws {
        let list = QuickAddList(id: "l1", name: "Work", defaultPriority: 3, defaultRepeating: "weekly",
                                defaultAssigneeId: "dana", defaultDueDate: "tomorrow", defaultDueTime: "17:00")
        let answer = try ask(list)
        XCTAssertEqual(answer.priority, 3)
        XCTAssertEqual(answer.assigneeId, "dana")
        XCTAssertEqual(answer.repeating, "weekly")
        XCTAssertEqual(iso(answer.dueDateTime), "2026-09-09T00:00:00Z", "tomorrow 17:00 at UTC-7")
        XCTAssertFalse(answer.isAllDay)
        XCTAssertFalse(answer.isPrivate)
    }

    func testAITD646_aChoiceBeatsADefault() throws {
        let list = QuickAddList(id: "l1", name: "Work", defaultPriority: 3, defaultAssigneeId: "dana")
        let answer = try ask(list, priority: 1, assigneeId: "sam")
        XCTAssertEqual(answer.priority, 1)
        XCTAssertEqual(answer.assigneeId, "sam")
        XCTAssertNil(try ask(list, assigneeId: "unassigned").assigneeId, "unassigned is a choice of nobody")
    }

    /// The three meanings of `defaultAssigneeId` that `NewTaskDefaultsAssigneeTests` pinned.
    func testAITD646_theDefaultAssigneeKeepsItsThreeMeanings() throws {
        func assignee(_ value: String?, userId: String? = "jon") throws -> String? {
            try ask(QuickAddList(id: "l1", name: "Work", defaultAssigneeId: value), userId: userId).assigneeId
        }
        XCTAssertEqual(try assignee(nil), "jon", "no default is the creator")
        XCTAssertEqual(try assignee(""), "jon", "empty is absent, not unassigned")
        XCTAssertNil(try assignee("unassigned"))
        XCTAssertEqual(try assignee("user-9"), "user-9")
        XCTAssertNil(try assignee(nil, userId: nil), "signed out, the creator is nobody")
    }

    /// My Tasks has no list defaults, but a task typed there still starts out yours.
    func testAITD646_noListIsAViewThatStartsOutMine() throws {
        let answer = try ask(nil)
        XCTAssertEqual(answer.assigneeId, "jon")
        XCTAssertNil(answer.dueDateTime)
        XCTAssertNil(answer.repeating)
    }

    /// A day with no time is all-day, stored at UTC midnight; `next_month` is read (core D59).
    func testAITD646_aDayWithNoTimeIsAllDayAndNextMonthIsRead() throws {
        let tomorrow = try ask(QuickAddList(id: "l1", name: "Work", defaultDueDate: "tomorrow"))
        XCTAssertEqual(iso(tomorrow.dueDateTime), "2026-09-08T00:00:00Z")
        XCTAssertTrue(tomorrow.isAllDay)

        let nextMonth = try ask(QuickAddList(id: "l1", name: "Work", defaultDueDate: "next_month"))
        XCTAssertEqual(iso(nextMonth.dueDateTime), "2026-10-07T00:00:00Z")

        XCTAssertNil(try ask(QuickAddList(id: "l1", name: "Work", defaultDueDate: "none")).dueDateTime)
    }

    /// `custom` carries no pattern, so it is no repeat; `never` is none either.
    func testAITD646_onlyARealRepeatIsADefault() throws {
        XCTAssertEqual(try ask(QuickAddList(id: "l1", name: "W", defaultRepeating: "daily")).repeating, "daily")
        XCTAssertNil(try ask(QuickAddList(id: "l1", name: "W", defaultRepeating: "never")).repeating)
        XCTAssertNil(try ask(QuickAddList(id: "l1", name: "W", defaultRepeating: "custom")).repeating)
    }
}
