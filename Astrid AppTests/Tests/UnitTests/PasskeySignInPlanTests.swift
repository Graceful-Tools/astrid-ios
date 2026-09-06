//  PasskeySignInPlanTests.swift
//  Regression guard for AITD-298 — "On Mac, sign-in with passkey requires a QR code but cannot
//  work with local passkey system (e.g. dashlane etc)".
//
//  The Mac sign-in ran a discoverable assertion with the full system sheet. With no passkey in
//  iCloud Keychain that sheet leads with the nearby-device QR, and third-party managers only
//  show once enabled in System Settings — which the app never said. The fix asks for LOCAL
//  credentials first (`.preferImmediatelyAvailableCredentials`), and when there are none offers
//  the alternatives explicitly. These tests pin that decision as a rule.

import XCTest
import AuthenticationServices
@testable import Astrid_App

final class PasskeySignInPlanTests: XCTestCase {

    // MARK: - Which sheet a sign-in tap asks for

    func testAITD298_MacAsksForLocalPasskeysFirst() {
        XCTAssertEqual(PasskeySignInPlan.initialPresentation(isMac: true), .localOnly)
    }

    /// The phone IS the passkey device; the full sheet (with its nearby-device option) stays.
    func testAITD298_IOSKeepsTheFullSheet() {
        XCTAssertEqual(PasskeySignInPlan.initialPresentation(isMac: false), .fullSheet)
    }

    /// The local-only attempt must not fall back to the QR on its own: the request option is
    /// what tells the system to skip the nearby-device flow.
    func testAITD298_LocalOnlyUsesPreferImmediatelyAvailableCredentials() {
        XCTAssertEqual(PasskeyPresentation.localOnly.requestOptions, [.preferImmediatelyAvailableCredentials])
        XCTAssertEqual(PasskeyPresentation.fullSheet.requestOptions, [])
    }

    // MARK: - What a cancellation means under each sheet

    /// With `.preferImmediatelyAvailableCredentials`, "no credentials" ends the request as
    /// `.canceled` without any UI — that is not the user saying no, it is "nothing local".
    func testAITD298_CancelUnderLocalOnlyMeansNoLocalPasskey() {
        let error = PasskeyManager.passkeyError(forAuthorizationCode: .canceled, presentation: .localOnly)
        guard case .noLocalPasskey = error else {
            return XCTFail("expected .noLocalPasskey, got \(error)")
        }
    }

    func testAITD298_CancelUnderTheFullSheetIsStillTheUserCancelling() {
        let error = PasskeyManager.passkeyError(forAuthorizationCode: .canceled, presentation: .fullSheet)
        guard case .userCancelled = error else {
            return XCTFail("expected .userCancelled, got \(error)")
        }
    }

    func testAITD298_OtherCodesMapAsBefore() {
        guard case .notSupported = PasskeyManager.passkeyError(forAuthorizationCode: .notHandled, presentation: .localOnly) else {
            return XCTFail("notHandled should still be .notSupported")
        }
        guard case .invalidResponse = PasskeyManager.passkeyError(forAuthorizationCode: .invalidResponse, presentation: .fullSheet) else {
            return XCTFail("invalidResponse should still be .invalidResponse")
        }
    }

    // MARK: - What happens next

    func testAITD298_NoLocalPasskeyOffersTheAlternatives() {
        XCTAssertEqual(PasskeySignInPlan.nextStep(after: .localOnly, error: .noLocalPasskey), .offerAlternatives)
    }

    /// Dismissing the full sheet is a deliberate no; nothing else pops up.
    func testAITD298_CancellingTheFullSheetIsQuiet() {
        XCTAssertEqual(PasskeySignInPlan.nextStep(after: .fullSheet, error: .userCancelled), .none)
    }

    func testAITD298_RealFailuresSurface() {
        XCTAssertEqual(PasskeySignInPlan.nextStep(after: .localOnly, error: .authenticationFailed("x")), .surfaceError)
        XCTAssertEqual(PasskeySignInPlan.nextStep(after: .fullSheet, error: .serverError("x")), .surfaceError)
    }

    /// The alternatives: the nearby-device sheet is the QR path, offered — not imposed.
    func testAITD298_OtherDeviceFallbackIsTheFullSheet() {
        XCTAssertEqual(PasskeySignInPlan.otherDevicePresentation, .fullSheet)
    }

    func testAITD298_PasswordManagerHelpOpensThePasswordsPane() {
        let url = PasskeySignInPlan.passwordOptionsSettingsURL
        XCTAssertEqual(url.scheme, "x-apple.systempreferences")
        XCTAssertTrue(url.absoluteString.lowercased().contains("passwords"))
    }

    func testAITD298_NoLocalPasskeyHasAnExplanation() {
        let text = PasskeyError.noLocalPasskey.errorDescription ?? ""
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.localizedCaseInsensitiveContains("passkey"))
    }

    // MARK: - The Mac login view follows the rule

    func testAITD298_MacLoginUsesThePlanAndOffersTheFallback() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/App/MacAuthGateView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(source.contains("PasskeySignInPlan.initialPresentation(isMac: true)"),
                      "the sign-in button must ask for local passkeys first")
        XCTAssertTrue(source.contains("PasskeySignInPlan.otherDevicePresentation"),
                      "the QR path must remain available as an explicit fallback")
        XCTAssertTrue(source.contains("PasskeySignInPlan.passwordOptionsSettingsURL"),
                      "the password-manager route must be offered")
    }
}
