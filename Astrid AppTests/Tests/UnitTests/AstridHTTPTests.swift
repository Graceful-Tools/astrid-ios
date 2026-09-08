//  AstridHTTPTests.swift
//  Task AITD-338 — the shared hardening primitive for requests built outside AstridAPIClient.

import XCTest
@testable import Astrid_App

final class AstridHTTPTests: XCTestCase {

    // MARK: - Multipart filename (AITD-338, finding 4)
    //
    // `uploadAttachment` wrote the user's file name raw into
    //   Content-Disposition: form-data; name="file"; filename="<name>"
    // A name carrying `"` ends the quoted string early; one carrying CR/LF ends the HEADER and
    // lets the rest of the name be read as further headers or as part content. This path is live:
    // the Share Extension hands `uploadSharedFile` a name chosen by whatever app shared the file.

    func testMultipartFilenameEscapesAnEmbeddedQuote() {
        let escaped = AstridHTTP.multipartFilename(#"in"jected.png"#)
        XCTAssertEqual(escaped, #"in\"jected.png"#,
                       "a quote must be backslash-escaped, not left to close the quoted string")
    }

    func testMultipartFilenameStripsCarriageReturnsAndNewlines() {
        let escaped = AstridHTTP.multipartFilename("evil.png\r\nContent-Type: text/html")
        XCTAssertFalse(escaped.unicodeScalars.contains("\r"), "CR would terminate the Content-Disposition header")
        XCTAssertFalse(escaped.unicodeScalars.contains("\n"), "LF would terminate the Content-Disposition header")
        XCTAssertEqual(escaped, "evil.pngContent-Type: text/html")
    }

    func testMultipartFilenameEscapesABackslashSoEscapingIsUnambiguous() {
        XCTAssertEqual(AstridHTTP.multipartFilename(#"a\b.png"#), #"a\\b.png"#)
    }

    func testMultipartFilenameLeavesAnOrdinaryNameAlone() {
        XCTAssertEqual(AstridHTTP.multipartFilename("Scan 2026-09-07.pdf"), "Scan 2026-09-07.pdf")
    }

    func testMultipartFilenameSubstitutesAPlaceholderForANameThatSanitisesToNothing() {
        XCTAssertEqual(AstridHTTP.multipartFilename("\r\n"), "file",
                       "an empty filename= is worse than a generic one — the server has nothing to key on")
    }

    // MARK: - URL construction (AITD-338, finding 1)

    func testAPIURLRefusesATraversalPath() {
        // `AttachmentService` interpolated ids straight into the path with a force-unwrap, so the
        // audit's backstop never saw them. It sees them now, and refusal is a throw, not a crash.
        XCTAssertThrowsError(try AstridHTTP.apiURL("/api/v1/tasks/abc/../admin")) { error in
            XCTAssertEqual(error as? AstridHTTPError, .unsafePath)
        }
    }

    func testAPIURLRefusesAPercentEncodedTraversalPath() {
        XCTAssertThrowsError(try AstridHTTP.apiURL("/api/v1/tasks/a%2F..%2Fadmin/attachments"))
    }

    func testAPIURLBuildsAnOrdinaryPathAgainstTheConfiguredBase() throws {
        let url = try AstridHTTP.apiURL("/api/v1/tasks/1234-abcd/attachments")
        XCTAssertEqual(url.absoluteString,
                       Constants.API.baseURL + "/api/v1/tasks/1234-abcd/attachments")
    }

    func testAPIURLCarriesQueryItems() throws {
        let url = try AstridHTTP.apiURL("/api/v1/secure-files/abc",
                                        query: [URLQueryItem(name: "info", value: "true")])
        XCTAssertEqual(url.absoluteString, Constants.API.baseURL + "/api/v1/secure-files/abc?info=true")
    }

    func testAPIURLDoesNotTrapOnAnIdCarryingASpace() throws {
        // `URL(string:)!` was the old shape, and an id with a space made it nil — a crash rather
        // than a refused request. The builder must survive it and keep the id one path component.
        let url = try AstridHTTP.apiURL("/api/v1/tasks/a b c/attachments")
        let tail: [String] = Array(url.pathComponents.suffix(3))
        XCTAssertEqual(tail, ["tasks", "a b c", "attachments"],
                       "the space must be encoded within the component, not split the path")
    }

    // MARK: - Session hardening (AITD-338, findings 2 and 3)

    func testTheSharedSessionCarriesTheConfiguredTimeout() {
        XCTAssertEqual(AstridHTTP.session.configuration.timeoutIntervalForRequest,
                       Constants.API.timeout,
                       "URLSession.shared ignored Constants.API.timeout and stalled for 60 s")
        XCTAssertEqual(AstridHTTP.session.configuration.timeoutIntervalForResource,
                       Constants.API.timeout)
    }

    func testTheSharedSessionIsBuiltThroughTheUITestHardening() {
        // Outside a UI test `harden` is a no-op, so the observable claim is that the session is
        // NOT the shared one — which is what carries the ambient cookie jar.
        XCTAssertFalse(AstridHTTP.session === URLSession.shared)
    }
}
