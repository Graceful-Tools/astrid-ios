//  MacTokensTests.swift
//  AITD-610 — the Mac's motion, type ramp and checkbox sizes come from astrid-core's vendored
//  AstridTokens, so web, iOS and Mac cannot drift apart on them.

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacTokensTests: XCTestCase {

    func testMotionComesFromTokens() {
        XCTAssertEqual(MacMotion.fastDuration, AstridTokens.Motion.fastDuration)
        XCTAssertEqual(MacMotion.mediumDuration, AstridTokens.Motion.mediumDuration)
        XCTAssertEqual(MacMotion.springResponse, AstridTokens.Motion.springDuration)
        XCTAssertEqual(MacMotion.springDamping, AstridTokens.Motion.springDamping)
    }

    func testTypeRampComesFromCompactTokens() {
        XCTAssertEqual(MacTypography.rowTitleSize, AstridTokens.TypeSize.Compact.rowTitle.size)
        XCTAssertEqual(MacTypography.rowMetaSize, AstridTokens.TypeSize.Compact.rowMeta.size)
        XCTAssertEqual(MacTypography.labelSize, AstridTokens.TypeSize.Compact.label.size)
        XCTAssertEqual(MacTypography.detailBodySize, AstridTokens.TypeSize.Compact.detailBody.size)
    }

    func testCheckboxSizesComeFromCompactTokens() {
        XCTAssertEqual(MacTaskVisuals.rowCheckboxSize, AstridTokens.Size.Compact.leadingControl)
        XCTAssertEqual(MacTaskVisuals.detailCheckboxSize, AstridTokens.Size.Compact.leadingControlDetail)
    }

    /// Register DS1 reaches the Mac: Ocean text is the darker token text.
    func testOceanTextOnMacIsTheTokenText() {
        XCTAssertEqual(Theme.themed(mode: "ocean", light: AstridTokens.light.textMuted,
                                    dark: Theme.Dark.textMuted, ocean: Theme.Ocean.textMuted),
                       AstridTokens.ocean.textMuted)
    }
}
#endif
