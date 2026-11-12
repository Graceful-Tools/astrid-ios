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

    /// AITD-615: astrid-core DS26 darkened the accent fill so white on it reads (5.17:1, was
    /// 3.68:1 on `#3b82f6`), and its hover moved one step on with it.
    func testAccentDefaultsToTheDS26Fill_AITD615() {
        XCTAssertEqual(Brand.accentColorHex, "#2563eb")
        XCTAssertEqual(Brand.accentColor, Color(red: 37/255, green: 99/255, blue: 235/255))
        XCTAssertEqual(Brand.accentHoverColor, Color(red: 29/255, green: 78/255, blue: 216/255))
    }

    // MARK: - Inks (DS25, AITD-615)

    /// The accent as text or an icon is its ink, not its fill: Astrid's designed blues.
    func testAccentInksDefaultToTheDesignedBlues_AITD615() {
        XCTAssertEqual(Brand.accentInkColorHex, "#1D4ED8")
        XCTAssertEqual(Brand.accentInkDarkColorHex, "#60A5FA")
        XCTAssertEqual(Brand.accentInkColor, Color(red: 29/255, green: 78/255, blue: 216/255))
        XCTAssertEqual(Brand.accentInkDarkColor, Color(red: 96/255, green: 165/255, blue: 250/255))
    }

    /// A configured ink wins; garbage falls back to the derived one rather than to a colour
    /// that may not read on the card.
    func testAConfiguredInkWins_AITD615() {
        XCTAssertEqual(Brand.resolveAccentInk("#112233", accentHex: "#ff6600", dark: false), "#112233")
        XCTAssertEqual(Brand.resolveAccentInk("nonsense", accentHex: Brand.defaultAccentHex, dark: true), "#60A5FA")
        XCTAssertEqual(Brand.resolveAccentInk("$(BRAND_INK)", accentHex: Brand.defaultAccentHex, dark: false), "#1D4ED8")
    }

    /// A partner with an accent and no inks gets web's `accentInk()` rule: the accent moved
    /// toward black (light) or white (dark) until it reads at 4.5:1 on the card and on its
    /// own 12% wash. A pale accent used as-is would be unreadable text.
    func testAPartnerInkIsDerivedToReadOnTheCard_AITD615() throws {
        let white = (255.0, 255.0, 255.0), darkCard = (31.0, 41.0, 55.0) // tokens: light bg-hover, dark bg-secondary
        for accent in ["#ff6600", "#22c55e", "#eab308", "#8b5cf6", "#3b82f6"] {
            let rgb = try XCTUnwrap(Brand.rgb(accent))
            for (dark, card) in [(false, white), (true, darkCard)] {
                let inkHex = Brand.resolveAccentInk(nil, accentHex: accent, dark: dark)
                let ink = try XCTUnwrap(Brand.rgb(inkHex), inkHex)
                let wash = Brand.over(rgb, card, alpha: 0.12)
                XCTAssertGreaterThanOrEqual(Brand.contrast(ink, card), 4.5, "\(accent) \(dark ? "dark" : "light") ink \(inkHex) on the card")
                XCTAssertGreaterThanOrEqual(Brand.contrast(ink, wash), 4.5, "\(accent) \(dark ? "dark" : "light") ink \(inkHex) on its wash")
            }
        }
        // Web's rule, step for step: orange on white is darkened 30% → (179, 71, 0).
        XCTAssertEqual(Brand.resolveAccentInk(nil, accentHex: "#ff6600", dark: false).lowercased(), "#b34700")
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
        XCTAssertEqual(Brand.resolveAccentHex(nil), "#2563eb")
        XCTAssertEqual(Brand.resolveAccentHex(""), "#2563eb")
        XCTAssertEqual(Brand.resolveAccentHex("   "), "#2563eb")
        XCTAssertEqual(Brand.resolveAccentHex("blue"), "#2563eb")
        XCTAssertEqual(Brand.resolveAccentHex("#12345"), "#2563eb", "5 digits is not a colour")
        XCTAssertEqual(Brand.resolveAccentHex("$(BRAND_ACCENT)"), "#2563eb", "unsubstituted build setting")
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

    /// Text and icons in the accent read its ink: the light ink on Light and Ocean, the dark
    /// ink on Dark (DS25).
    func testEveryThemeVariantReadsTheBrandAccentInk_AITD615() {
        XCTAssertEqual(Theme.accentInk, Brand.accentInkColor)
        XCTAssertEqual(Theme.Ocean.accentInk, Brand.accentInkColor)
        XCTAssertEqual(Theme.Dark.accentInk, Brand.accentInkDarkColor)
    }

    func testEveryThemeVariantReadsTheBrandAccentText() {
        XCTAssertEqual(Theme.accentText, Brand.accentTextColor)
        XCTAssertEqual(Theme.Dark.accentText, Brand.accentTextColor)
        XCTAssertEqual(Theme.Ocean.accentText, Brand.accentTextColor)
    }

    /// Focus rings are the brand's, not an incidental blue — a partner build with a green
    /// accent and blue focus rings looks broken. On Dark it is the accent's dark ink (DS26):
    /// the darkened fill is 2.84:1 as a line on a dark card.
    func testFocusBordersReadTheBrandAccent() {
        XCTAssertEqual(Theme.borderFocus, Brand.accentColor)
        XCTAssertEqual(Theme.Dark.borderFocus, Brand.accentInkDarkColor)
        XCTAssertEqual(Theme.Ocean.borderFocus, Brand.accentColor)
    }

    /// Dark mode's selected-row border is the accent's dark ink (DS26).
    func testDarkSelectedBorderReadsTheBrandAccentInk() {
        XCTAssertEqual(Theme.Dark.bgSelectedBorder, Brand.accentInkDarkColor)
    }

    /// Low priority is drawn in the accent (its dark ink on Dark). It is the only priority
    /// colour that is — medium/high/none are semantic (amber/red/gray) and must NOT follow
    /// the brand.
    func testPriorityLowReadsTheBrandAccentAndTheOthersDoNot() {
        XCTAssertEqual(Theme.priorityLow, Brand.accentColor)
        XCTAssertEqual(AstridTokens.dark.priorityLow, Brand.accentInkDarkColor)
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
