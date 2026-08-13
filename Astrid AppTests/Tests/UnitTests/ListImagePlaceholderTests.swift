//  ListImagePlaceholderTests.swift
//  Regression guard for Task 9a9d24bd — "List Creation / Edit should have List Image (see web,
//  ios). Not a color picker. Use iOS as example. Reuse code and business logic to keep in sync."
//
//  The 16 pastel placeholders lived as a `private let` inside iOS's ImagePickerView, a UIKit
//  view, so the Mac could not reuse them — only copy them, which is how two platforms end up
//  offering different pictures. They are shared data now.
//
//  The paths are the part that must not drift: web serves those files and both clients store the
//  path on `TaskList.imageUrl`. A typo or a reordering on one platform is a broken image on the
//  other, and nothing would fail loudly.

import XCTest
@testable import Astrid_App

final class ListImagePlaceholderTests: XCTestCase {

    /// The exact set web serves, in the order both platforms show them.
    func testThePlaceholderPathsAreTheAgreedSet() {
        XCTAssertEqual(ListImagePlaceholders.all.map(\.path), [
            "/images/placeholders/lavender.png",
            "/images/placeholders/mint.png",
            "/images/placeholders/peach.png",
            "/images/placeholders/coral.png",
            "/images/placeholders/sky.png",
            "/images/placeholders/sage.png",
            "/images/placeholders/rose.png",
            "/images/placeholders/butter.png",
            "/images/placeholders/periwinkle.png",
            "/images/placeholders/seafoam.png",
            "/images/placeholders/apricot.png",
            "/images/placeholders/lilac.png",
            "/images/placeholders/blush.png",
            "/images/placeholders/powder.png",
            "/images/placeholders/cream.png",
            "/images/placeholders/pearl.png",
        ])
    }

    /// Every entry is renderable and storable: a name, a parseable swatch colour, a path.
    func testEveryPlaceholderIsComplete() {
        for p in ListImagePlaceholders.all {
            XCTAssertFalse(p.name.isEmpty, "\(p.path) has no name")
            XCTAssertTrue(p.colorHex.hasPrefix("#") && p.colorHex.count == 7,
                          "\(p.name) has an unusable swatch colour: \(p.colorHex)")
            XCTAssertTrue(p.path.hasPrefix("/images/placeholders/"), "\(p.name) is not a placeholder path")
        }
    }

    /// Ids are the paths, so a duplicate would silently collapse two choices in a ForEach.
    func testPlaceholdersAreUnique() {
        XCTAssertEqual(Set(ListImagePlaceholders.all.map(\.id)).count, ListImagePlaceholders.all.count)
    }

    /// Telling a placeholder from an upload matters: an upload can be deleted server-side.
    func testRecognisingAPlaceholder() {
        XCTAssertTrue(ListImagePlaceholders.isPlaceholder("/images/placeholders/rose.png"))
        XCTAssertFalse(ListImagePlaceholders.isPlaceholder("/uploads/list-images/abc.jpg"))
        XCTAssertFalse(ListImagePlaceholders.isPlaceholder(nil))
        XCTAssertFalse(ListImagePlaceholders.isPlaceholder(""))
    }

    /// iOS must read the shared list rather than keeping its own copy, or the extraction bought
    /// nothing and the two can drift again.
    func testIOSUsesTheSharedPalette() throws {
        let picker = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid App/Views/Components/ImagePickerView.swift"),
            encoding: .utf8)
        XCTAssertTrue(picker.contains("ListImagePlaceholders"),
                      "ImagePickerView should read the shared palette")
        XCTAssertFalse(picker.contains("/images/placeholders/lavender.png"),
                       "…and should no longer carry its own copy of the paths")
    }
}
