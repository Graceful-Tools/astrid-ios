//  ListQuickAddDefaultsTests.swift
//  `defaultAssigneeId` has three meanings on the wire (documented in ListDefaults):
//    nil          → "task_creator": the new task goes to whoever creates it
//    "unassigned" → nobody
//    an id        → that person
//  Mac was collapsing nil and "unassigned" into "no assignee", so a list whose default is the
//  creator produced UNASSIGNED tasks. These pinned the Swift copy, `NewTaskDefaults`; since
//  AITD-646 they run against astrid-core's `quickAddDefaults`, which replaced it.

import XCTest
@testable import Astrid_App

final class ListQuickAddDefaultsTests: XCTestCase {

    private let me = "user-me"

    private func assignee(_ value: String?, currentUserId: String?) -> String? {
        ListQuickAddDefaults.assignee(listDefault: value, currentUserId: currentUserId)
    }

    func testNilMeansTheTaskCreator() {
        XCTAssertEqual(assignee(nil, currentUserId: me), me, "nil is 'task_creator', not 'no assignee'")
    }

    func testExplicitUnassignedMeansNobody() {
        XCTAssertNil(assignee("unassigned", currentUserId: me))
    }

    func testASpecificIdIsHonoured() {
        XCTAssertEqual(assignee("user-9", currentUserId: me), "user-9")
    }

    /// Signed out, "task creator" cannot be resolved — better unassigned than a bogus id.
    func testNoCurrentUserFallsBackToUnassigned() {
        XCTAssertNil(assignee(nil, currentUserId: nil))
    }

    /// An empty string is an ABSENT value, not the literal "unassigned" — so it means the same as
    /// nil: task creator.
    func testEmptyStringIsTreatedAsAbsentNotUnassigned() {
        XCTAssertEqual(assignee("", currentUserId: me), me)
    }

    // MARK: - AITD-646: the whole answer comes from the core

    private let now = ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z")!
    private let california = TimeZone(secondsFromGMT: -7 * 3600)!

    /// A list set to "next month" — which the iOS and Mac list settings offer — keeps its default
    /// now that quick-add asks the core (core D59).
    func testAITD646_aNextMonthListKeepsItsDefault() {
        var list = TaskList(id: "l1", name: "Work", privacy: .PRIVATE)
        list.defaultDueDate = "next_month"
        let answer = ListQuickAddDefaults.resolve(list, currentUserId: me, now: now, timeZone: california)
        XCTAssertEqual(answer.dueDateTime.map { ISO8601DateFormatter().string(from: $0) },
                       "2026-10-07T00:00:00Z")
        XCTAssertTrue(answer.isAllDay)
    }

    /// A date default with a time is a TIMED task at that local time, not an all-day one.
    func testAITD646_aDefaultTimeMakesATimedTask() {
        var list = TaskList(id: "l1", name: "Work", privacy: .PRIVATE)
        list.defaultDueDate = "tomorrow"
        list.defaultDueTime = "17:00"
        let answer = ListQuickAddDefaults.resolve(list, currentUserId: me, now: now, timeZone: california)
        XCTAssertEqual(answer.dueDateTime.map { ISO8601DateFormatter().string(from: $0) },
                       "2026-09-09T00:00:00Z")
        XCTAssertFalse(answer.isAllDay)
    }

    /// The repeat badge previews only a real repeat.
    func testAITD646_onlyARealRepeatIsPreviewed() {
        var list = TaskList(id: "l1", name: "Work", privacy: .PRIVATE)
        list.defaultRepeating = "weekly"
        XCTAssertEqual(ListQuickAddDefaults.resolve(list, currentUserId: nil).repeating, "weekly")
        list.defaultRepeating = "never"
        XCTAssertNil(ListQuickAddDefaults.resolve(list, currentUserId: nil).repeating)
        XCTAssertNil(ListQuickAddDefaults.resolve(nil, currentUserId: nil).repeating)
    }
}
