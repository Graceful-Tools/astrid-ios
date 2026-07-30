import SwiftUI
import XCTest
@testable import Astrid_App

/// Whitelabel — the brand accent is a VARIABLE, not a constant (task 97208a72).
///
/// `Theme` already abstracts light vs dark vs ocean, but it did not abstract *whose*
/// blue: `Color(red: 59/255, green: 130/255, blue: 246/255)` was written out 26 times,
/// once per theme variant. That made a partner theme a find-and-replace rather than a
/// configuration change, which is exactly the coupling this refactor exists to remove.
///
/// These tests pin the two halves that matter:
///   1. the default is still Astrid blue, so nothing changes for Astrid, and
///   2. every theme variant reads the accent from `Brand` rather than from a literal —
///      a regression here is invisible (the app still looks right for Astrid) until a
///      partner build ships with one stray blue button.
final class BrandAccentTests: XCTestCase {

    // MARK: - Default

    func testAccentDefaultsToAstridBlue() {
        XCTAssertEqual(Brand.accentColorHex, "#3b82f6")
        XCTAssertEqual(Brand.accentColor, Color(red: 59/255, green: 130/255, blue: 246/255))
    }

    func testAccentHoverIsTheDarkerShadeUsedToday() {
        XCTAssertEqual(Brand.accentHoverColor, Color(red: 37/255, green: 99/255, blue: 235/255))
    }

    /// The accent renders white text today. A partner picking a pale accent needs to
    /// change this with it, so it is configuration rather than a constant.
    func testAccentTextDefaultsToWhite() {
        XCTAssertEqual(Brand.accentTextColor, Color(red: 1, green: 1, blue: 1))
    }

    // MARK: - Resolution

    /// Hex resolution is a pure function so it can be tested without a second bundle.
    func testResolveAccentAcceptsAHexWithOrWithoutHash() {
        XCTAssertEqual(Brand.resolveAccentHex("#ff6600"), "#ff6600")
        XCTAssertEqual(Brand.resolveAccentHex("ff6600"), "#ff6600")
        XCTAssertEqual(Brand.resolveAccentHex("  #FF6600  "), "#FF6600")
    }

    /// A malformed accent must fall back rather than throw or render transparent. A
    /// brand colour is chrome, not a feature — a typo in it must never take the app down.
    func testResolveAccentFallsBackOnGarbage() {
        XCTAssertEqual(Brand.resolveAccentHex(nil), "#3b82f6")
        XCTAssertEqual(Brand.resolveAccentHex(""), "#3b82f6")
        XCTAssertEqual(Brand.resolveAccentHex("   "), "#3b82f6")
        XCTAssertEqual(Brand.resolveAccentHex("blue"), "#3b82f6")
        XCTAssertEqual(Brand.resolveAccentHex("#12345"), "#3b82f6", "5 digits is not a colour")
        XCTAssertEqual(Brand.resolveAccentHex("$(BRAND_ACCENT)"), "#3b82f6", "unsubstituted build setting")
    }

    /// An 8-digit hex carries alpha — accepted, because a partner may want a translucent
    /// accent, and Color(hex:) already supports it.
    func testResolveAccentAcceptsEightDigitHex() {
        XCTAssertEqual(Brand.resolveAccentHex("#3b82f680"), "#3b82f680")
    }

    /// Whatever resolution returns must actually parse — otherwise `accentColor` would
    /// silently fall back at a different layer and the two could disagree.
    func testResolvedAccentAlwaysParses() {
        for raw in [nil, "", "nonsense", "#3b82f6", "ff6600", "#3b82f680"] as [String?] {
            XCTAssertNotNil(Color(hex: Brand.resolveAccentHex(raw)), "unparseable for \(raw ?? "nil")")
        }
    }

    // MARK: - Theme wiring

    /// The point of the phase: no theme variant may hold its own copy of the accent.
    func testEveryThemeVariantReadsTheBrandAccent() {
        XCTAssertEqual(Theme.accent, Brand.accentColor)
        XCTAssertEqual(Theme.Dark.accent, Brand.accentColor)
        XCTAssertEqual(Theme.Ocean.accent, Brand.accentColor)
    }

    func testEveryThemeVariantReadsTheBrandAccentHover() {
        XCTAssertEqual(Theme.accentHover, Brand.accentHoverColor)
        XCTAssertEqual(Theme.Dark.accentHover, Brand.accentHoverColor)
        XCTAssertEqual(Theme.Ocean.accentHover, Brand.accentHoverColor)
    }

    func testEveryThemeVariantReadsTheBrandAccentText() {
        XCTAssertEqual(Theme.accentText, Brand.accentTextColor)
        XCTAssertEqual(Theme.Dark.accentText, Brand.accentTextColor)
        XCTAssertEqual(Theme.Ocean.accentText, Brand.accentTextColor)
    }

    /// Focus rings are the accent, not an incidental blue — a partner build with a green
    /// accent and blue focus rings looks broken.
    func testFocusBordersReadTheBrandAccent() {
        XCTAssertEqual(Theme.borderFocus, Brand.accentColor)
        XCTAssertEqual(Theme.Dark.borderFocus, Brand.accentColor)
        XCTAssertEqual(Theme.Ocean.borderFocus, Brand.accentColor)
    }

    /// Dark mode's selected-row border is the accent too.
    func testDarkSelectedBorderReadsTheBrandAccent() {
        XCTAssertEqual(Theme.Dark.bgSelectedBorder, Brand.accentColor)
    }

    /// Low priority is drawn in the accent. It is the only priority colour that is —
    /// medium/high/none are semantic (amber/red/gray) and must NOT follow the brand.
    func testPriorityLowReadsTheBrandAccentAndTheOthersDoNot() {
        XCTAssertEqual(Theme.priorityLow, Brand.accentColor)
        XCTAssertNotEqual(Theme.priorityHigh, Brand.accentColor)
        XCTAssertNotEqual(Theme.priorityMedium, Brand.accentColor)
        XCTAssertNotEqual(Theme.priorityNone, Brand.accentColor)
    }

    /// Status colours are semantic and stay fixed: a red error in a green-branded app is
    /// still red. Pinned so a later "make everything brandable" pass does not swallow them.
    func testStatusColoursAreNotBranded() {
        XCTAssertNotEqual(Theme.error, Brand.accentColor)
        XCTAssertNotEqual(Theme.warning, Brand.accentColor)
        XCTAssertNotEqual(Theme.success, Brand.accentColor)
    }
}
