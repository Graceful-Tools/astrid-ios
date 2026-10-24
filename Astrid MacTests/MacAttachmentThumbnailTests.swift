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

}
#endif
