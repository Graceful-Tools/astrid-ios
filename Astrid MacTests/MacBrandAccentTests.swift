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

    func testAccentDefaultsToAstridBlueOnMac() {
        XCTAssertEqual(Brand.accentColorHex, "#3b82f6")
        XCTAssertEqual(Brand.accentColor, Color(red: 59/255, green: 130/255, blue: 246/255))
    }

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
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        for mode in ["light", "dark", "ocean"] {
            UserDefaults.standard.set(mode, forKey: key)
            XCTAssertEqual(Theme.accent, Brand.accentColor, "accent drifted in \(mode)")
            XCTAssertEqual(Theme.Dark.accent, Brand.accentColor, "Dark.accent drifted in \(mode)")
            XCTAssertEqual(Theme.Ocean.accent, Brand.accentColor, "Ocean.accent drifted in \(mode)")
        }
    }
}
#endif
