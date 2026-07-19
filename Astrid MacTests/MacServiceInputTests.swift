//  MacServiceInputTests.swift
//  Astrid for Mac — Task 3b9883d0: "Add to Astrid" Services input parsing (title + notes).

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacServiceInputTests: XCTestCase {

    func testFirstLineIsTitleRestIsNotes() {
        let p = MacServiceInput.parse("Buy milk\nfrom the corner store\ntonight")
        XCTAssertEqual(p?.title, "Buy milk")
        XCTAssertEqual(p?.notes, "from the corner store\ntonight")
    }

    func testSingleLineHasNoNotes() {
        let p = MacServiceInput.parse("Call the dentist")
        XCTAssertEqual(p?.title, "Call the dentist")
        XCTAssertEqual(p?.notes, "")
    }

    func testLeadingBlankLinesSkipped() {
        let p = MacServiceInput.parse("\n\n   \nReal title\nnotes")
        XCTAssertEqual(p?.title, "Real title")
        XCTAssertEqual(p?.notes, "notes")
    }

    func testEmptyOrWhitespaceReturnsNil() {
        XCTAssertNil(MacServiceInput.parse(""))
        XCTAssertNil(MacServiceInput.parse("   \n\t\n "))
    }

    func testTitleCappedAt200() {
        let long = String(repeating: "a", count: 500)
        XCTAssertEqual(MacServiceInput.parse(long)?.title.count, 200)
    }
}
#endif
