//  MacListImagePickerTests.swift
//  Regression guard for Task 9a9d24bd — "List Creation / Edit should have List Image. Not a color
//  picker." on Mac.
//
//  The Mac's edit sheet offered a row of colour swatches and an upload button that only worked
//  for a list that already existed — so a list created on Mac could not be given a picture at
//  all. It now offers the same 16 shared placeholders iOS and web do.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacListImagePickerTests: XCTestCase {

    private func sheet() throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/Views/MacListEditSheet.swift"), encoding: .utf8)
    }

    /// The colour swatch row is gone — that is the literal ask.
    func testTheColourSwatchRowIsGone() throws {
        XCTAssertFalse(try sheet().contains("mac.color_label"),
                       "The colour picker is replaced by a list image picker (task 9a9d24bd)")
    }

    /// …replaced by the SHARED placeholders, not a Mac-local copy of them.
    func testItOffersTheSharedPlaceholders() throws {
        let source = try sheet()
        XCTAssertTrue(source.contains("ListImagePlaceholders.all"),
                      "Mac should read the same palette as iOS and web")
        XCTAssertFalse(source.contains("/images/placeholders/"),
                       "…without keeping its own copy of the paths")
    }

    /// The Mac sees exactly what iOS sees — the point of extracting the palette.
    func testTheMacSeesTheSamePlaceholdersAsIOS() {
        XCTAssertEqual(ListImagePlaceholders.all.count, 16)
        XCTAssertEqual(ListImagePlaceholders.all.first?.path, "/images/placeholders/lavender.png")
        XCTAssertEqual(ListImagePlaceholders.all.last?.path, "/images/placeholders/pearl.png")
    }

    /// A placeholder needs no upload and no id, so it must survive list CREATION — previously
    /// impossible on Mac, where the only image affordance required an existing list.
    func testAnImageChosenWhileCreatingIsApplied() throws {
        let source = try sheet()
        XCTAssertTrue(source.contains("chosenImage"),
                      "A placeholder picked before the list exists must be applied after creation")
    }
}
#endif
