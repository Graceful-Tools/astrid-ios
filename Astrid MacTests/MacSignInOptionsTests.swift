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

    /// The locally-built (development-signed) app carries the full entitlements, so the runtime
    /// answer here is true — the value is read from the signature, not hardcoded.
    func testRuntimeValueReadsThisBuildsSignature() {
        XCTAssertTrue(MacSignInOptions.showsAppleSignIn,
                      "Development builds sign with Astrid Mac.entitlements, which has it")
    }
}
