//  LegacyMCPAttachmentTests.swift
//  AITD-355 — render the legacy Attachment rows MCP writes, alongside SecureFile.
//
//  The v1 task response carries TWO attachment relations. `secureFiles` are real secure-file
//  records, fetched by id through `/api/v1/secure-files/{id}`. `attachments` is the legacy table,
//  whose only writers are the two MCP handlers; those rows carry a plain fetchable `url` and have
//  NO secure-files record, so resolving one of their ids through that route 404s.
//
//  iOS was already LISTING them — so this was never web's "invisible in the product" bug — but
//  the conversion to `SecureFile` dropped `url`, leaving the only field that makes them
//  retrievable on the floor. The thumbnail appeared, the tap did nothing. That is worse than a
//  missing attachment: a missing one is visibly a bug, a dead one reads as a bad connection.

import XCTest
@testable import Astrid_App

final class LegacyMCPAttachmentTests: XCTestCase {

    private func legacy(id: String = "mcp-1",
                        name: String = "spec.pdf",
                        url: String = "/api/secure-files/mcp-1") -> Attachment {
        Attachment(id: id, name: name, url: url, type: "application/pdf", size: 1024)
    }

    private func secure(id: String, name: String = "photo.png") -> SecureFile {
        SecureFile(id: id, name: name, size: 2048, mimeType: "image/png")
    }

    private func task(secureFiles: [SecureFile]? = nil,
                      attachments: [Attachment]? = nil,
                      comments: [Comment]? = nil) -> Task {
        Task(id: "t1", title: "Task", listIds: [],
             attachments: attachments, secureFiles: secureFiles, comments: comments)
    }

    // MARK: - The bug: the url has to survive the conversion

    func testALegacyAttachmentKeepsTheURLThatMakesItFetchable() {
        let files = task(attachments: [legacy()]).allSecureFiles()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.directURL, "/api/secure-files/mcp-1",
                       "dropping the url leaves the file listed but unfetchable — that is AITD-355")
    }

    /// The routing decision, as a value rather than a network call.
    func testALegacyAttachmentRoutesAroundTheSecureFilesEndpoint() {
        let file = SecureFile(legacy: legacy())
        guard case .directURL(let url) = file.source else {
            return XCTFail("a legacy attachment must resolve to its own url, got \(file.source)")
        }
        XCTAssertEqual(url.absoluteString, Constants.API.baseURL + "/api/secure-files/mcp-1")
    }

    /// A real secure file has no `directURL`, so it must still go the signed-URL route. If this
    /// ever flipped, every ordinary attachment in the app would try to fetch a path it does not
    /// have.
    func testARealSecureFileStillUsesTheSignedURLRoute() {
        XCTAssertEqual(secure(id: "sf-1").source, .secureFilesRoute)
    }

    /// A file staged on the device and not uploaded yet is checked FIRST — it has no server
    /// record of any kind, of either sort.
    func testAStagedFileIsServedLocallyEvenIfItSomehowCarriesAURL() {
        var staged = secure(id: "temp_abc")
        staged.directURL = "/api/secure-files/whatever"
        XCTAssertEqual(staged.source, .localStaging)
    }

    /// Stored URLs exist in both shapes, because different generations of the product persisted
    /// them differently. Both have to resolve or old rows go dark.
    func testBothStoredURLShapesResolve() {
        XCTAssertEqual(SecureFile.absoluteURL(from: "https://cdn.example.com/f.png")?.absoluteString,
                       "https://cdn.example.com/f.png")
        XCTAssertEqual(SecureFile.absoluteURL(from: "/api/v1/secure-files/x")?.absoluteString,
                       Constants.API.baseURL + "/api/v1/secure-files/x")
        XCTAssertNil(SecureFile.absoluteURL(from: "not-a-path"),
                     "a value that is neither absolute nor rooted cannot be resolved, and "
                     + "guessing at a base for it would produce a URL that 404s quietly")
    }

    // MARK: - The contract's ordering and dedupe

    func testOrderIsSecureFilesThenMCPAttachmentsThenCommentFiles() {
        let comment = Comment(id: "c1", content: "", type: .TEXT, taskId: "t1",
                              secureFiles: [secure(id: "from-comment")])
        let files = task(secureFiles: [secure(id: "sf-1")],
                         attachments: [legacy(id: "mcp-1")],
                         comments: [comment]).allSecureFiles()
        XCTAssertEqual(files.map(\.id), ["sf-1", "mcp-1", "from-comment"])
    }

    /// "Dedupe by url as well as id — the ids come from two different tables."
    func testTheSameFileArrivingTwiceByURLIsListedOnce() {
        let files = task(attachments: [legacy(id: "a", url: "/api/secure-files/shared"),
                                       legacy(id: "b", url: "/api/secure-files/shared")])
            .allSecureFiles()
        XCTAssertEqual(files.count, 1, "same url, different table ids — one file, not two")
    }

    func testDuplicateIdsAreStillCollapsed() {
        let comment = Comment(id: "c1", content: "", type: .TEXT, taskId: "t1",
                              secureFiles: [secure(id: "sf-1")])
        let files = task(secureFiles: [secure(id: "sf-1")], comments: [comment]).allSecureFiles()
        XCTAssertEqual(files.count, 1)
    }

    /// Two DIFFERENT files must not collapse just because neither carries a url — every real
    /// secure file has `directURL == nil`, so a naive url-dedupe would fold them all into one.
    func testFilesWithoutURLsAreNotTreatedAsDuplicates() {
        let files = task(secureFiles: [secure(id: "sf-1"), secure(id: "sf-2")]).allSecureFiles()
        XCTAssertEqual(files.map(\.id), ["sf-1", "sf-2"])
    }

    // MARK: - Decoding is untouched

    /// `directURL` is deliberately outside `CodingKeys`. The API's secure-file shape has no such
    /// field, and adding one to the decode would change what every existing response means.
    func testTheAPIShapeDecodesExactlyAsBefore() throws {
        let json = #"{"id":"sf-1","originalName":"a.png","fileSize":10,"mimeType":"image/png"}"#
        let file = try JSONDecoder().decode(SecureFile.self, from: Data(json.utf8))
        XCTAssertEqual(file.id, "sf-1")
        XCTAssertEqual(file.name, "a.png")
        XCTAssertNil(file.directURL, "a decoded secure file has no direct url — it is fetched by id")
        XCTAssertEqual(file.source, .secureFilesRoute)
    }

    // MARK: - One union, not two

    /// The model and `TaskAttachmentSectionView` each had a copy of this rule, and only the
    /// view's ran — so the model's could not have been the fix. The view must ASK.
    func testTheAttachmentSectionUsesTheSharedUnion() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Astrid App/Views/Tasks/TaskAttachmentSectionView.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("task.allSecureFiles("),
                      "the view must ask the shared union rather than restating it")
        XCTAssertFalse(source.contains("SecureFile(\n"),
                       "the view must not build SecureFiles itself — that is where the url got lost")
    }

    /// This surface offers no deletion, and must not start: the delete path is the secure-files
    /// endpoint, which does not know legacy rows and would fail on exactly the files this task
    /// made visible.
    func testTheAttachmentSectionOffersNoDeletion() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Astrid App/Views/Tasks/TaskAttachmentSectionView.swift"),
            encoding: .utf8)
        XCTAssertFalse(source.contains("onDelete"),
                       "task attachments are not deletable here; the delete path cannot serve "
                       + "legacy MCP rows, so offering it would fail on them alone")
    }
}
