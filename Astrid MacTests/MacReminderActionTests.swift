//  MacReminderActionTests.swift
//  Astrid for Mac — Task 32c6f756: notification action routing (Complete / Snooze / open).
//  The handler previously ignored these identifiers, so the reminder buttons did nothing.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacReminderActionTests: XCTestCase {

    func testRouting() {
        XCTAssertEqual(ReminderAction.route(actionIdentifier: "COMPLETE_ACTION"), .complete)
        XCTAssertEqual(ReminderAction.route(actionIdentifier: "SNOOZE_ACTION"), .snooze)
        // The default tap action (UNNotificationDefaultActionIdentifier) + any unknown → open.
        XCTAssertEqual(ReminderAction.route(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier"), .open)
        XCTAssertEqual(ReminderAction.route(actionIdentifier: "something_else"), .open)
    }

    func testSnoozeDefaultIsSane() {
        XCTAssertGreaterThan(ReminderAction.snoozeMinutes, 0)
    }
}
#endif
