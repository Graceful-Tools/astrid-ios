//  MacAttachmentThumbnailTests.swift
//  Regression tests for AITD-308 — "[mac] make the attachment thumbnail show optimistically when
//  posted from mac or from the server".
//
//  The bubble drew its files (AITD-304) but every draw started from nothing. Posting a screenshot
//  from the Mac cleared `stagedFiles` — throwing away bytes that were in memory and on screen a
//  moment earlier — and the new bubble then asked an empty ThumbnailCache, showed a grey
//  placeholder, and re-read the same bytes off disk asynchronously.
//
//  The "or from the server" half is the same omission one step later. `recordOutboxUpload` aliases
//  the cached thumbnail temp_… → realId, but `ThumbnailCache.alias` copies only if there is
//  something to copy — and the only thing that ever populated the cache was a bubble finishing its
//  own async load. An upload that completed first aliased nothing, so the server's copy of that
//  comment made the Mac DOWNLOAD an image it had just uploaded.

#if os(macOS)
import XCTest
import AppKit
@testable import Astrid_Mac

final class MacAttachmentThumbnailTests: XCTestCase {

    /// A real, decodable 1×1 PNG — `NSImage(data:)` must actually succeed or the seed is a no-op
    /// and the test would pass for the wrong reason.
    private func pngBytes() throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32))
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    // MARK: what can be drawn without waiting

    /// An image already decoded in memory draws immediately — no placeholder, no await.
    func testACachedImageNeedsNoLoadAITD308() {
        XCTAssertEqual(MacAttachmentThumbnail.source(mimeType: "image/png", hasCachedImage: true,
                                                     hasCachedBytes: false),
                       .cachedImage)
    }

    /// Bytes already downloaded to disk are readable synchronously. Awaiting for them is what put
    /// a grey box on every re-render of a file this Mac had already fetched once.
    func testAlreadyDownloadedBytesDrawWithoutAPlaceholderAITD308() {
        XCTAssertEqual(MacAttachmentThumbnail.source(mimeType: "image/jpeg", hasCachedImage: false,
                                                     hasCachedBytes: true),
                       .cachedBytes)
    }

    /// The placeholder is for the one case that genuinely has to wait.
    func testOnlyAnUnfetchedFileWaitsAITD308() {
        XCTAssertEqual(MacAttachmentThumbnail.source(mimeType: "image/png", hasCachedImage: false,
                                                     hasCachedBytes: false),
                       .mustFetch)
        XCTAssertTrue(MacAttachmentThumbnail.Source.mustFetch.showsPlaceholder)
        XCTAssertFalse(MacAttachmentThumbnail.Source.cachedImage.showsPlaceholder)
        XCTAssertFalse(MacAttachmentThumbnail.Source.cachedBytes.showsPlaceholder)
    }

    /// A document or a video is a chip, and must never start an image load — NSImage would happily
    /// hand back nil for a .mov and trade the chip for a grey box.
    func testANonImageLoadsNothingAITD308() {
        for mime in ["video/quicktime", "application/pdf", "text/plain"] {
            XCTAssertEqual(MacAttachmentThumbnail.source(mimeType: mime, hasCachedImage: true,
                                                         hasCachedBytes: true),
                           .notAnImage, mime)
        }
        XCTAssertFalse(MacAttachmentThumbnail.Source.notAnImage.showsPlaceholder)
    }

    // MARK: posted from the Mac — the bytes were already in hand

    /// Staging an image puts it in the thumbnail cache under its temp id, so the comment bubble is
    /// a cache HIT the instant it is posted. Before this, the bytes were dropped when `stagedFiles`
    /// was cleared and the bubble re-read them off disk behind a placeholder.
    @MainActor
    func testStagingAnImageSeedsItsThumbnailAITD308() throws {
        let tempId = AttachmentService.shared.saveLocallyAndUploadAsync(
            fileData: try pngBytes(), fileName: "shot.png", mimeType: "image/png",
            taskId: "task-aitd308")
        defer { AttachmentService.shared.cancelUpload(tempFileId: tempId) }

        XCTAssertTrue(ThumbnailCache.shared.has(tempId),
                      "the thumbnail must be ready before the comment is posted, not after")
    }

    /// …and the upload completing carries that thumbnail to the REAL file id. This is the "or from
    /// the server" half: when the server's copy of the comment comes back naming the real file, the
    /// image is already in hand instead of being downloaded back from the server that just got it.
    @MainActor
    func testTheSeededThumbnailSurvivesTheTempToRealSwapAITD308() throws {
        let tempId = AttachmentService.shared.saveLocallyAndUploadAsync(
            fileData: try pngBytes(), fileName: "shot.png", mimeType: "image/png",
            taskId: "task-aitd308")
        defer { AttachmentService.shared.cancelUpload(tempFileId: tempId) }

        let realId = "real-aitd308-\(UUID().uuidString)"
        AttachmentService.shared.recordOutboxUpload(tempFileId: tempId, realFileId: realId)

        XCTAssertTrue(ThumbnailCache.shared.has(realId),
                      "aliasing copies only what is there — an unseeded cache aliased nothing, so "
                      + "the server's copy of the comment re-downloaded the image")
    }

    /// A staged video or document seeds nothing — there is no image to decode, and a nil decode
    /// stored under the id would be indistinguishable from a miss.
    @MainActor
    func testStagingANonImageSeedsNoThumbnailAITD308() {
        let tempId = AttachmentService.shared.saveLocallyAndUploadAsync(
            fileData: Data(repeating: 0xAB, count: 64), fileName: "clip.mov",
            mimeType: "video/quicktime", taskId: "task-aitd308")
        defer { AttachmentService.shared.cancelUpload(tempFileId: tempId) }

        XCTAssertFalse(ThumbnailCache.shared.has(tempId))
    }
}
#endif
