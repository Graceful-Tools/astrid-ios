//  MacDataExportTests.swift
//  Astrid for Mac — Task 180199c0: export filename + content-type mapping.

#if os(macOS)
import XCTest
import UniformTypeIdentifiers
@testable import Astrid_Mac

final class MacDataExportTests: XCTestCase {

    func testFileName() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 7, day: 18))!
        XCTAssertEqual(MacDataExport.fileName(format: "json", date: date, calendar: cal), "astrid-export-2026-07-18.json")
        XCTAssertEqual(MacDataExport.fileName(format: "csv", date: date, calendar: cal), "astrid-export-2026-07-18.csv")
    }

    func testContentType() {
        XCTAssertEqual(MacDataExport.contentType(format: "csv"), .commaSeparatedText)
        XCTAssertEqual(MacDataExport.contentType(format: "json"), .json)
        XCTAssertEqual(MacDataExport.contentType(format: "anything-else"), .json)
    }
}
#endif
