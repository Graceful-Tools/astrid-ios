//  LegacyAPIClientRetiredTests.swift
//  Regression guard for AITD-504 — the legacy `APIClient` / `APIEndpoint` pair is gone.
//
//  Task 2023c90f was closed on 2026-08-16 with no commit, and ASTRID.md went on saying "still
//  open" for two months while four services kept sending sign-in, session, profile, account and
//  upload calls through a second HTTP client. Two clients is two places to set — or forget — the
//  platform header, the path-safety guard, the timeouts and the UI-test network isolation. The
//  legacy one had no isolation at all, so a UI test's sign-in went through the real cookie jar.
//
//  Read the source rather than the symbol table: a type that still compiles in some corner of the
//  app is exactly what this is meant to catch.
//
//  The one behaviour the legacy client had that the other did not: it lifted the session out of a
//  sign-in's `Set-Cookie` into the Keychain. Apple and Google sign-in depend on it entirely —
//  without it a successful sign-in is followed by a 401 on the very next request. So that moved
//  too, and is pinned below.

import XCTest
@testable import Astrid_App

final class LegacyAPIClientRetiredTests: XCTestCase {

    private static let sourceRoots = ["Astrid App", "Astrid Mac"]

    private func swiftSources() throws -> [(path: String, text: String)] {
        let root = RepositoryLocator.root
        var result: [(String, String)] = []
        for dir in Self.sourceRoots {
            let base = root.appendingPathComponent(dir)
            guard let walker = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
            for case let url as URL in walker where url.pathExtension == "swift" {
                result.append((url.path.replacingOccurrences(of: root.path + "/", with: ""),
                               try String(contentsOf: url, encoding: .utf8)))
            }
        }
        return result
    }

    func testAITD504_TheLegacyClientFilesAreDeleted() {
        for file in ["Astrid App/Core/Networking/APIClient.swift",
                     "Astrid App/Core/Networking/APIEndpoint.swift"] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: RepositoryLocator.root.appendingPathComponent(file).path),
                           "\(file) should be gone — AstridAPIClient is the one client (ASTRID.md §2a)")
        }
    }

    func testAITD504_NoSourceDeclaresOrUsesASecondClient() throws {
        // Word boundaries, or `AstridAPIClient.shared` reads as `APIClient.shared`.
        let forbidden = [#"\benum APIEndpoint\b"#, #"\bclass APIClient\b"#, #"\bAPIClientProtocol\b"#,
                         #"\bAPIClient\.shared\b"#, #"\bas\?? APIError\b"#]
            .map { try! NSRegularExpression(pattern: $0) }
        var hits: [String] = []
        for source in try swiftSources() {
            let range = NSRange(source.text.startIndex..., in: source.text)
            for regex in forbidden where regex.firstMatch(in: source.text, range: range) != nil {
                hits.append("\(source.path): \(regex.pattern)")
            }
        }
        XCTAssertTrue(hits.isEmpty, "The legacy client is still referenced:\n" + hits.joined(separator: "\n"))
    }

    // MARK: - The session a sign-in hands back as Set-Cookie

    private let url = URL(string: "https://www.astrid.cc/api/v1/auth/apple")!

    func testAITD504_ASignInSessionCookieIsCaptured() {
        let header = SessionCookieCapture.cookieHeader(
            fromResponseHeaders: ["Set-Cookie": "__Secure-next-auth.session-token=abc; Path=/; HttpOnly; Secure"],
            url: url)
        XCTAssertEqual(header, "__Secure-next-auth.session-token=abc")
    }

    func testAITD504_OnlyAuthCookiesAreKept() {
        let header = SessionCookieCapture.cookieHeader(
            fromResponseHeaders: ["Set-Cookie": "theme=dark; Path=/, next-auth.csrf-token=c; Path=/, next-auth.session-token=s; Path=/"],
            url: url)
        XCTAssertEqual(header, "next-auth.csrf-token=c; next-auth.session-token=s")
    }

    func testAITD504_AResponseWithoutAuthCookiesCapturesNothing() {
        XCTAssertNil(SessionCookieCapture.cookieHeader(fromResponseHeaders: ["Set-Cookie": "theme=dark; Path=/"], url: url))
        XCTAssertNil(SessionCookieCapture.cookieHeader(fromResponseHeaders: [:], url: url))
    }

    // MARK: - What the callers branched on

    /// The legacy client reported a 401 as `httpError(401)`; this one says `.unauthorized`. The
    /// background session check signs the user out on a 401 and must still see one.
    func testAITD504_UnauthorizedReadsAs401() {
        XCTAssertEqual(AstridAPIError.unauthorized.httpStatusCode, 401)
        XCTAssertEqual(AstridAPIError.httpError(statusCode: 404, message: "").httpStatusCode, 404)
        XCTAssertNil(AstridAPIError.invalidResponse.httpStatusCode)
    }

    /// The legacy client decoded `{"error": "..."}` for the message a sign-in or profile screen
    /// shows. This one keeps the raw body, so the message is read out of it.
    func testAITD504_TheServerMessageIsReadFromTheBody() {
        XCTAssertEqual(AstridAPIError.httpError(statusCode: 400, message: "{\"error\":\"Email taken\"}").serverMessage,
                       "Email taken")
        XCTAssertNil(AstridAPIError.httpError(statusCode: 502, message: "<html>Bad gateway</html>").serverMessage)
        XCTAssertNil(AstridAPIError.unauthorized.serverMessage)
    }
}
