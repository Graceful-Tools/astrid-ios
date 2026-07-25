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

    /// Themed input tokens exist per theme (5b41942a) — Ocean's chrome-silver input must differ
    /// from the plain white light input, and Dark's from both.
    func testThemedInputTokens() {
        let key = "themeMode"
        let saved = UserDefaults.standard.string(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        UserDefaults.standard.set("ocean", forKey: key)
        XCTAssertEqual(Theme.inputBg, Theme.Ocean.inputBg, "Ocean quick-add uses the chrome-silver input")
        UserDefaults.standard.set("dark", forKey: key)
        XCTAssertEqual(Theme.inputBg, Theme.Dark.inputBg)
        UserDefaults.standard.set("light", forKey: key)
        XCTAssertEqual(Theme.inputBg, Color(red: 1, green: 1, blue: 1))
    }
}
#endif
