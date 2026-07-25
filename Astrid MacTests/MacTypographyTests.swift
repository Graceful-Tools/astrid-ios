//  MacTypographyTests.swift
//  Astrid for Mac — Task 913216a9: one type ramp with iOS-matching hierarchy at desktop density.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacTypographyTests: XCTestCase {

    func testHierarchyOrdering() {
        XCTAssertGreaterThan(MacTypography.detailTitleSize, MacTypography.rowTitleSize)
        XCTAssertGreaterThan(MacTypography.rowTitleSize, MacTypography.rowMetaSize)
        XCTAssertGreaterThan(MacTypography.rowMetaSize, MacTypography.labelSize)
    }

    func testDesktopDensityBand() {
        // Bigger than the old ad-hoc 15pt, but not the 19pt touch-target size.
        XCTAssertGreaterThan(MacTypography.rowTitleSize, 15)
        XCTAssertLessThan(MacTypography.rowTitleSize, 19)
        XCTAssertGreaterThanOrEqual(MacTypography.rowMetaSize, 12, "Metadata must stay legible")
    }
}
#endif
