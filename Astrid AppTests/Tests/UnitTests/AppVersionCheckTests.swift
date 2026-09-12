//  AppVersionCheckTests.swift
//  Tests for AITD-383 — "Add an 'Update' CTA in the style of a reminder when a newer version of
//  the app is available."
//
//  The CTA is the visible half; these cover the half that decides whether it appears at all,
//  which is where this feature can go wrong quietly. A version check that is subtly wrong does
//  not crash — it just nags the wrong people forever, or never appears and looks like it was
//  never built.

import XCTest
@testable import Astrid_App

final class AppVersionCheckTests: XCTestCase {

    // MARK: - Versions are numbers, not text

    /// The one that makes a string compare unacceptable: "1.10.0" sorts BEFORE "1.9.2"
    /// lexicographically, so the user on the newest build would be told to update.
    func testTenIsNewerThanNine() {
        XCTAssertTrue(AppVersionCheck.isNewer("1.10.0", than: "1.9.2"),
                      "AITD-383: 1.10 is newer than 1.9 — a string compare says otherwise")
        XCTAssertFalse(AppVersionCheck.isNewer("1.9.2", than: "1.10.0"))
    }

    func testOrdinaryOrdering() {
        XCTAssertTrue(AppVersionCheck.isNewer("1.9.3", than: "1.9.2"))
        XCTAssertTrue(AppVersionCheck.isNewer("2.0.0", than: "1.99.99"))
        XCTAssertFalse(AppVersionCheck.isNewer("1.9.2", than: "1.9.2"))
    }

    /// A server reporting two components and an app reporting three must not read as a permanent
    /// upgrade. Missing components are zeros.
    func testMissingComponentsAreZero() {
        XCTAssertEqual(AppVersionCheck.compare("1.9", "1.9.0"), .orderedSame)
        XCTAssertEqual(AppVersionCheck.compare("1.9.0.0", "1.9"), .orderedSame)
        XCTAssertFalse(AppVersionCheck.isNewer("1.9", than: "1.9.0"))
    }

    /// A cosmetic suffix is a real thing builds do. It must not throw, crash, or silence the
    /// check — it is simply not the decisive part.
    func testNonNumericSuffixesDoNotBreakTheComparison() {
        XCTAssertEqual(AppVersionCheck.compare("1.9.2-beta", "1.9.2"), .orderedSame)
        XCTAssertTrue(AppVersionCheck.isNewer("1.9.3-rc1", than: "1.9.2"))
    }

    // MARK: - TestFlight must not be told to downgrade

    /// THE failure mode for this account: internal builds routinely run ahead of the App Store, so
    /// "latest != current" would nag every internal build to go backwards — wrong, and unfixable
    /// by the person looking at it.
    func testAnInternalBuildAheadOfTheStoreIsNotPrompted() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.3", latest: "1.9.2",
                                                    dismissedVersion: nil),
                       "AITD-383: a build newer than the store must never be told to update")
    }

    func testABuildBehindTheStoreIsPrompted() {
        XCTAssertTrue(AppVersionCheck.shouldPrompt(current: "1.9.1", latest: "1.9.2",
                                                   dismissedVersion: nil))
    }

    func testTheCurrentVersionIsNotPrompted() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.2", latest: "1.9.2",
                                                    dismissedVersion: nil))
    }

    // MARK: - Dismissal is per version

    func testDismissingAVersionSilencesThatVersion() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.1", latest: "1.9.2",
                                                    dismissedVersion: "1.9.2"))
    }

    /// One dismissal must not turn the feature off for good.
    func testDismissingAVersionDoesNotSilenceTheNextOne() {
        XCTAssertTrue(AppVersionCheck.shouldPrompt(current: "1.9.1", latest: "1.9.3",
                                                   dismissedVersion: "1.9.2"),
                      "AITD-383: dismissing 1.9.2 was an answer about 1.9.2")
    }

    /// Dismissing something newer than what is now offered still counts — the user has already
    /// said no to at least this much.
    func testADismissalAheadOfTheOfferStillHolds() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.1", latest: "1.9.2",
                                                    dismissedVersion: "1.9.5"))
    }

    // MARK: - Not knowing is not an update

    /// The endpoint does not exist yet — astrid-web deploys by hand — so this is the state the
    /// app will actually be in when this ships. It has to be silent, not broken.
    func testAnUnknownLatestVersionNeverPrompts() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.1", latest: nil,
                                                    dismissedVersion: nil),
                       "AITD-383: an absent endpoint means silence, not a banner")
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.1", latest: "",
                                                    dismissedVersion: nil))
    }

    /// Not knowing our OWN version is the same kind of nothing.
    func testAnUnknownCurrentVersionNeverPrompts() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: nil, latest: "1.9.2",
                                                    dismissedVersion: nil))
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "", latest: "1.9.2",
                                                    dismissedVersion: nil))
    }

    /// Garbage must not be decisive either way. "" parses to [0], so it is not newer than a real
    /// version — the check stays quiet rather than prompting everyone.
    func testGarbageDoesNotPrompt() {
        XCTAssertFalse(AppVersionCheck.shouldPrompt(current: "1.9.2", latest: "not-a-version",
                                                    dismissedVersion: nil))
    }
}
