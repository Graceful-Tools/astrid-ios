import SwiftUI
import XCTest
@testable import Astrid_App

/// AITD-610 — `Theme` reads its values from the vendored `AstridTokens` (astrid-core
/// `design/tokens.json`), so a palette change lands in core once and reaches iOS, Mac and web
/// together. A value that should differ is changed in core first, never here.
final class ThemeTokensTests: XCTestCase {

    func testLightPaletteComesFromTokens() {
        let t = AstridTokens.light
        XCTAssertEqual(Theme.bgPrimary, t.bgPrimary)
        XCTAssertEqual(Theme.bgSecondary, t.bgSecondary)
        XCTAssertEqual(Theme.bgTertiary, t.bgTertiary)
        XCTAssertEqual(Theme.bgHover, t.bgHover)
        XCTAssertEqual(Theme.bgActive, t.bgActive)
        XCTAssertEqual(Theme.bgSelected, t.bgSelected)
        XCTAssertEqual(Theme.bgSelectedBorder, t.bgSelectedBorder)
        XCTAssertEqual(Theme.border, t.border)
        XCTAssertEqual(Theme.borderHover, t.borderHover)
        XCTAssertEqual(Theme.borderInput, t.borderInput)
        XCTAssertEqual(Theme.textPrimary, t.textPrimary)
        XCTAssertEqual(Theme.textSecondary, t.textSecondary)
        XCTAssertEqual(Theme.textMuted, t.textMuted)
        XCTAssertEqual(Theme.textInverted, t.textInverted)
        XCTAssertEqual(Theme.textSelected, t.textSelected)
        XCTAssertEqual(Theme.success, t.success)
        XCTAssertEqual(Theme.warning, t.warning)
        XCTAssertEqual(Theme.error, t.error)
        XCTAssertEqual(Theme.info, t.info)
        XCTAssertEqual(Theme.priorityNone, t.priorityNone)
        XCTAssertEqual(Theme.priorityMedium, t.priorityMedium)
        XCTAssertEqual(Theme.priorityHigh, t.priorityHigh)
        XCTAssertEqual(Theme.headerBg, t.headerBg)
        XCTAssertEqual(Theme.headerBorder, t.headerBorder)
        XCTAssertEqual(Theme.inputBg, t.inputBg)
        XCTAssertEqual(Theme.inputBorder, t.inputBorder)
        XCTAssertEqual(Theme.inputPlaceholder, t.inputPlaceholder)
        XCTAssertEqual(Theme.buttonBg, t.buttonBg)
        XCTAssertEqual(Theme.buttonHover, t.buttonHover)
        XCTAssertEqual(Theme.buttonBorder, t.buttonBorder)
    }

    func testDarkPaletteComesFromTokens() {
        let t = AstridTokens.dark
        XCTAssertEqual(Theme.Dark.bgPrimary, t.bgPrimary)
        XCTAssertEqual(Theme.Dark.bgSecondary, t.bgSecondary)
        XCTAssertEqual(Theme.Dark.bgSelected, t.bgSelected)
        XCTAssertEqual(Theme.Dark.border, t.border)
        XCTAssertEqual(Theme.Dark.textPrimary, t.textPrimary)
        XCTAssertEqual(Theme.Dark.textSecondary, t.textSecondary)
        XCTAssertEqual(Theme.Dark.textMuted, t.textMuted)
        XCTAssertEqual(Theme.Dark.textInverted, t.textInverted)
        XCTAssertEqual(Theme.Dark.inputBg, t.inputBg)
        XCTAssertEqual(Theme.Dark.buttonBg, t.buttonBg)
        XCTAssertEqual(Theme.Dark.headerBg, t.headerBg)
    }

    func testOceanPaletteComesFromTokens() {
        let t = AstridTokens.ocean
        XCTAssertEqual(Theme.Ocean.bgPrimary, t.bgPrimary)
        XCTAssertEqual(Theme.Ocean.border, t.border)
        XCTAssertEqual(Theme.Ocean.headerBg, t.headerBg)
        XCTAssertEqual(Theme.Ocean.inputBg, t.inputBg)
        XCTAssertEqual(Theme.Ocean.inputPlaceholder, t.inputPlaceholder)
        XCTAssertEqual(Theme.Ocean.buttonHover, t.buttonHover)
    }

    /// Register DS1: grey text on the cyan background measured 3.1:1 (web AWTD-1496), so the
    /// tokens give Ocean darker text, and iOS and Mac adopt it.
    func testOceanTextIsTheDarkerTokenText() {
        let t = AstridTokens.ocean
        XCTAssertEqual(Theme.Ocean.textPrimary, t.textPrimary)
        XCTAssertEqual(Theme.Ocean.textSecondary, t.textSecondary)
        XCTAssertEqual(Theme.Ocean.textMuted, t.textMuted)
        XCTAssertEqual(Theme.Ocean.textSelected, t.textSelected)
        XCTAssertEqual(Theme.Ocean.textMuted, Color(red: 75/255, green: 85/255, blue: 99/255))
    }

    func testSpacingRadiiAndShadowsComeFromTokens() {
        XCTAssertEqual(Theme.spacing4, AstridTokens.Space.s4)
        XCTAssertEqual(Theme.spacing16, AstridTokens.Space.s16)
        XCTAssertEqual(Theme.spacing48, AstridTokens.Space.s48)
        XCTAssertEqual(Theme.radiusSmall, AstridTokens.Radius.sm)
        XCTAssertEqual(Theme.radiusXLarge, AstridTokens.Radius.xl)
        XCTAssertEqual(Theme.shadowLarge.radius, AstridTokens.Shadow.lg.radius)
        XCTAssertEqual(Theme.shadowLarge.y, AstridTokens.Shadow.lg.y)
    }
}
