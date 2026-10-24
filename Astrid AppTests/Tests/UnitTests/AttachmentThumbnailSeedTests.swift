//  AttachmentThumbnailSeedTests.swift
//  AITD-308: a staged image is in the thumbnail cache the instant its comment is posted, and the
//  upload completing carries it to the real file id — so the server's copy of the comment draws
//  an image already in hand instead of downloading the one just uploaded.
//
//  Moved from the Mac suite (AITD-539): `AttachmentService` and `ThumbnailCache` are shared code,
//  and the Mac suite was the only place they were tested. Each test stages on a service of its
//  own — stub session, scratch keychain, temp caches, own defaults suite — rather than `.shared`.

import XCTest
@testable import Astrid_App

@MainActor
final class AttachmentThumbnailSeedTests: XCTestCase {

    /// A real, decodable 1×1 PNG, the same on both platforms — `PlatformImage(data:)` must succeed
    /// or the seed is a no-op and the test passes for the wrong reason.
    private let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

    private func makeService() throws -> AttachmentService {
        let id = UUID().uuidString
        let caches = FileManager.default.temporaryDirectory.appendingPathComponent("AttachmentThumbnailSeedTests-\(id)")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let suite = "AttachmentThumbnailSeedTests-\(id)"
        addTeardownBlock {
            try? FileManager.default.removeItem(at: caches)
            UserDefaults().removePersistentDomain(forName: suite)
        }
        StubURLProtocol.reset()
        return AttachmentService(session: StubURLProtocol.session(),
                                 blobConfiguration: StubURLProtocol.configuration(),
                                 keychain: KeychainService(service: "cc.astrid.tests.\(id)"),
                                 cachesDirectory: caches,
                                 defaults: try XCTUnwrap(UserDefaults(suiteName: suite)))
    }

    func testStagingAnImageSeedsItsThumbnail_AITD308() throws {
        XCTAssertNotNil(PlatformImage(data: png), "the fixture must decode")
        let service = try makeService()
        let tempId = service.saveLocallyAndUploadAsync(fileData: png, fileName: "shot.png",
                                                       mimeType: "image/png", taskId: "task-aitd308")
        defer { service.cancelUpload(tempFileId: tempId) }

        XCTAssertTrue(ThumbnailCache.shared.has(tempId),
                      "the thumbnail must be ready before the comment is posted, not after")
    }

    func testTheSeededThumbnailSurvivesTheTempToRealSwap_AITD308() throws {
        let service = try makeService()
        let tempId = service.saveLocallyAndUploadAsync(fileData: png, fileName: "shot.png",
                                                       mimeType: "image/png", taskId: "task-aitd308")
        defer { service.cancelUpload(tempFileId: tempId) }

        let realId = "real-aitd308-\(UUID().uuidString)"
        service.recordOutboxUpload(tempFileId: tempId, realFileId: realId)

        XCTAssertTrue(ThumbnailCache.shared.has(realId),
                      "aliasing copies only what is there — an unseeded cache aliased nothing, so "
                      + "the server's copy of the comment re-downloaded the image")
    }

    /// A staged video seeds nothing — a nil decode stored under the id would read as a miss.
    func testStagingANonImageSeedsNoThumbnail_AITD308() throws {
        let service = try makeService()
        let tempId = service.saveLocallyAndUploadAsync(fileData: Data(repeating: 0xAB, count: 64),
                                                       fileName: "clip.mov", mimeType: "video/quicktime",
                                                       taskId: "task-aitd308")
        defer { service.cancelUpload(tempFileId: tempId) }

        XCTAssertFalse(ThumbnailCache.shared.has(tempId))
    }
}
