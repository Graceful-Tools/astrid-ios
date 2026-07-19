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

    func testLabel() {
        XCTAssertEqual(MacRemindersStatus.label(.notDetermined), "Not connected")
        XCTAssertEqual(MacRemindersStatus.label(.denied), "Denied — enable in System Settings › Privacy")
        XCTAssertEqual(MacRemindersStatus.label(.restricted), "Denied — enable in System Settings › Privacy")
        if #available(macOS 14.0, *) {
            XCTAssertEqual(MacRemindersStatus.label(.fullAccess), "Connected")
        }
    }
}
#endif
