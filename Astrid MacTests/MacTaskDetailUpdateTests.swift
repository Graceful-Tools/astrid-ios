//  MacTaskDetailUpdateTests.swift
//  Regression for task 63a27f1b — Mac task detail must actually CLEAR due date and
//  assignee (not early-return) and must preserve the task's repeat-from mode.

import XCTest
@testable import Astrid_Mac

final class MacTaskDetailUpdateTests: XCTestCase {

    // Turning the Due-date toggle OFF must send the clear sentinel, not the current date.
    func testDueOffSendsClearSentinel() {
        XCTAssertEqual(MacTaskDetailUpdate.dueDateArg(hasDue: false, due: Date(timeIntervalSince1970: 1000)),
                       Date.distantPast,
                       "Due-date OFF must map to Date.distantPast so TaskService clears the due date.")
    }

    func testDueOnSendsThatDate() {
        let d = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(MacTaskDetailUpdate.dueDateArg(hasDue: true, due: d), d)
    }

    // Selecting "No one" (nil) must unassign via empty string per the service contract.
    func testNoAssigneeMapsToEmptyString() {
        XCTAssertEqual(MacTaskDetailUpdate.assigneeArg(nil), "",
                       "A nil assignee selection must map to \"\" so TaskService unassigns.")
    }

    func testAssigneePassthrough() {
        XCTAssertEqual(MacTaskDetailUpdate.assigneeArg("user-123"), "user-123")
    }

    // Repeat edits must preserve the task's existing repeat-from mode, not force DUE_DATE.
    func testRepeatFromPreservesCompletionDateMode() {
        let task = Task(id: "t1", title: "x", repeatFrom: .COMPLETION_DATE)
        XCTAssertEqual(MacTaskDetailUpdate.repeatFromArg(task), "COMPLETION_DATE",
                       "A task set to repeat from completion date must keep that mode on repeat edits.")
    }

    func testRepeatFromDefaultsToDueDate() {
        let task = Task(id: "t2", title: "x")
        XCTAssertEqual(MacTaskDetailUpdate.repeatFromArg(task), "DUE_DATE")
    }
}
