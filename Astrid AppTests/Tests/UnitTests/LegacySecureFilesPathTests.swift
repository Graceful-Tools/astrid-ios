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

final class LegacySecureFilesPathTests: XCTestCase {

    private static let roots = ["Astrid App", "Astrid Mac", "Astrid"]

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func productionSources() throws -> [(path: String, source: String)] {
        var found: [(String, String)] = []
        for root in Self.roots {
            let rootURL = repositoryRoot.appendingPathComponent(root)
            guard let walker = FileManager.default.enumerator(at: rootURL,
                                                              includingPropertiesForKeys: nil)
            else { continue }
            for case let fileURL as URL in walker where fileURL.pathExtension == "swift" {
                found.append((fileURL.lastPathComponent,
                              try String(contentsOf: fileURL, encoding: .utf8)))
            }
        }
        return found
    }

    // MARK: - Nothing MINTS the legacy path

    /// Interpolating a file id into the legacy path is what "building it" looks like in Swift.
    /// A `contains("/api/secure-files/")` check is not that, and must stay allowed — which is why
    /// this matches the interpolation rather than the bare string.
    func testNoProductionCodeBuildsTheLegacySecureFilesPath() throws {
        var offenders: [String] = []
        for (path, source) in try productionSources() where source.contains("/api/secure-files/\\(") {
            offenders.append(path)
        }
        XCTAssertEqual(offenders, [],
                       "these build the legacy /api/secure-files/ path; new writes must use "
                       + "/api/v1/secure-files/{id} so they don't persist rows in the old form:\n"
                       + offenders.joined(separator: "\n"))
    }

    /// The one place that mints a stored attachment URL. If this ever emits the legacy form,
    /// every file uploaded afterwards is another legacy row.
    func testTheUploadPathMintsTheV1Form() throws {
        let source = try String(
            contentsOf: repositoryRoot
                .appendingPathComponent("Astrid App/Core/Services/AttachmentService.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("\"/api/v1/secure-files/\\(fileId)\""),
                      "uploadSecureFile must return the v1 path")
        XCTAssertFalse(source.contains("/api/secure-files/"),
                       "the upload service has no business naming the legacy path at all")
    }

    // MARK: - The renderers still ACCEPT it

    /// Attachment URLs are PERSISTED, so rows written before the v1 cutover still hold the legacy
    /// form and always will. Tightening these matchers to v1-only would blank out every image
    /// stored before the cutover — the failure would look like "old attachments stopped loading",
    /// which is a long way from the change that caused it.
    func testTheImageLoadersStillAuthenticateLegacyStoredURLs() throws {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Astrid App/Utilities/ImageCache.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("/api/secure-files/"),
                      "ImageCache must still recognise legacy stored URLs as needing auth, or "
                      + "pre-cutover attachments load unauthenticated and fail")
        XCTAssertTrue(source.contains("/api/v1/secure-files/"))
    }
}
