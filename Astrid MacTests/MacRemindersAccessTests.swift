//  MacRemindersAccessTests.swift
//  Reminders access must survive dropping com.apple.security.personal-information.reminders
//  (ITMS-90285). That key is not a real macOS App Sandbox entitlement, so it granted nothing —
//  EventKit reminders ride on com.apple.security.personal-information.calendars, which stays.
//  This runs in the app test host, under the app's REAL entitlements, so a sandbox that refused
//  EventKit would show up here.

import XCTest
import EventKit
@testable import Astrid_Mac

final class MacRemindersAccessTests: XCTestCase {

    /// Constructing an EKEventStore and asking about reminders must not be blocked by the sandbox.
    func testEventKitIsReachableUnderTheSandbox() {
        let store = EKEventStore()
        let status = EKEventStore.authorizationStatus(for: .reminder)
        XCTAssertNotEqual(status, .restricted,
                          "The sandbox is refusing EventKit — the calendars entitlement is missing")
        // Fetching sources works regardless of grant; a sandbox denial surfaces as a crash/refusal.
        _ = store.sources
    }

    /// When access is already granted on this machine, reminder calendars must actually come back —
    /// the strongest available proof that removing the bogus entitlement changed nothing.
    func testGrantedAccessStillReturnsReminderCalendars() throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        try XCTSkipUnless(status == .fullAccess || status == .authorized,
                          "Reminders access is \(status.rawValue) on this machine — nothing to verify without prompting")
        let calendars = EKEventStore().calendars(for: .reminder)
        XCTAssertFalse(calendars.isEmpty, "Access is granted but no reminder calendars came back")
    }
}
