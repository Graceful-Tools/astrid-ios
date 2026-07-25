//  MacThemeTests.swift
//  Astrid for Mac — the base Theme tokens resolve to the selected theme (ocean/light/dark) on macOS.

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacThemeTests: XCTestCase {

    func testThemedResolvesByMode() {
        let l = Color.red, d = Color.green, o = Color.blue
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }

        UserDefaults.standard.set("dark", forKey: key)
        XCTAssertEqual(Theme.themed(light: l, dark: d, ocean: o), d)

        UserDefaults.standard.set("ocean", forKey: key)
        XCTAssertEqual(Theme.themed(light: l, dark: d, ocean: o), o)

        UserDefaults.standard.set("light", forKey: key)
        XCTAssertEqual(Theme.themed(light: l, dark: d, ocean: o), l)
    }

    /// Dark theme must actually flip the base surface + text tokens (not stay light).
    func testDarkThemeChangesBaseTokens() {
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("light", forKey: key)
        let lightBg = Theme.bgPrimary, lightText = Theme.textPrimary
        UserDefaults.standard.set("dark", forKey: key)
        XCTAssertNotEqual(Theme.bgPrimary, lightBg, "Dark theme should change the background token")
        XCTAssertNotEqual(Theme.textPrimary, lightText, "Dark theme should change the text token")
        XCTAssertEqual(Theme.bgPrimary, Theme.Dark.bgPrimary)
        XCTAssertEqual(Theme.textPrimary, Theme.Dark.textPrimary)
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
    func testCachedModeInvalidatesOnSwitch() {
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("ocean", forKey: key)
        XCTAssertEqual(Theme.currentThemeMode, "ocean")
        _ = Theme.bgPrimary   // populate/exercise the cache
        UserDefaults.standard.set("dark", forKey: key)
        XCTAssertEqual(Theme.currentThemeMode, "dark", "Cache must invalidate on the defaults change")
        XCTAssertEqual(Theme.bgPrimary, Theme.Dark.bgPrimary)
        UserDefaults.standard.set("light", forKey: key)
        XCTAssertEqual(Theme.currentThemeMode, "light")
    }
}
#endif
