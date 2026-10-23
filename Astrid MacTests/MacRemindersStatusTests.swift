//  MacRemindersStatusTests.swift
//  Astrid for Mac — Task 33d648f2: Apple Reminders (EventKit) authorization status mapping.

#if os(macOS)
import XCTest
import EventKit
@testable import Astrid_Mac

final class MacRemindersStatusTests: XCTestCase {

    func testIsGranted() {
        if #available(macOS 14.0, *) {
            XCTAssertTrue(MacRemindersStatus.isGranted(.fullAccess))
            XCTAssertFalse(MacRemindersStatus.isGranted(.writeOnly))
        }
        XCTAssertFalse(MacRemindersStatus.isGranted(.notDetermined))
        XCTAssertFalse(MacRemindersStatus.isGranted(.denied))
        XCTAssertFalse(MacRemindersStatus.isGranted(.restricted))
    }

    /// Rule 8 (AITD-537): each status reads its key, and the key resolves.
    func testLabelsReadTheirKeys_AITD537() {
        var expected: [(EKAuthorizationStatus, String)] = [
            (.notDetermined, "sync.not_connected"),
            (.denied, "mac.reminders.status.denied"),
            (.restricted, "mac.reminders.status.denied"),
        ]
        if #available(macOS 14.0, *) {
            expected.append((.fullAccess, "sync.connected"))
            expected.append((.writeOnly, "mac.reminders.status.limited"))
        }
        for (status, key) in expected {
            XCTAssertNotEqual(NSLocalizedString(key, comment: ""), key, "\(key) is missing")
            XCTAssertEqual(MacRemindersStatus.label(status), NSLocalizedString(key, comment: ""))
        }
    }
}
#endif
