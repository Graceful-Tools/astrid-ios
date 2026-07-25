//  MacDetailChromeTests.swift
//  Astrid for Mac — Task 98c6c6d5: the details surface must be readable in EVERY theme × system
//  appearance combination. RED before the fix: mode "auto" on a dark system returned a white card
//  while Theme.textPrimary resolved white → white-on-white unreadable detail.

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacDetailChromeTests: XCTestCase {

    func testWhiteInLightAndOcean() {
        for mode in ["ocean", "light"] {
            // System appearance must not matter for explicit light-family themes.
            XCTAssertEqual(MacDetailChrome.background(mode: mode, systemIsDark: false), .white)
            XCTAssertEqual(MacDetailChrome.background(mode: mode, systemIsDark: true), .white)
        }
    }

    func testDarkThemeUsesDarkSurface() {
        XCTAssertEqual(MacDetailChrome.background(mode: "dark", systemIsDark: false), Theme.Dark.bgSecondary)
        XCTAssertEqual(MacDetailChrome.background(mode: "dark", systemIsDark: true), Theme.Dark.bgSecondary)
    }

    /// THE bug (98c6c6d5): auto + dark system must NOT be a white card (text resolves white).
    func testAutoFollowsSystemAppearance() {
        XCTAssertEqual(MacDetailChrome.background(mode: "auto", systemIsDark: true), Theme.Dark.bgSecondary,
                       "Auto on a dark system must use the dark surface — white would be white-on-white")
        XCTAssertEqual(MacDetailChrome.background(mode: "auto", systemIsDark: false), .white)
    }
}
#endif
