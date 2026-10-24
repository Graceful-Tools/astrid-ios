//  MacBrandAccentTests.swift
//  Whitelabel (task 97208a72) — the Mac target must read the accent from Brand too.
//
//  Theme has a separate `#if os(macOS)` branch for its base tokens, so a Mac-only
//  regression is invisible to the iOS suite. That branch owns `borderFocus`, which is
//  drawn on every focused control in the app.

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacBrandAccentTests: XCTestCase {

    /// The macOS branch of Theme owns its own borderFocus — pinned separately from iOS.
    func testMacFocusBorderReadsTheBrandAccent() {
        XCTAssertEqual(Theme.borderFocus, Brand.accentColor)
    }

    func testMacInteractiveTokensReadTheBrandAccent() {
        XCTAssertEqual(Theme.accent, Brand.accentColor)
        XCTAssertEqual(Theme.accentHover, Brand.accentHoverColor)
        XCTAssertEqual(Theme.accentText, Brand.accentTextColor)
    }

    /// The accent must not change when the user switches theme — light/dark/ocean vary
    /// the SURFACE, not the brand. A partner accent that only applied in one mode would
    /// be a subtle, easily-missed break.
    func testAccentIsStableAcrossThemeModes() {
        // Every theme's accent is the brand's — asked of each palette directly, with no theme
        // written into the developer's real defaults (AITD-534). `Theme.accent` is a constant.
        XCTAssertEqual(Theme.accent, Brand.accentColor)
        for (mode, accent) in [("dark", Theme.Dark.accent), ("ocean", Theme.Ocean.accent)] {
            XCTAssertEqual(accent, Brand.accentColor, "accent drifted in \(mode)")
        }
    }

}
#endif
