//  MacNewDueDateTests.swift
//  Task 0b057b7a — "when assigning a date to a task that has no date, it currently sets a
//  time to current time. it should be 'all day'".
//
//  Picking a day funnels through one place, and that place asked the TASK whether it was
//  all-day. A task with no date at all answered "no", so the day was combined with a time —
//  and with no existing time to take, the day kept the clock time it was built from. Every
//  task you dated quietly acquired a meaningless 3:55 AM.

import XCTest
@testable import Astrid_Mac

final class MacNewDueDateTests: XCTestCase {

    /// The regression: a task with NO date gets an all-day date, whatever the stale flag says.
    func testDatingATaskThatHadNoDateMakesItAllDay() {
        XCTAssertTrue(MacNewDueDate.isAllDay(existingDate: nil, currentIsAllDay: false),
                      "Task 0b057b7a: a first date must not pick up the current clock time")
        XCTAssertTrue(MacNewDueDate.isAllDay(existingDate: nil, currentIsAllDay: true))
    }

    /// A task that already has an all-day date stays all-day.
    func testAnAllDayTaskStaysAllDay() {
        XCTAssertTrue(MacNewDueDate.isAllDay(existingDate: Date(), currentIsAllDay: true))
    }

    /// A task that already has a TIME keeps it — changing the day must not silently discard
    /// a time the user set on purpose.
    func testATimedTaskKeepsItsTime() {
        XCTAssertFalse(MacNewDueDate.isAllDay(existingDate: Date(), currentIsAllDay: false),
                       "Rescheduling a 9am meeting to tomorrow leaves it at 9am")
    }
}
