//  MacAttachmentIconTests.swift
//  Astrid for Mac — Task 6a25494a: attachment type→symbol + human-readable size mapping.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacAttachmentIconTests: XCTestCase {

    func testSymbolByMimeType() {
        XCTAssertEqual(MacAttachmentIcon.symbol(type: "image/png", name: "a"), "photo")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: "video/quicktime", name: "a"), "film")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: "audio/mpeg", name: "a"), "waveform")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: "application/pdf", name: "a"), "doc.richtext")
    }

    func testSymbolFallsBackToExtension() {
        XCTAssertEqual(MacAttachmentIcon.symbol(type: nil, name: "photo.JPG"), "photo")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: "", name: "clip.mov"), "film")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: nil, name: "archive.zip"), "doc.zipper")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: nil, name: "notes.md"), "doc.text")
        XCTAssertEqual(MacAttachmentIcon.symbol(type: nil, name: "unknown.bin"), "paperclip")
    }

    func testHumanSize() {
        XCTAssertEqual(MacAttachmentIcon.humanSize(0), "")
        XCTAssertEqual(MacAttachmentIcon.humanSize(-5), "")
        XCTAssertEqual(MacAttachmentIcon.humanSize(512), "512 B")
        XCTAssertEqual(MacAttachmentIcon.humanSize(2048), "2.0 KB")
        XCTAssertEqual(MacAttachmentIcon.humanSize(5 * 1024 * 1024), "5.0 MB")
    }
}
#endif
