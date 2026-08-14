//  SessionCookieRenewalTests.swift
//  Regression guard for Task b8999ea3 — persist the renewed session token that
//  `/api/v1/auth/mobile-session` now returns in its body.
//
//  The trap here is the storage format. The Keychain does NOT hold a bare token: it holds a whole
//  `Cookie` request header, `name=value; name2=value2`, and that string is set verbatim as the
//  Cookie header on every request. The server hands back a bare JWT.
//
//  So writing the token straight to the Keychain would produce `Cookie: eyJhbGciOi…` with no cookie
//  name at all. The server would find no session token, return 401, and the app would sign the user
//  out — immediately, and on the very launch that was supposed to keep them signed in. Worse than
//  the bug being fixed, and it would look exactly like the bug.
//
//  The value has to be swapped INSIDE the stored header, keeping the name already in use and any
//  other cookies alongside it.

import XCTest
@testable import Astrid_App

final class SessionCookieRenewalTests: XCTestCase {

    private let newToken = "eyJhbGciOiJIUzI1NiJ9.new"

    // MARK: - Swapping the value, keeping the name

    /// Production uses the `__Secure-` prefixed name. Keep whichever name is already there.
    func testItReplacesTheValueAndKeepsTheSecureName() {
        let stored = "__Secure-next-auth.session-token=OLD"
        XCTAssertEqual(SessionCookie.replacingToken(in: stored, with: newToken),
                       "__Secure-next-auth.session-token=\(newToken)")
    }

    func testItKeepsThePlainNameWhenThatIsWhatIsStored() {
        let stored = "next-auth.session-token=OLD"
        XCTAssertEqual(SessionCookie.replacingToken(in: stored, with: newToken),
                       "next-auth.session-token=\(newToken)")
    }

    /// Other cookies travel with it — the CSRF cookie in particular. Dropping them would break the
    /// next write rather than the next read, which is a far more confusing failure.
    func testOtherCookiesSurviveInOrder() {
        let stored = "next-auth.csrf-token=abc; __Secure-next-auth.session-token=OLD; other=z"
        XCTAssertEqual(SessionCookie.replacingToken(in: stored, with: newToken),
                       "next-auth.csrf-token=abc; __Secure-next-auth.session-token=\(newToken); other=z")
    }

    /// A JWT is dot-separated, but base64url padding can carry `=`. Splitting on every `=` instead
    /// of the first would truncate the token silently.
    func testATokenContainingEqualsIsNotTruncated() {
        let padded = "eyJhbGciOiJIUzI1NiJ9.payload=="
        XCTAssertEqual(SessionCookie.replacingToken(in: "next-auth.session-token=OLD", with: padded),
                       "next-auth.session-token=\(padded)")
    }

    func testWhitespaceAfterSeparatorsIsTolerated() {
        let stored = "a=1;   next-auth.session-token=OLD ;b=2"
        let result = SessionCookie.replacingToken(in: stored, with: newToken)
        XCTAssertTrue(result.contains("next-auth.session-token=\(newToken)"))
        XCTAssertTrue(result.contains("a=1"))
        XCTAssertTrue(result.contains("b=2"))
    }

    // MARK: - When there is nothing to swap into

    /// Nothing stored yet: still produce a usable header rather than a bare token. The server
    /// accepts either name, so the unprefixed one is the safe default.
    func testWithNothingStoredItStillProducesANamedCookie() {
        for stored in [nil, "", "   "] as [String?] {
            XCTAssertEqual(SessionCookie.replacingToken(in: stored, with: newToken),
                           "next-auth.session-token=\(newToken)",
                           "a bare token would be sent as a nameless Cookie header")
        }
    }

    /// Cookies stored but no session token among them — add one, keep the rest.
    func testASessionCookieIsAddedWhenAbsent() {
        let result = SessionCookie.replacingToken(in: "next-auth.csrf-token=abc", with: newToken)
        XCTAssertTrue(result.contains("next-auth.csrf-token=abc"))
        XCTAssertTrue(result.contains("next-auth.session-token=\(newToken)"))
    }

    /// The result must never be just the token — that is the whole failure this guards.
    func testTheResultIsNeverABareToken() {
        for stored in [nil, "", "a=1", "next-auth.session-token=OLD"] as [String?] {
            let result = SessionCookie.replacingToken(in: stored, with: newToken)
            XCTAssertNotEqual(result, newToken)
            XCTAssertTrue(result.contains("session-token="),
                          "every result must name the session cookie (stored=\(stored ?? "nil"))")
        }
    }

    // MARK: - The response carries it

    /// Absent, not null, when no renewal was due — decoding must not fail, and must not invent one.
    func testASessionResponseWithoutARenewalDecodes() throws {
        let json = #"{"user":{"id":"u1","email":"a@b.c","name":null,"image":null},"meta":{"apiVersion":"v1"}}"#
        let response = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.sessionToken, "no renewal was due; that is not an error")
    }

    func testASessionResponseCarriesTheRenewedToken() throws {
        let json = #"{"user":{"id":"u1","email":"a@b.c","name":null,"image":null},"sessionToken":"NEW","expiresAt":"2026-09-13T00:00:00Z"}"#
        let response = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.sessionToken, "NEW")
    }

    /// The database-session path returns an expiry but no token — nothing to store, not a failure.
    func testAnExpiryWithoutATokenIsNotARenewalToStore() throws {
        let json = #"{"user":{"id":"u1","email":"a@b.c","name":null,"image":null},"expiresAt":"2026-09-13T00:00:00Z"}"#
        let response = try JSONDecoder().decode(SessionResponse.self, from: Data(json.utf8))
        XCTAssertNil(response.sessionToken)
    }

    // MARK: - The caller actually saves it

    func testAuthManagerPersistsARenewedToken() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid App/Core/Authentication/AuthManager.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("SessionCookie.replacingToken"),
                      "a renewed token must be folded into the stored cookie, not written raw")
        XCTAssertTrue(source.contains("saveSessionCookie"),
                      "…and actually saved, or the renewal is received and dropped")
    }
}
