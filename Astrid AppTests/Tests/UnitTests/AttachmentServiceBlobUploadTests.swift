//
//  AttachmentServiceBlobUploadTests.swift
//  AttachmentService's two paths that go straight to Vercel Blob (AITD-535): a file over 4 MB
//  (`uploadToSecureEndpoint` → `uploadDirectToBlob`) and an edited attachment
//  (`updateAttachment`). Both read the session cookie and refuse to start without one, so the
//  service gets a scratch keychain; the Blob PUT goes through the stub's configuration.
//

import XCTest
@testable import Astrid_App

@MainActor
final class AttachmentServiceBlobUploadTests: XCTestCase {
    private var service: AttachmentService!
    private var keychain: KeychainService!
    private var caches: URL!
    private var suiteName: String!

    private static let cookie = "__Secure-next-auth.session-token=abc"

    override func setUp() async throws {
        try await super.setUp()
        StubURLProtocol.reset()
        keychain = KeychainService(service: "cc.astrid.tests.\(UUID().uuidString)")
        caches = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttachmentServiceBlobUploadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        suiteName = "AttachmentServiceBlobUploadTests-\(UUID().uuidString)"
        service = AttachmentService(session: StubURLProtocol.session(),
                                    blobConfiguration: StubURLProtocol.configuration(),
                                    keychain: keychain, cachesDirectory: caches,
                                    defaults: try XCTUnwrap(UserDefaults(suiteName: suiteName)))
    }

    override func tearDown() async throws {
        StubURLProtocol.reset()
        try? keychain.deleteSessionCookie()
        service = nil
        try? FileManager.default.removeItem(at: caches)
        UserDefaults().removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// Just over the 4 MB line, so the upload takes the direct-to-Blob path.
    private let largeFile = Data(repeating: 7, count: 4 * 1024 * 1024 + 1)

    // MARK: Large upload: get-upload-url → Blob PUT

    func testALargeFileAsksForAnUploadURLThenPutsTheBytesToBlob_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { request in
            request.url?.host == "blob.example"
                ? .json("{}")
                : .json(#"{"uploadToken":"tok","pathname":"p/big.mov","fileId":"f-big","uploadUrl":"https://blob.example/p/big.mov"}"#)
        }

        let fileId = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                              mimeType: "video/quicktime", context: ["taskId": "t-1"])

        XCTAssertEqual(fileId, "f-big")
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.map(\.path), ["/api/v1/secure-upload/get-upload-url", "/p/big.mov"])

        let ask = sent[0]
        XCTAssertEqual(ask.method, "POST")
        XCTAssertEqual(ask.request.value(forHTTPHeaderField: "Cookie"), Self.cookie)
        XCTAssertEqual(ask.jsonBody?["fileName"] as? String, "big.mov")
        XCTAssertEqual(ask.jsonBody?["fileType"] as? String, "video/quicktime")
        XCTAssertEqual(ask.jsonBody?["fileSize"] as? Int, largeFile.count)
        XCTAssertEqual(ask.jsonBody?["context"] as? [String: String], ["taskId": "t-1"])

        let put = sent[1]
        XCTAssertEqual(put.method, "PUT")
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "Authorization"), "Bearer tok")
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
        XCTAssertNil(put.request.value(forHTTPHeaderField: "Cookie"), "the session cookie never goes to Blob")
        XCTAssertEqual(service.uploadProgress, 1.0)
        XCTAssertFalse(service.isUploading)
    }

    // MARK: Presigned upload (AITD-558)
    //
    // The server is moving off `BLOB_READ_WRITE_TOKEN`, which every `uploadToken` is derived
    // from. A presigned server sends `presigned: { uploadUrl, headers }` — the whole request,
    // composed with `@vercel/blob`'s `presignUrl`, so the vendor's query and header rules live
    // on the server and move with its SDK rather than being frozen into an App Store build.

    private static let presignedURL =
        "https://blob.example/api/blob/?pathname=files%2Fu%2Ff-big.mov&vercel-blob-delegation=d.e&vercel-blob-signature=s1"

    func testAPresignedResponseIsPutAsGivenWithNoBearerToken_AITD558() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { request in
            request.url?.host == "blob.example"
                ? .json(#"{"url":"https://blob.example/files/u/f-big.mov","pathname":"files/u/f-big.mov"}"#)
                : .json(#"{"pathname":"files/u/f-big.mov","fileId":"f-big","presigned":{"uploadUrl":"\#(Self.presignedURL)","headers":{"x-api-version":"12","x-vercel-blob-store-id":"abc","x-vercel-blob-access":"public"}}}"#)
        }

        let fileId = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                              mimeType: "video/quicktime", context: ["taskId": "t-1"])

        XCTAssertEqual(fileId, "f-big")
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.count, 2)
        let put = sent[1]
        XCTAssertEqual(put.method, "PUT")
        XCTAssertEqual(put.request.url?.absoluteString, Self.presignedURL,
                       "the signed query is the credential — it must reach Blob untouched")
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "x-api-version"), "12")
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "x-vercel-blob-store-id"), "abc")
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "x-vercel-blob-access"), "public")
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
        XCTAssertNil(put.request.value(forHTTPHeaderField: "Authorization"),
                     "a presigned PUT carries no bearer token — there is none to send")
        XCTAssertNil(put.request.value(forHTTPHeaderField: "Cookie"), "the session cookie never goes to Blob")
        XCTAssertEqual(put.body, largeFile)
        XCTAssertEqual(service.uploadProgress, 1.0)
    }

    func testAResponseCarryingBothShapesTakesThePresignedOne_AITD558() async throws {
        // The additive migration step: the server sends the legacy fields alongside the new ones.
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { request in
            request.url?.host == "blob.example"
                ? .json("{}")
                : .json(#"{"uploadToken":"tok","uploadUrl":"https://legacy.example/p","pathname":"p","fileId":"f","presigned":{"uploadUrl":"\#(Self.presignedURL)","headers":{}}}"#)
        }

        _ = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                     mimeType: "video/quicktime", context: [:])

        let put = StubURLProtocol.requests[1]
        XCTAssertEqual(put.request.url?.host, "blob.example")
        XCTAssertNil(put.request.value(forHTTPHeaderField: "Authorization"))
    }

    func testAResponseWithNeitherShapeFailsBeforeBlob_AITD558() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { _ in .json(#"{"pathname":"p","fileId":"f"}"#) }

        do {
            _ = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                         mimeType: "video/quicktime", context: [:])
            XCTFail("a response with no way to upload must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 1)
    }

    func testALargeFileWithNoSessionCookieSendsNothing_AITD535() async throws {
        do {
            _ = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                         mimeType: "video/quicktime", context: [:])
            XCTFail("an upload with no session must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testARefusedUploadURLNeverReachesBlob_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { _ in .json(#"{"error":"too big"}"#, status: 413) }

        do {
            _ = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                         mimeType: "video/quicktime", context: [:])
            XCTFail("a refused upload URL must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/api/v1/secure-upload/get-upload-url"])
    }

    func testABlobRefusalFailsTheUploadWithoutReportingDone_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { request in
            request.url?.host == "blob.example"
                ? .json("{}", status: 403)
                : .json(#"{"uploadToken":"tok","pathname":"p","fileId":"f","uploadUrl":"https://blob.example/p"}"#)
        }

        do {
            _ = try await service.uploadToSecureEndpoint(fileData: largeFile, fileName: "big.mov",
                                                         mimeType: "video/quicktime", context: [:])
            XCTFail("a Blob refusal must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertLessThan(service.uploadProgress, 1.0)
        XCTAssertFalse(service.isUploading)
    }

    // MARK: Edited attachment: upload-url → Blob PUT → confirm-upload

    private func respondToUpdate(blobStatus: Int = 200, confirmStatus: Int = 200) {
        StubURLProtocol.respond = { request in
            switch request.url?.path {
            case "/api/v1/secure-files/f-9/upload-url":
                return .json(#"{"uploadUrl":"https://blob.example/f-9.png","pathname":"f-9.png","headers":{"x-api-version":"7","authorization":"Bearer blob"},"oldBlobUrl":"https://blob.example/old.png"}"#)
            case "/f-9.png":
                return .json(#"{"url":"https://blob.example/f-9-v2.png","pathname":"f-9-v2.png"}"#, status: blobStatus)
            case "/api/v1/secure-files/f-9/confirm-upload":
                return .json(#"{"id":"f-9","originalName":"shot.png","mimeType":"image/png","fileSize":4,"updatedAt":"2026-10-23T00:00:00Z","success":true}"#,
                             status: confirmStatus)
            case "/api/v1/secure-files/f-9":
                return .json(#"{"url":"https://blob.example/f-9-v2.png"}"#)
            case "/f-9-v2.png":
                return .http(status: 200, body: Data("new!".utf8))
            default:
                return .json("{}", status: 404)
            }
        }
    }

    func testUpdatingAnAttachmentPutsTheNewBytesConfirmsAndReturnsTheFile_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        respondToUpdate()
        let edited = Data("new!".utf8)
        let updated = expectation(forNotification: .attachmentUpdated, object: nil) { note in
            note.userInfo?["fileId"] as? String == "f-9"
        }

        let file = try await service.updateAttachment(fileId: "f-9", newFileData: edited, mimeType: "image/png")

        XCTAssertEqual(file, SecureFile(id: "f-9", name: "shot.png", size: 4, mimeType: "image/png"))
        let sent = StubURLProtocol.requests
        XCTAssertEqual(sent.map(\.path), ["/api/v1/secure-files/f-9/upload-url", "/f-9.png",
                                          "/api/v1/secure-files/f-9/confirm-upload"])

        XCTAssertEqual(sent[0].request.value(forHTTPHeaderField: "Cookie"), Self.cookie)
        XCTAssertEqual(sent[0].jsonBody?["mimeType"] as? String, "image/png")
        XCTAssertEqual(sent[0].jsonBody?["fileSize"] as? Int, edited.count)

        XCTAssertEqual(sent[1].method, "PUT")
        XCTAssertEqual(sent[1].request.value(forHTTPHeaderField: "x-api-version"), "7",
                       "the headers the server hands out are passed to Blob as given")
        XCTAssertEqual(sent[1].request.value(forHTTPHeaderField: "authorization"), "Bearer blob")
        XCTAssertNil(sent[1].request.value(forHTTPHeaderField: "Cookie"), "the session cookie never goes to Blob")
        XCTAssertEqual(sent[1].body, edited)

        XCTAssertEqual(sent[2].request.value(forHTTPHeaderField: "Cookie"), Self.cookie)
        XCTAssertEqual(sent[2].jsonBody?["blobUrl"] as? String, "https://blob.example/f-9-v2.png")
        XCTAssertEqual(sent[2].jsonBody?["oldBlobUrl"] as? String, "https://blob.example/old.png")
        XCTAssertEqual(sent[2].jsonBody?["fileSize"] as? Int, edited.count)

        await fulfillment(of: [updated], timeout: 1)
        XCTAssertEqual(service.uploadProgress, 1.0)
        XCTAssertFalse(service.isUploading)
    }

    func testUpdatingAnAttachmentTakesAPresignedRequestWithNoAppChange_AITD558() async throws {
        // `secure-files/:id/upload-url` already hands out the whole request (URL + headers), so
        // the server can swap in a presigned one and this path keeps working as shipped.
        try keychain.saveSessionCookie(Self.cookie)
        let signed = "https://blob.example/api/blob/?pathname=f-9.png&vercel-blob-delegation=d.e&vercel-blob-signature=s1"
        StubURLProtocol.respond = { request in
            switch request.url?.path {
            case "/api/v1/secure-files/f-9/upload-url":
                return .json(#"{"uploadUrl":"\#(signed)","pathname":"f-9.png","headers":{"x-api-version":"12","x-vercel-blob-store-id":"abc"}}"#)
            case "/api/blob":
                return .json(#"{"url":"https://blob.example/f-9-v2.png","pathname":"f-9-v2.png"}"#)
            case "/api/v1/secure-files/f-9/confirm-upload":
                return .json(#"{"id":"f-9","originalName":"shot.png","mimeType":"image/png","fileSize":4,"updatedAt":"2026-10-23T00:00:00Z","success":true}"#)
            default:
                return .json(#"{"url":"https://blob.example/f-9-v2.png"}"#)
            }
        }

        _ = try await service.updateAttachment(fileId: "f-9", newFileData: Data("new!".utf8), mimeType: "image/png")

        let put = StubURLProtocol.requests[1]
        XCTAssertEqual(put.request.url?.absoluteString, signed)
        XCTAssertEqual(put.request.value(forHTTPHeaderField: "x-vercel-blob-store-id"), "abc")
        XCTAssertNil(put.request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(StubURLProtocol.requests[2].jsonBody?["blobUrl"] as? String, "https://blob.example/f-9-v2.png")
    }

    func testUpdatingAnAttachmentDropsItsCachedDownload_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        StubURLProtocol.respond = { request in
            request.url?.host == "blob.example"
                ? .http(status: 200, body: Data("old!".utf8))
                : .json(#"{"url":"https://blob.example/f-9-v1.png"}"#)
        }
        let before = await service.fileData(for: "f-9")
        XCTAssertEqual(before, Data("old!".utf8))
        respondToUpdate()

        _ = try await service.updateAttachment(fileId: "f-9", newFileData: Data("new!".utf8), mimeType: "image/png")
        let after = await service.fileData(for: "f-9")

        XCTAssertEqual(after, Data("new!".utf8), "the edited bytes are fetched again, not served from the old cache")
    }

    func testUpdatingAnAttachmentWithNoSessionCookieSendsNothing_AITD535() async throws {
        do {
            _ = try await service.updateAttachment(fileId: "f-9", newFileData: Data("x".utf8), mimeType: "image/png")
            XCTFail("an update with no session must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertTrue(StubURLProtocol.requests.isEmpty)
    }

    func testABlobRefusalStopsTheUpdateBeforeTheConfirm_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        respondToUpdate(blobStatus: 500)

        do {
            _ = try await service.updateAttachment(fileId: "f-9", newFileData: Data("x".utf8), mimeType: "image/png")
            XCTFail("a Blob refusal must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertEqual(StubURLProtocol.requests.map(\.path), ["/api/v1/secure-files/f-9/upload-url", "/f-9.png"],
                       "nothing is confirmed against bytes Blob never took")
    }

    func testARefusedConfirmFailsTheUpdate_AITD535() async throws {
        try keychain.saveSessionCookie(Self.cookie)
        respondToUpdate(confirmStatus: 409)

        do {
            _ = try await service.updateAttachment(fileId: "f-9", newFileData: Data("x".utf8), mimeType: "image/png")
            XCTFail("a refused confirm must throw")
        } catch {
            XCTAssertEqual(error as? AttachmentError, .uploadFailed)
        }
        XCTAssertEqual(StubURLProtocol.requests.count, 3)
    }
}
