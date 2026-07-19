//  MacListImageTests.swift
//  Astrid for Mac — Task 383b96af: list-image file-type support check.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListImageTests: XCTestCase {

    func testSupportedImageExtensions() {
        XCTAssertTrue(MacListImage.isSupported(filename: "logo.png"))
        XCTAssertTrue(MacListImage.isSupported(filename: "photo.JPG"))   // case-insensitive
        XCTAssertTrue(MacListImage.isSupported(filename: "pic.heic"))
        XCTAssertTrue(MacListImage.isSupported(filename: "anim.gif"))
    }

    func testUnsupportedFiles() {
        XCTAssertFalse(MacListImage.isSupported(filename: "doc.pdf"))
        XCTAssertFalse(MacListImage.isSupported(filename: "notes.txt"))
        XCTAssertFalse(MacListImage.isSupported(filename: "noextension"))
    }
}
#endif
