//  MacChatLoadStateTests.swift
//  Astrid for Mac — Task e4d0eb84: chat surface resolution (the indefinite-spinner regression).

#if os(macOS)
import SwiftUI
import XCTest
@testable import Astrid_Mac

final class MacChatLoadStateTests: XCTestCase {

    func testSpinnerOnlyDuringInitialLoad() {
        XCTAssertEqual(MacChatLoadState.surface(loading: true, hasMessages: false), .spinner)
    }

    /// THE regression: once loading completes with no messages, the surface MUST be .empty —
    /// an indefinite spinner (loading stuck true) was the bug.
    func testLoadCompleteResolvesToEmptyNotSpinner() {
        XCTAssertEqual(MacChatLoadState.surface(loading: false, hasMessages: false), .empty)
    }

    func testCachedMessagesAlwaysWinOverSpinner() {
        XCTAssertEqual(MacChatLoadState.surface(loading: true, hasMessages: true), .messages,
                       "A refresh must not hide already-visible messages behind a spinner")
        XCTAssertEqual(MacChatLoadState.surface(loading: false, hasMessages: true), .messages)
    }

    /// Themed input tokens differ per theme (5b41942a), asked without touching global state
    /// (task f040f28e).
    ///
    /// This used to write `themeMode` into `UserDefaults` and read `Theme.inputBg` back. That
    /// flaked for two independent reasons: the key is process-wide and other test classes read
    /// it while running in parallel, and `currentThemeMode` is cached behind a
    /// `UserDefaults.didChangeNotification` observer that arrives asynchronously — so even alone,
    /// "set the default then immediately read the colour" could return the previous theme's.
    ///
    /// The mapping is a pure function of the mode, so it now takes one. Same assertions, no race,
    /// and nothing left behind for the next test.
    func testThemedInputTokens() {
        XCTAssertEqual(Theme.themed(mode: "ocean", light: .white, dark: Theme.Dark.inputBg, ocean: Theme.Ocean.inputBg),
                       Theme.Ocean.inputBg, "Ocean quick-add uses the chrome-silver input")
        XCTAssertEqual(Theme.themed(mode: "dark", light: .white, dark: Theme.Dark.inputBg, ocean: Theme.Ocean.inputBg),
                       Theme.Dark.inputBg)
        XCTAssertEqual(Theme.themed(mode: "light", light: .white, dark: Theme.Dark.inputBg, ocean: Theme.Ocean.inputBg),
                       .white)
    }

    /// The tokens must actually differ, or "themed" would be decoration. This is the assertion
    /// the old test was really making, and it never needed UserDefaults either.
    func testTheThreeThemesAreDistinct() {
        XCTAssertNotEqual(Theme.Ocean.inputBg, Theme.Dark.inputBg)
        XCTAssertNotEqual(Theme.Ocean.inputBg, Color(red: 1, green: 1, blue: 1))
    }

    /// An unrecognised mode must not crash or pick arbitrarily — it falls through to the system
    /// appearance, which is the "auto" case every real build starts in.
    func testAnUnknownModeFallsBackRatherThanFailing() {
        let resolved = Theme.themed(mode: "not-a-theme", light: .white, dark: .black, ocean: .blue)
        XCTAssertTrue(resolved == .white || resolved == .black,
                      "auto resolves to light or dark, never to a theme-specific token")
    }

    /// The global-state version is gone. If it comes back, so does the flake.
    ///
    /// The needle is assembled at runtime on purpose: written as one literal it would match
    /// ITSELF, and the guard would fail the moment it was added — which is exactly what happened
    /// on the first attempt.
    func testThisSuiteDoesNotWriteTheGlobalThemeKey() throws {
        let needle = "UserDefaults.standard" + ".set"
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath), encoding: .utf8)
        XCTAssertFalse(source.contains(needle),
                       "Writing themeMode here is what made this suite flake under parallel execution")
    }
}
#endif
