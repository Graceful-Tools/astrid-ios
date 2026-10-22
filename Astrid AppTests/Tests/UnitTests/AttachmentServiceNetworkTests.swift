//  AttachmentServiceNetworkTests.swift
//  AttachmentService's HTTP paths through `StubURLProtocol` instead of the server (AITD-535):
//  what each upload, download and delete sends, how it reads the answer, and the bytes ladder
//  (staged copy → download cache → server) that both platforms' attachment views rely on.
//
//  Each test builds its own service on a temp caches directory and a throwaway defaults suite,
//  so nothing reaches the host app's caches, `UserDefaults.standard` or the network.

import XCTest
@testable import Astrid_App

@MainActor
final class AttachmentServiceNetworkTests: XCTestCase {
    private var service: AttachmentService!
    private var caches: URL!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        caches = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentServiceNetworkTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        suiteName = "AttachmentServiceNetworkTests-\(UUID().uuidString)"
        service = AttachmentService(session: StubURLProtocol.session(), cachesDirectory: caches,
                                    defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        service = nil
        try? FileManager.default.removeItem(at: caches)
        UserDefaults().removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func onlyRequest(file: StaticString = #filePath, line: UInt = #line) throws -> StubURLProtocol.Recorded {
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.count, 1, "exactly one request goes out", file: file, line: line)
        return try XCTUnwrap(sent.first, file: file, line: line)
    }

    private func bodyText(_ recorded: StubURLProtocol.Recorded) -> String {
        recorded.body.map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    // MARK: Upload through the server

    func testUploadSecureFileSendsMultipartWithContextAndReturnsThePath_AITD535() async throws {
        StubURLProtocol.respond = { _ in
            .json(#"{"fileId":"f-9","fileName":"a.txt","fileSize":5,"mimeType":"text/plain","success":true}"#)
        }

        let path = try await service.uploadSecureFile(data: Data("hello".utf8), fileName: "a\"b.txt",
                                                      mimeType: "text/plain", context: ["taskId": "t-1"])

        XCTAssertEqual(path, "/api/v1/secure-files/f-9")
        let sent = try onlyRequest()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/v1/secure-upload/request-upload")
        let contentType = try XCTUnwrap(sent.request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = bodyText(sent)
        XCTAssertTrue(body.contains(#"name="file"; filename="a\"b.txt""#), "the quote in the name is escaped")
        XCTAssertTrue(body.contains("Content-Type: text/plain\r\n\r\nhello\r\n"))
        XCTAssertTrue(body.contains("name=\"context\"\r\n\r\n{\"taskId\":\"t-1\"}\r\n"))
        XCTAssertEqual(service.uploadProgress, 1.0)
    }

    func testSmallSecureUploadGoesThroughTheServerAndClearsIsUploading_AITD535() async throws {
        StubURLProtocol.respond = { _ in
            .json(#"{"fileId":"f-1","fileName":"a","fileSize":1,"mimeType":"text/plain","success":true}"#)
        }

        let fileId = try await service.uploadToSecureEndpoint(fileData: Data("x".utf8), fileName: "a",
                                                              mimeType: "text/plain", taskId: "t-2")

        XCTAssertEqual(fileId, "f-1")
        XCTAssertEqual(try onlyRequest().path, "/api/v1/secure-upload/request-upload")
        XCTAssertFalse(service.isUploading)
    }

    func testARefusedServerUploadThrowsUploadFailed_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"error":"nope"}"#, status: 413) }

        do {
            _ = try await service.uploadSecureFile(data: Data("x".utf8), fileName: "a",
                                                   mimeType: "text/plain", context: [:])
            XCTFail("a 413 must throw")
        } catch AttachmentError.uploadFailed {
        }
        XCTAssertNotEqual(service.uploadProgress, 1.0, "a failed upload does not report completion")
    }

    func testUploadAttachmentPostsToTheTaskAndDecodesTheAttachment_AITD535() async throws {
        StubURLProtocol.respond = { _ in
            .json(#"{"id":"att-1","name":"n.pdf","url":"https://blob.example/n.pdf","type":"application/pdf","size":3,"taskId":"t-3"}"#)
        }

        let attachment = try await service.uploadAttachment(taskId: "t-3", fileData: Data("pdf".utf8),
                                                            fileName: "n.pdf", mimeType: "application/pdf")

        XCTAssertEqual(attachment.id, "att-1")
        XCTAssertEqual(attachment.taskId, "t-3")
        let sent = try onlyRequest()
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.path, "/api/v1/tasks/t-3/attachments")
        XCTAssertTrue(bodyText(sent).contains("Content-Type: application/pdf\r\n\r\npdf\r\n"))
        XCTAssertFalse(service.isUploading)
    }

    func testUploadAttachmentOnA500ThrowsInvalidResponse_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json("{}", status: 500) }

        do {
            _ = try await service.uploadAttachment(taskId: "t-3", fileData: Data(), fileName: "n",
                                                   mimeType: "text/plain")
            XCTFail("a 500 must throw")
        } catch AstridAPIError.invalidResponse {
        }
    }

    func testUploadAttachmentRefusesATraversalTaskIdBeforeSending_AITD535() async throws {
        do {
            _ = try await service.uploadAttachment(taskId: "../admin", fileData: Data(), fileName: "n",
                                                   mimeType: "text/plain")
            XCTFail("a traversal id must throw")
        } catch {
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    // MARK: Download and delete

    func testDownloadAttachmentReturnsTheBytesAndThrowsOnA404_AITD535() async throws {
        let attachment = Attachment(id: "a-1", name: "n", url: "https://blob.example/n", type: "text/plain", size: 3)
        StubURLProtocol.respond = { _ in .http(status: 200, body: Data("abc".utf8)) }

        let data = try await service.downloadAttachment(attachment)

        XCTAssertEqual(data, Data("abc".utf8))
        XCTAssertEqual(try onlyRequest().request.url?.absoluteString, "https://blob.example/n")

        StubURLProtocol.respond = { _ in .http(status: 404, body: Data()) }
        do {
            _ = try await service.downloadAttachment(attachment)
            XCTFail("a 404 must throw")
        } catch AstridAPIError.invalidResponse {
        }
    }

    func testDeleteAttachmentSendsADeleteToTheAttachmentPath_AITD535() async throws {
        StubURLProtocol.respond = { _ in .http(status: 204, body: Data()) }

        try await service.deleteAttachment(taskId: "t-4", attachmentId: "a-4")

        let sent = try onlyRequest()
        XCTAssertEqual(sent.method, "DELETE")
        XCTAssertEqual(sent.path, "/api/v1/tasks/t-4/attachments/a-4")

        StubURLProtocol.respond = { _ in .http(status: 403, body: Data()) }
        do {
            try await service.deleteAttachment(taskId: "t-4", attachmentId: "a-4")
            XCTFail("a 403 must throw")
        } catch AstridAPIError.invalidResponse {
        }
    }

    // MARK: The signed-URL route

    func testGetSecureFileDownloadURLAsksForInfoAndReturnsTheSignedURL_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"url":"https://blob.example/signed?sig=1"}"#) }

        let url = try await service.getSecureFileDownloadURL(for: "f-5")

        XCTAssertEqual(url?.absoluteString, "https://blob.example/signed?sig=1")
        let sent = try onlyRequest()
        XCTAssertEqual(sent.path, "/api/v1/secure-files/f-5")
        XCTAssertEqual(sent.query, ["info": "true"])
    }

    func testGetSecureFileDownloadURLIsNilWhenTheServerRefuses_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json(#"{"error":"forbidden"}"#, status: 403) }

        let url = try await service.getSecureFileDownloadURL(for: "f-5")

        XCTAssertNil(url)
    }

    // MARK: The bytes ladder

    func testFileDataFetchesThroughTheSignedURLThenServesTheCache_AITD535() async throws {
        StubURLProtocol.respond = { request in
            request.url?.host == "blob.example"
                ? .http(status: 200, body: Data("bytes".utf8))
                : .json(#"{"url":"https://blob.example/f-6"}"#)
        }

        let first = await service.fileData(for: "f-6")

        XCTAssertEqual(first, Data("bytes".utf8))
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/api/v1/secure-files/f-6", "/f-6"])

        let second = await service.fileData(for: "f-6")

        XCTAssertEqual(second, Data("bytes".utf8))
        XCTAssertEqual(StubURLProtocol.requests.count, 2, "the second read is served from the download cache")
    }

    func testFileDataForAStagedFileReadsItsLocalCopyAndSendsNothing_AITD535() async throws {
        let tempId = service.saveLocallyAndUploadAsync(fileData: Data("staged".utf8), fileName: "s.txt",
                                                       mimeType: "text/plain", context: ["taskId": "t-7"])

        let data = await service.fileData(for: tempId)

        XCTAssertEqual(data, Data("staged".utf8))
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testFileDataIsNilWhenTheServerHasNoSuchFile_AITD535() async throws {
        StubURLProtocol.respond = { _ in .json("{}", status: 404) }

        let data = await service.fileData(for: "missing")

        XCTAssertNil(data)
        XCTAssertNil(service.getCachedDownload(for: "missing"), "nothing is cached for a miss")
    }

    func testALegacyFileIsFetchedFromItsOwnURLNotTheSecureFilesRoute_AITD535() async throws {
        var legacy = SecureFile(id: "legacy-1", name: "l.png", size: 4, mimeType: "image/png")
        legacy.directURL = "https://blob.example/legacy.png"
        StubURLProtocol.respond = { _ in .http(status: 200, body: Data("png!".utf8)) }

        let data = await service.fileData(for: legacy)

        XCTAssertEqual(data, Data("png!".utf8))
        XCTAssertEqual(try onlyRequest().request.url?.absoluteString, "https://blob.example/legacy.png")
        XCTAssertEqual(service.getCachedDownload(for: "legacy-1"), Data("png!".utf8))
    }

    func testPrepareFilesForPreviewKeepsTheRequestedOrderAndSkipsMisses_AITD535() async throws {
        StubURLProtocol.respond = { request in
            switch request.url?.path {
            case "/api/v1/secure-files/a": return .json(#"{"url":"https://blob.example/a"}"#)
            case "/api/v1/secure-files/c": return .json(#"{"url":"https://blob.example/c"}"#)
            case "/a": return .http(status: 200, body: Data("A".utf8))
            case "/c": return .http(status: 200, body: Data("C".utf8))
            default: return .json("{}", status: 404)
            }
        }
        let files = ["a", "gone", "c"].map { SecureFile(id: $0, name: "\($0).txt", size: 1, mimeType: "text/plain") }

        let prepared = await service.prepareFilesForPreview(files: files)

        XCTAssertEqual(prepared.map(\.fileId), ["a", "c"])
        XCTAssertEqual(try Data(contentsOf: prepared[0].url), Data("A".utf8))
        XCTAssertEqual(try Data(contentsOf: prepared[1].url), Data("C".utf8))
    }

    // MARK: Pending uploads persist to the injected defaults

    func testAPendingUploadSurvivesARelaunchThroughTheDefaults_AITD535() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let tempId = service.saveLocallyAndUploadAsync(fileData: Data("p".utf8), fileName: "p.txt",
                                                       mimeType: "text/plain", context: ["taskId": "t-8"])
        service.recordOutboxUpload(tempFileId: tempId, realFileId: "real-8")

        let relaunched = AttachmentService(session: StubURLProtocol.session(), cachesDirectory: caches,
                                           defaults: defaults)

        XCTAssertEqual(relaunched.getRealFileId(for: tempId), "real-8")
        XCTAssertEqual(relaunched.pendingUploads[tempId]?.fileName, "p.txt")
    }
}
