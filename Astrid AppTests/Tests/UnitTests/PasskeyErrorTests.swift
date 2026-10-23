//  PasskeyErrorTests.swift
//  AITD-537 — every passkey error is shown to the user, so its copy comes from a
//  `passkey.error.*` key (rule 8), not an English literal. These tests used to pin the English,
//  which made the hardcoding impossible to fix without breaking them; now they assert each case
//  reads its key and that the key resolves, so they pass in every language the host runs in.

import XCTest
@testable import Astrid_App

final class PasskeyErrorTests: XCTestCase {

    private func text(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    private func assertReadsKey(_ error: PasskeyError, _ key: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(text(key), key, "\(key) is missing from Localizable.strings", file: file, line: line)
        XCTAssertEqual(error.errorDescription, text(key), file: file, line: line)
    }

    private func assertReadsKey(_ error: PasskeyError, _ key: String, with detail: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(text(key), key, "\(key) is missing from Localizable.strings", file: file, line: line)
        XCTAssertEqual(error.errorDescription, String(format: text(key), detail), file: file, line: line)
        XCTAssertTrue(error.errorDescription?.contains(detail) == true, "the detail is shown", file: file, line: line)
    }

    func testEachFixedErrorReadsItsKey_AITD537() {
        assertReadsKey(.notSupported, "passkey.error.not_supported")
        assertReadsKey(.userCancelled, "passkey.error.cancelled")
        assertReadsKey(.noLocalPasskey, "passkey.error.no_local_passkey")
        assertReadsKey(.invalidChallenge, "passkey.error.invalid_challenge")
        assertReadsKey(.invalidUserId, "passkey.error.invalid_user_id")
        assertReadsKey(.invalidResponse, "passkey.error.invalid_response")
        assertReadsKey(.existingUser(email: "test@example.com", hasPasskey: true), "passkey.error.existing_user_passkey")
        assertReadsKey(.existingUser(email: "test@example.com", hasPasskey: false), "passkey.error.existing_user_other")
    }

    func testErrorsThatCarryADetailShowItInsideTheirKey_AITD537() {
        assertReadsKey(.authenticationFailed("Token expired"), "passkey.error.authentication_failed", with: "Token expired")
        assertReadsKey(.registrationFailed("Server error"), "passkey.error.registration_failed", with: "Server error")
        assertReadsKey(.unknown("Something went wrong"), "passkey.error.unknown", with: "Something went wrong")
    }

    /// The server's own message is passed through as given — it is already the server's copy.
    func testAServerErrorShowsTheServersMessage() {
        XCTAssertEqual(PasskeyError.serverError("Connection timeout").errorDescription, "Connection timeout")
    }

    func testErrorIsLocalizedError() {
        let error: LocalizedError = PasskeyError.notSupported
        XCTAssertNotNil(error.errorDescription)
    }
}
