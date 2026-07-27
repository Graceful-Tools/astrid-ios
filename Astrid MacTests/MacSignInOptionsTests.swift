//  MacSignInOptionsTests.swift
//  Which sign-in methods a build may offer — see MacSignInOptions.
//
//  The direct-download build is signed without com.apple.developer.applesignin (Apple does not
//  issue it in Developer ID profiles). An Apple button in that build fails at the moment the user
//  taps it, so it must not be shown.

import XCTest
@testable import Astrid_Mac

final class MacSignInOptionsTests: XCTestCase {

    func testAppleSignInNeedsTheEntitlement() {
        XCTAssertTrue(MacSignInOptions.showsAppleSignIn(
            entitlements: ["com.apple.developer.applesignin": ["Default"]]))
        XCTAssertFalse(MacSignInOptions.showsAppleSignIn(entitlements: [:]),
                       "No entitlement means the button must be hidden")
    }

    /// An empty array is what a stripped entitlements file can leave behind — it grants nothing.
    func testEmptyEntitlementCountsAsAbsent() {
        XCTAssertFalse(MacSignInOptions.showsAppleSignIn(
            entitlements: ["com.apple.developer.applesignin": [String]()]))
    }

    /// Other entitlements are irrelevant — associated-domains IS in the Developer ID profile, so
    /// keying off "we have some entitlements" would wrongly show the button.
    func testOtherEntitlementsDoNotEnableIt() {
        XCTAssertFalse(MacSignInOptions.showsAppleSignIn(
            entitlements: ["com.apple.developer.associated-domains": ["webcredentials:astrid.cc"],
                           "com.apple.security.app-sandbox": true]))
    }

    /// The signature-reading path works: the sandbox entitlement is present in EVERY signing
    /// configuration — the app's own file, the DMG's stripped one, and the minimal CI file.
    func testItCanReadThisBuildsSignature() {
        XCTAssertNotNil(MacSignInOptions.entitlement("com.apple.security.app-sandbox"),
                        "SecTask should surface an entitlement every configuration grants")
    }

    /// The runtime flag follows the signature, whatever it happens to say. An earlier version of
    /// this test asserted the entitlement was PRESENT — true on a dev machine, false on Xcode
    /// Cloud, where the test host is ad-hoc signed with ci_scripts/AstridMacCI.entitlements. That
    /// assumption is precisely what this feature exists to avoid, and it broke the macOS build.
    func testRuntimeValueAgreesWithTheSignature() {
        let key = "com.apple.developer.applesignin"
        let expected = MacSignInOptions.showsAppleSignIn(
            entitlements: MacSignInOptions.entitlement(key).map { [key: $0] } ?? [:])
        XCTAssertEqual(MacSignInOptions.showsAppleSignIn, expected)
    }
}
