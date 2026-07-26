//  MacTypographyTests.swift
//  Astrid for Mac — one type ramp with the iOS hierarchy at MAC density.
//
//  The earlier version of this file pinned rowTitle > 15pt, which encoded the bug: those sizes
//  were derived from iOS's numbers (19pt title / 17pt body) and read oversized in a Mac window,
//  where the system body is 13pt. The ramp is now anchored to the MAC system size, so the rule is
//  "iOS's hierarchy, macOS's density" rather than a magic band.

#if os(macOS)
import XCTest
import AppKit
@testable import Astrid_Mac

final class MacTypographyTests: XCTestCase {

    /// The visual hierarchy iOS has: detail title > row title > secondary text.
    func testHierarchyOrdering() {
        XCTAssertGreaterThan(MacTypography.detailTitleSize, MacTypography.rowTitleSize)
        XCTAssertGreaterThan(MacTypography.rowTitleSize, MacTypography.rowMetaSize)
        // Meta and field labels are both secondary; labels must never exceed meta.
        XCTAssertLessThanOrEqual(MacTypography.labelSize, MacTypography.rowMetaSize)
    }

    /// A row title sits just above the MAC body size — the same relationship iOS has (19 vs 17),
    /// not iOS's absolute numbers.
    func testRowTitleTracksTheMacSystemBodySize() {
        let macBody = NSFont.systemFontSize            // 13pt on macOS
        XCTAssertGreaterThanOrEqual(MacTypography.rowTitleSize, macBody,
                                    "A row title should not be smaller than system body text")
        XCTAssertLessThanOrEqual(MacTypography.rowTitleSize, macBody + 2,
                                 "Row titles were 16pt — oversized against macOS's 13pt body")
    }

    /// Secondary text stays legible without competing with the title.
    func testSecondaryTextIsSmallButLegible() {
        XCTAssertGreaterThanOrEqual(MacTypography.rowMetaSize, 10)
        XCTAssertLessThan(MacTypography.rowMetaSize, MacTypography.rowTitleSize)
    }

    /// The detail header is clearly a heading, but still desktop-scale.
    func testDetailTitleIsAHeadingNotATouchTarget() {
        XCTAssertGreaterThan(MacTypography.detailTitleSize, NSFont.systemFontSize)
        XCTAssertLessThan(MacTypography.detailTitleSize, 19, "19pt is the iOS touch-scale size")
    }
}
#endif
