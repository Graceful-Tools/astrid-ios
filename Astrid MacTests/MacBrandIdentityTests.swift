//  MacBrandIdentityTests.swift
//  Whitelabel (task 97208a72) — brand-bearing values a Mac user actually SEES.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBrandIdentityTests: XCTestCase {

    /// MacAuthGateView draws this above the sign-in buttons. It was the literal
    /// `Text("astrid")` — the same bug that shipped an Astrid wordmark on a partner's
    /// web sign-in page, because a lowercase literal survives a case-sensitive sweep.
    func testWordmarkAndSloganAreBrandValues() {
        XCTAssertEqual(Brand.wordmark, "astrid")
        XCTAssertEqual(Brand.slogan, "Get it done!")
    }

    /// The Mac save panel and the iOS share sheet must agree on the filename stem —
    /// they are one feature on two platforms, and a partner should configure it once.
    func testExportFilenameUsesTheBrandPrefix() {
        var components = DateComponents()
        components.year = 2026; components.month = 7; components.day = 18
        let gregorian = Calendar(identifier: .gregorian)
        let date = gregorian.date(from: components)!

        XCTAssertEqual(MacDataExport.fileName(format: "json", date: date, calendar: gregorian),
                       "astrid-export-2026-07-18.json")
        XCTAssertEqual(MacDataExport.fileName(format: "csv", date: date, calendar: gregorian),
                       "astrid-export-2026-07-18.csv")
        XCTAssertTrue(MacDataExport.fileName(format: "json", date: date, calendar: gregorian)
            .hasPrefix(Brand.exportFilePrefix))
    }
}
#endif
