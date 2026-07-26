//  MacThemedSurfaceTests.swift
//  Regression for task b365f261 — "[Mac] cannot see text in settings in light mode".
//  A themed surface paints Theme.bgPrimary; if it doesn't also pin the color scheme, macOS keeps
//  drawing system text for its OWN appearance — white labels on the white Light-theme surface.

import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacThemedSurfaceTests: XCTestCase {

    func testLightThemePinsLightSchemeSoTextStaysDark() {
        // The reported bug: Light theme + dark macOS = invisible settings text.
        XCTAssertEqual(MacSurfaceScheme.colorScheme(mode: "light"), .light)
    }

    func testOceanPaintsLightSurfaceSoItAlsoPinsLight() {
        XCTAssertEqual(MacSurfaceScheme.colorScheme(mode: "ocean"), .light)
    }

    func testDarkThemePinsDarkScheme() {
        XCTAssertEqual(MacSurfaceScheme.colorScheme(mode: "dark"), .dark)
    }

    func testAutoFollowsTheSystem() {
        // In auto the painted background already tracks the system appearance, so forcing a
        // scheme would fight it.
        XCTAssertNil(MacSurfaceScheme.colorScheme(mode: "auto"))
        XCTAssertNil(MacSurfaceScheme.colorScheme(mode: "unknown-future-mode"))
    }
}
