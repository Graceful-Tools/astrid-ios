//  MacEntitlementsGuardTests.swift
//  Guard for the App Store upload rejection on build #571 (ITMS-90285).
//
//  "Astrid Mac.entitlements" claimed com.apple.security.personal-information.reminders. There is
//  no such App Sandbox entitlement on macOS — Reminders access rides on the calendars
//  entitlement — so App Store Connect rejected the package:
//
//      Invalid Code Signing Entitlements … key 'com.apple.security.personal-information.reminders'
//      … is not supported. (90285)
//
//  Nothing local catches this: the app builds, runs, and even NOTARIZES with the bogus key, since
//  notarization does not validate entitlement names. Only the upload does — so this test does.

import XCTest

final class MacEntitlementsGuardTests: XCTestCase {

    /// App Sandbox keys macOS actually defines, plus the developer entitlements this app uses.
    /// Anything outside this list gets the build rejected at upload, not at build time.
    private let supported: Set<String> = [
        "com.apple.security.app-sandbox",
        "com.apple.security.network.client",
        "com.apple.security.network.server",
        "com.apple.security.files.user-selected.read-only",
        "com.apple.security.files.user-selected.read-write",
        "com.apple.security.files.downloads.read-write",
        "com.apple.security.personal-information.addressbook",
        "com.apple.security.personal-information.calendars",
        "com.apple.security.personal-information.location",
        "com.apple.security.device.camera",
        "com.apple.security.device.microphone",
        "com.apple.security.device.audio-input",
        "com.apple.security.print",
        "com.apple.security.automation.apple-events",
        "com.apple.security.application-groups",
        "com.apple.developer.applesignin",
        "com.apple.developer.associated-domains",
        "com.apple.developer.aps-environment",
        "keychain-access-groups",
    ]

    func testMacEntitlementsUseOnlyKeysMacOSSupports() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()

        var violations: [String] = []
        for name in ["Astrid Mac/Astrid Mac.entitlements",
                     "Astrid Mac/Astrid Mac Direct.entitlements",
                     "ci_scripts/AstridMacCI.entitlements"] {
            let url = root.appendingPathComponent(name)
            let data = try Data(contentsOf: url)
            let plist = try XCTUnwrap(try PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any])
            for key in plist.keys where !supported.contains(key) {
                violations.append("\(name): \(key)")
            }
        }

        XCTAssertEqual(violations, [], """
            These entitlements are not supported on macOS and will be rejected at upload (ITMS-90285):
            \(violations.joined(separator: "\n"))
            """)
    }

    /// The capability the app actually needs — EventKit reminders ride on it — must stay.
    func testCalendarsEntitlementSurvives() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        for name in ["Astrid Mac/Astrid Mac.entitlements", "Astrid Mac/Astrid Mac Direct.entitlements"] {
            let data = try Data(contentsOf: root.appendingPathComponent(name))
            let plist = try XCTUnwrap(try PropertyListSerialization
                .propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertNotNil(plist["com.apple.security.personal-information.calendars"],
                            "\(name) lost the calendars entitlement, which is what grants Reminders access")
        }
    }
}
