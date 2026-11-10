import SwiftUI
import XCTest
@testable import Astrid_App

/// AITD-611 — iOS resolves one `AstridTokens.Palette` per theme, the way the Mac does, instead of
/// a fixed light value plus a `colorScheme == .dark ?` ternary at every use (register DS8).
/// The ternary could only ever pick light or dark, so Ocean rendered with light's text and
/// borders — the contrast fix in core (DS1) never reached it on iOS.
final class ThemePaletteTests: XCTestCase {

    func testOceanResolvesTheOceanPaletteWhateverTheSystemScheme() {
        XCTAssertEqual(AstridTokens.palette(for: .ocean, colorScheme: .light).textPrimary, AstridTokens.ocean.textPrimary)
        XCTAssertEqual(AstridTokens.palette(for: .ocean, colorScheme: .dark).bgPrimary, AstridTokens.ocean.bgPrimary)
        XCTAssertEqual(AstridTokens.palette(for: .ocean, colorScheme: .light).border, AstridTokens.ocean.border)
    }

    func testLightAndDarkIgnoreTheSystemScheme() {
        XCTAssertEqual(AstridTokens.palette(for: .light, colorScheme: .dark).bgPrimary, AstridTokens.light.bgPrimary)
        XCTAssertEqual(AstridTokens.palette(for: .dark, colorScheme: .light).bgPrimary, AstridTokens.dark.bgPrimary)
    }

    func testAutoFollowsTheSystemScheme() {
        XCTAssertEqual(AstridTokens.palette(for: .auto, colorScheme: .light).textPrimary, AstridTokens.light.textPrimary)
        XCTAssertEqual(AstridTokens.palette(for: .auto, colorScheme: .dark).textPrimary, AstridTokens.dark.textPrimary)
    }

    /// The point of the migration: Ocean is a third palette, not "light". If core ever made the
    /// two identical this test would be meaningless, so it says so rather than passing quietly.
    func testOceanIsNotLight() {
        XCTAssertNotEqual(AstridTokens.palette(for: .ocean, colorScheme: .light).textPrimary,
                          AstridTokens.light.textPrimary)
    }

    // MARK: - The last pass: one place resolves Auto

    /// Views used to work out "which theme is on screen" themselves, each with its own
    /// `colorScheme == .dark ? .dark : .light`. One resolver now does it for all of them.
    func testResolvedThemeKeepsFixedModesAndMapsAutoToTheSystemScheme() {
        XCTAssertEqual(ThemeMode.ocean.resolved(for: .dark), .ocean)
        XCTAssertEqual(ThemeMode.light.resolved(for: .dark), .light)
        XCTAssertEqual(ThemeMode.dark.resolved(for: .light), .dark)
        XCTAssertEqual(ThemeMode.auto.resolved(for: .light), .light)
        XCTAssertEqual(ThemeMode.auto.resolved(for: .dark), .dark)
    }

    /// Several views still keep the setting as a raw string; the string form must agree, and an
    /// unknown value passes through untouched, as those views did before.
    func testResolvedNameAgreesWithTheEnumAndPassesUnknownValuesThrough() {
        XCTAssertEqual(ThemeMode.resolvedName("auto", colorScheme: .dark), "dark")
        XCTAssertEqual(ThemeMode.resolvedName("auto", colorScheme: .light), "light")
        XCTAssertEqual(ThemeMode.resolvedName("ocean", colorScheme: .dark), "ocean")
        XCTAssertEqual(ThemeMode.resolvedName("something-else", colorScheme: .dark), "something-else")
    }
}
