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
        try String(contentsOf: RepositoryLocator.root
            .appendingPathComponent("Astrid Mac/Views/MacListEditSheet.swift"), encoding: .utf8)
    }

    /// …replaced by the SHARED placeholders, not a Mac-local copy of them.
    func testItOffersTheSharedPlaceholders() throws {
        let source = try sheet()
        XCTAssertTrue(source.contains("ListImagePlaceholders.all"),
                      "Mac should read the same palette as iOS and web")
        XCTAssertFalse(source.contains("/images/placeholders/"),
                       "…without keeping its own copy of the paths")
    }

}
#endif
