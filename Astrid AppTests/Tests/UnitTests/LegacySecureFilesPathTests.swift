//  LegacySecureFilesPathTests.swift
//  AITD-366 — "Say whether iOS builds /api/secure-files/{id} itself or only renders stored URLs."
//
//  The answer was: only renders. Every path iOS CONSTRUCTS is `/api/v1/secure-files/{id}`; the
//  legacy form appears in this codebase exclusively inside `contains(...)` checks, applied to a
//  URL that arrived from the server. The 19 `iOS-app` hits the census counted are old comment and
//  message content being displayed, the same cause as web's own traffic on that route.
//
//  These tests keep that answer true rather than merely recorded. Web has declared the legacy
//  route a PERMANENT ALIAS — exempt from the 2026-11-01 sunset, served indefinitely — so the risk
//  is not that rendering breaks. It is the opposite: nothing forces the legacy form out, so a new
//  call site could start MINTING it and no one would notice, and every URL written in that form
//  is persisted into a row that outlives the migration.
//
//  Hence two halves, pulling opposite ways and both required:
//    - nothing may BUILD the legacy path
//    - the renderers must keep ACCEPTING it, for rows already written

import XCTest
@testable import Astrid_App

final class LegacySecureFilesPathTests: XCTestCase {

    // MARK: - The renderers still ACCEPT it

    /// Attachment URLs are PERSISTED, so rows written before the v1 cutover still hold the legacy
    /// form and always will. Tightening these matchers to v1-only would blank out every image
    /// stored before the cutover — the failure would look like "old attachments stopped loading",
    /// which is a long way from the change that caused it.
    func testTheImageLoadersStillAuthenticateLegacyStoredURLs_AITD538() throws {
        let base = "https://www.astrid.cc"
        XCTAssertTrue(SecureFilesURL.needsSession(try XCTUnwrap(URL(string: "\(base)/api/secure-files/abc"))),
                      "a legacy stored URL still needs the session, or pre-cutover attachments fail")
        XCTAssertTrue(SecureFilesURL.needsSession(try XCTUnwrap(URL(string: "\(base)/api/v1/secure-files/abc"))))
        XCTAssertTrue(SecureFilesURL.needsSession(
            try XCTUnwrap(URL(string: "\(base)/api/v1/secure-files/abc?info=true"))))
        XCTAssertFalse(SecureFilesURL.needsSession(
            try XCTUnwrap(URL(string: "https://example.blob.vercel-storage.com/avatar.png"))),
                       "a public image is fetched without the cookie")
        XCTAssertFalse(SecureFilesURL.needsSession(
            try XCTUnwrap(URL(string: "\(base)/proxy?u=/api/v1/secure-files/abc"))),
                       "only the path decides, never a query that names the route")
    }
}
