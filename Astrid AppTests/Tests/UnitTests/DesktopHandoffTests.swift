import XCTest
@testable import Astrid_App

/// GitHub and SSO sign-in through the desktop hand-off (AITD-465, spec §6.5).
///
/// The app never sees a GitHub or SAML credential: it opens `/auth/desktop` in an
/// ASWebAuthenticationSession, gets a one-time code back on its URL scheme, and trades the code
/// plus a PKCE verifier for a session token. These tests pin the parts that are easy to get
/// subtly wrong — the S256 encoding, the URL the server validates, and the state check.
final class DesktopHandoffTests: XCTestCase {

    func testAITD465_ChallengeIsRFC7636S256() {
        // Expected value computed outside Swift, so this checks the encoding rather than echoing it:
        //   printf '%s' <verifier> | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
        XCTAssertEqual(
            DesktopHandoff.challenge(for: "aitd-465-fixed-verifier-0123456789abcdefghijklmnop"),
            "xJkJUxAnlhJE5P-pOK6kmK9ddjw59Jx9PSVSNLa9Yt4"
        )
    }

    func testAITD465_GeneratedVerifierIsWithinRFCBoundsAndUnpredictable() {
        let a = DesktopHandoff.Attempt.start()
        let b = DesktopHandoff.Attempt.start()
        XCTAssertTrue((43...128).contains(a.verifier.count))
        XCTAssertNil(a.verifier.range(of: "[^A-Za-z0-9\\-._~]", options: .regularExpression))
        XCTAssertEqual(a.challenge, DesktopHandoff.challenge(for: a.verifier))
        // The server rejects a challenge that is not 43 base64url characters.
        XCTAssertEqual(a.challenge.count, 43)
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.state, b.state)
    }

    func testAITD465_StartURLCarriesWhatTheServerValidates() throws {
        let attempt = DesktopHandoff.Attempt(verifier: "v", challenge: "c", state: "s")
        let url = try XCTUnwrap(DesktopHandoff.startURL(
            baseURL: URL(string: "https://www.astrid.cc")!, provider: .github, attempt: attempt, client: "ios"))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "www.astrid.cc")
        XCTAssertEqual(parts.path, "/auth/desktop")
        let query = Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query, [
            "client": "ios",
            "provider": "github",
            "state": "s",
            "code_challenge": "c",
            "code_challenge_method": "S256",
        ])
        // The verifier never leaves the app until the exchange.
        XCTAssertFalse(url.absoluteString.contains("verifier"))
    }

    func testAITD465_EachPlatformNamesItself() {
        #if os(macOS)
        XCTAssertEqual(DesktopHandoff.clientId, "mac")
        #else
        XCTAssertEqual(DesktopHandoff.clientId, "ios")
        #endif
    }

    func testAITD465_CallbackYieldsTheCodeWhenStateMatches() throws {
        let callback = URL(string: "astrid://auth/callback?code=abc123&state=s1")!
        XCTAssertEqual(try DesktopHandoff.code(from: callback, expectedState: "s1"), "abc123")
    }

    func testAITD465_CallbackWithAnotherAttemptsStateIsRejected() {
        let callback = URL(string: "astrid://auth/callback?code=abc123&state=someone-else")!
        XCTAssertThrowsError(try DesktopHandoff.code(from: callback, expectedState: "s1")) {
            XCTAssertEqual($0 as? DesktopHandoff.HandoffError, .stateMismatch)
        }
    }

    func testAITD465_CallbackWithoutACodeIsRejected() {
        for raw in ["astrid://auth/callback?state=s1", "astrid://auth/callback?code=&state=s1"] {
            XCTAssertThrowsError(try DesktopHandoff.code(from: URL(string: raw)!, expectedState: "s1")) {
                XCTAssertEqual($0 as? DesktopHandoff.HandoffError, .missingCode)
            }
        }
    }

    func testAITD465_ACallbackForAnotherRouteIsRejected() {
        // The same scheme also carries task deep links; only auth/callback is a sign-in.
        let callback = URL(string: "astrid://tasks/abc?code=abc123&state=s1")!
        XCTAssertThrowsError(try DesktopHandoff.code(from: callback, expectedState: "s1")) {
            XCTAssertEqual($0 as? DesktopHandoff.HandoffError, .unexpectedCallback)
        }
    }

    func testAITD465_ExchangedTokenIsStoredUnderTheNameTheServerStated() {
        XCTAssertEqual(
            DesktopHandoff.cookieHeader(token: "jwt", cookieName: "__Secure-next-auth.session-token"),
            "__Secure-next-auth.session-token=jwt"
        )
        // A name the app does not recognise as a session cookie falls back rather than storing a
        // header nothing reads.
        XCTAssertEqual(DesktopHandoff.cookieHeader(token: "jwt", cookieName: "evil"), "next-auth.session-token=jwt")
        XCTAssertEqual(DesktopHandoff.cookieHeader(token: "jwt", cookieName: nil), "next-auth.session-token=jwt")
    }

    func testAITD465_ExchangeGoesThroughTheV1Route() throws {
        let source = try RepositoryLocator.source(at: "Astrid App/Core/Networking/AstridAPIClient+Auth.swift")
        XCTAssertTrue(source.contains("\"/api/v1/auth/desktop/exchange\""))
    }
}
