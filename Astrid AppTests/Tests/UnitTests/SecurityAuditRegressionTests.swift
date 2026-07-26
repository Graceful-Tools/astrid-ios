//  SecurityAuditRegressionTests.swift
//  Regression coverage for the pre-Mac-release security audit (2026-07-25).
//
//  Each test pins a specific weakness found during that audit, so a future refactor that
//  reintroduces it fails here rather than in the wild.

import XCTest
@testable import Astrid_App

final class SecurityAuditRegressionTests: XCTestCase {

    // MARK: - OAuth state validation
    //
    // The flow generated `state` and never checked it. An attacker-supplied redirect could
    // therefore inject their own authorization code into the victim's sign-in.

    func testCallbackWithForgedStateIsRejected() {
        let url = URL(string: "com.astrid.app:/oauth?code=attacker_code&state=WRONG")!
        XCTAssertThrowsError(
            try OAuthCallbackValidator.authorizationCode(from: url, expectedState: "EXPECTED")
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackError, .stateMismatch,
                           "A mismatched state must reject the code, not spend it")
        }
    }

    func testCallbackWithoutStateIsRejected() {
        let url = URL(string: "com.astrid.app:/oauth?code=attacker_code")!
        XCTAssertThrowsError(
            try OAuthCallbackValidator.authorizationCode(from: url, expectedState: "EXPECTED")
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackError, .stateMismatch)
        }
    }

    func testEmptyExpectedStateNeverMatches() {
        // Guards against a regression where a nil/empty stored state degrades to "accept anything".
        let url = URL(string: "com.astrid.app:/oauth?code=c&state=")!
        XCTAssertThrowsError(
            try OAuthCallbackValidator.authorizationCode(from: url, expectedState: "")
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackError, .stateMismatch)
        }
    }

    func testMatchingStateReturnsCode() throws {
        let url = URL(string: "com.astrid.app:/oauth?code=good_code&state=S123")!
        let code = try OAuthCallbackValidator.authorizationCode(from: url, expectedState: "S123")
        XCTAssertEqual(code, "good_code")
    }

    func testProviderErrorIsSurfaced() {
        let url = URL(string: "com.astrid.app:/oauth?error=access_denied&state=S123")!
        XCTAssertThrowsError(
            try OAuthCallbackValidator.authorizationCode(from: url, expectedState: "S123")
        ) { error in
            XCTAssertEqual(error as? OAuthCallbackError, .providerError("access_denied"))
        }
    }

    // MARK: - Deep-link identifier validation
    //
    // `astrid://tasks/abc%2F..%2Fadmin` decoded to `abc/../admin` and was interpolated straight
    // into `/api/v1/tasks/<id>`, letting a crafted link steer the authenticated client at
    // arbitrary API paths.

    func testTraversalIdentifiersAreRejected() {
        for hostile in ["abc/../admin", "../../api/v1/users/me/export", "a/b", "..", ".",
                        "id with space", "id%2Fadmin", "http://evil.test"] {
            XCTAssertFalse(APIPathSafety.isValidIdentifier(hostile),
                           "\(hostile) must not be accepted as an identifier")
        }
    }

    func testLegitimateIdentifiersAreAccepted() {
        for ok in ["2bdd5df3-1a2b-4c3d-9e8f-000000000000", "temp_12345", "local_abc-DEF_9", "aB3"] {
            XCTAssertTrue(APIPathSafety.isValidIdentifier(ok), "\(ok) should be a valid identifier")
        }
    }

    func testEmptyAndOverlongIdentifiersAreRejected() {
        XCTAssertFalse(APIPathSafety.isValidIdentifier(""))
        XCTAssertFalse(APIPathSafety.isValidIdentifier(String(repeating: "a", count: 129)))
        XCTAssertTrue(APIPathSafety.isValidIdentifier(String(repeating: "a", count: 128)))
    }

    // MARK: - Path escaping (second, independent guard)

    func testSeparatorsCannotEscapeTheirPathComponent() {
        XCTAssertEqual(APIPathSafety.escapedPathComponent("abc/../admin"), "abc%2F..%2Fadmin")
        XCTAssertEqual(APIPathSafety.escapedPathComponent("a b"), "a%20b")
        XCTAssertEqual(APIPathSafety.escapedPathComponent("id?x=1&y=2"), "id%3Fx%3D1%26y%3D2")
    }

    func testEscapingLeavesOrdinaryIdentifiersUntouched() {
        let id = "2bdd5df3-1a2b-4c3d-9e8f-000000000000"
        XCTAssertEqual(APIPathSafety.escapedPathComponent(id), id)
        XCTAssertEqual(APIPathSafety.escapedPathComponent("temp_1.2~3"), "temp_1.2~3")
    }

    /// End-to-end shape check: the escaped component cannot alter the request path.
    func testEscapedComponentKeepsRequestPathIntact() throws {
        let base = URL(string: "https://astrid.cc")!
        let hostile = "abc%2F..%2Fadmin".removingPercentEncoding!   // "abc/../admin"
        let path = "/api/v1/tasks/\(APIPathSafety.escapedPathComponent(hostile))"
        let url = try XCTUnwrap(URLComponents(url: base.appendingPathComponent(path),
                                              resolvingAgainstBaseURL: false)?.url)
        XCTAssertFalse(url.absoluteString.contains("/../"),
                       "Escaped ids must not introduce traversal segments: \(url.absoluteString)")
        XCTAssertTrue(url.absoluteString.hasPrefix("https://astrid.cc/api/v1/tasks/"),
                      "Request must stay under the tasks collection: \(url.absoluteString)")
    }
}
