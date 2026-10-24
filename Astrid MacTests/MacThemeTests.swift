//  MacThemeTests.swift
//  Astrid for Mac — the base Theme tokens resolve to the selected theme (ocean/light/dark) on macOS.

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacThemeTests: XCTestCase {

    /// The mode → colour mapping, asked with the mode passed in rather than written into the
    /// developer's real `themeMode` (AITD-534; the pattern from task f040f28e).
    func testThemedResolvesByMode() {
        let l = Color.red, d = Color.green, o = Color.blue
        XCTAssertEqual(Theme.themed(mode: "dark", light: l, dark: d, ocean: o), d)
        XCTAssertEqual(Theme.themed(mode: "ocean", light: l, dark: d, ocean: o), o)
        XCTAssertEqual(Theme.themed(mode: "light", light: l, dark: d, ocean: o), l)
    }

    /// Dark theme must actually flip the base surface + text tokens (not stay light).
    func testDarkThemeChangesBaseTokens() {
        let white = Color(red: 1, green: 1, blue: 1)
        let ink = Color(red: 17/255, green: 24/255, blue: 39/255)
        XCTAssertNotEqual(Theme.Dark.bgPrimary, white, "Dark theme should change the background token")
        XCTAssertNotEqual(Theme.Dark.textPrimary, ink, "Dark theme should change the text token")
        XCTAssertEqual(Theme.themed(mode: "dark", light: white, dark: Theme.Dark.bgPrimary, ocean: Theme.Ocean.bgPrimary),
                       Theme.Dark.bgPrimary)
    }

    /// Pervasive theme background (eae911d4): each theme's primary surface must be visually distinct
    /// so applying Theme.bgPrimary everywhere actually reads as Ocean vs Light vs Dark.
    func testThemeBackgroundsAreDistinct() {
        XCTAssertNotEqual(Theme.Ocean.bgPrimary, Theme.Dark.bgPrimary)
        // Ocean's cyan primary must differ from the plain light white.
        XCTAssertNotEqual(Theme.Ocean.bgPrimary, Color(red: 1, green: 1, blue: 1))
    }

    /// Theme-mode CACHE invalidation (3c34c411): after switching themeMode in UserDefaults, the
    /// cached mode must reflect the new value immediately (synchronous didChange invalidation) —
    /// a stale cache would freeze the app's colors on the previous theme.
    func testCachedModeInvalidatesOnSwitch() throws {
        // On a suite of its own, not the app's defaults — the Mac test host IS the app, so
        // `.standard` is the developer's real theme (AITD-534).
        let suite = "MacThemeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        Theme.readMode(from: defaults)
        defer {
            Theme.readMode(from: .standard)
            defaults.removePersistentDomain(forName: suite)
        }
        defaults.set("ocean", forKey: "themeMode")
        XCTAssertEqual(Theme.currentThemeMode, "ocean")
        _ = Theme.bgPrimary   // populate/exercise the cache
        defaults.set("dark", forKey: "themeMode")
        XCTAssertEqual(Theme.currentThemeMode, "dark", "Cache must invalidate on the defaults change")
        XCTAssertEqual(Theme.bgPrimary, Theme.Dark.bgPrimary)
        defaults.set("light", forKey: "themeMode")
        XCTAssertEqual(Theme.currentThemeMode, "light")
    }

}
#endif
