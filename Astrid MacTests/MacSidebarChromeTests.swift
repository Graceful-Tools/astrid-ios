//  MacSidebarChromeTests.swift
//  The sidebar's top and bottom strips are painted, and painted with the theme (task 46f66cb8).
//
//  Jon: "the footer background color is black across themes and the header is transparent
//  causing the lists to appear behind the list open/close button and the window
//  red/yellow/green system buttons."
//
//  Both symptoms are the same omission. A `safeAreaInset` is a SIBLING of the List, not part of
//  it, so the List's own `.background(Theme.bgPrimary)` never reached either strip. What showed
//  through was the window's material — which follows the system appearance, not ours, so it read
//  black in every theme — and the top of the sidebar had no fill at all, letting rows scroll up
//  under the titlebar controls.
//
//  These pin the fix at the source level, which is the only level available: the colours are
//  resolved by SwiftUI at render time and there is no rendered surface to sample in a unit test.
//  That is a real limit and it is why the strips carry accessibility identifiers too — a future
//  UI test can find them even though these cannot.

#if os(macOS)
import XCTest
import SwiftUI
@testable import Astrid_Mac

final class MacSidebarChromeTests: XCTestCase {

    private func rootSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The account bar is a separate view painted over the container, and it has its own copy of
    /// the "does this follow the theme" question (AITD-307).
    private func accountBarSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacSidebarAccountBar.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The header

    /// Without a top inset the list scrolls under the traffic lights. This is the whole of the
    /// second symptom.
    func testTheSidebarPaintsATopStrip() throws {
        XCTAssertTrue(try rootSource().contains(".safeAreaInset(edge: .top"),
                      "The sidebar needs an opaque strip at the top, or rows scroll under the titlebar")
    }

    func testTheTopStripIsTallEnoughToClearTheWindowButtons() {
        // The traffic lights and the sidebar toggle sit within the standard titlebar row.
        XCTAssertGreaterThanOrEqual(MacLayout.sidebarTitlebarInset, 28,
                                    "A short strip leaves rows visible beside the window buttons")
    }

    // MARK: - The footer

    /// The account bar already had a background; the inset AROUND it did not, which is what was
    /// black. Painting the container is the fix, so the container is what this pins.
    func testTheFooterStripIsPaintedAsAWhole() throws {
        let source = try rootSource()
        guard let footer = source.range(of: ".safeAreaInset(edge: .bottom, spacing: 0)") else {
            return XCTFail("The sidebar's account-bar inset is gone")
        }
        let block = String(source[footer.lowerBound...].prefix(600))

        XCTAssertTrue(block.contains("VStack"),
                      "Divider and account bar must share one container, so one background covers both")
        XCTAssertTrue(block.contains(".background(sidebarChromeBackground)"),
                      "The footer container must carry the theme background, not just the bar inside it")
    }

    /// A strip that stops at the safe area leaves a band of window material at the very edge —
    /// which is the same black, just thinner, and reads as a rendering glitch rather than a bug.
    func testBothStripsReachTheWindowEdge() throws {
        let source = try rootSource()
        XCTAssertTrue(source.contains(".ignoresSafeArea(edges: .top)"),
                      "The top strip must reach the window edge")
        XCTAssertTrue(source.contains(".ignoresSafeArea(edges: .bottom)"),
                      "The footer strip must reach the window edge")
    }


    // MARK: - The regression this file's own fix caused (task 6531e684)

    /// Painting the strips fixed the colour and froze it.
    ///
    /// `Theme.bgPrimary` reads `Theme.currentThemeMode`, which is a CACHED global refreshed by a
    /// `UserDefaults.didChangeNotification` observer. A view that neither observes `themeMode`
    /// nor passes a mode in therefore paints whatever the theme was when its body last ran —
    /// ocean, the default — and never changes. Before build 238 the footer had no background at
    /// all, so the window material showed through and tracked the SYSTEM appearance, which is
    /// why it used to look dark and follow along.
    ///
    /// So the sidebar must observe the theme, and resolve through the mode it observes.
    func testTheSidebarObservesTheThemeSoItsStripsRedraw() throws {
        let source = try rootSource()
        XCTAssertTrue(source.contains(#"@AppStorage("themeMode")"#),
                      "Without observing themeMode the sidebar's body never re-runs on a theme change")
    }

    /// And resolves with that mode rather than the cached global, because the cache is
    /// invalidated asynchronously — re-rendering at the wrong moment still reads the old theme.
    ///
    /// The mapping moved into the shared `MacSidebarChrome` for AITD-307 (two views paint this
    /// strip and only one of them was resolving correctly), so what is pinned is that the strip
    /// is resolved FROM A MODE rather than from the global — by either spelling.
    func testTheStripsResolveWithTheObservedModeRatherThanTheCachedGlobal() throws {
        let source = try rootSource()
        XCTAssertTrue(source.contains("Theme.themed(mode:")
                      || source.contains("MacSidebarChrome.background(mode:"),
                      "Pass the observed mode in; Theme.bgPrimary reads a cache refreshed on a notification")
    }

    // MARK: - The other half of the same strip (AITD-307)

    /// AITD-307: "left menu footer is white in all themes. should match theme color."
    ///
    /// The footer is TWO layers, and 6531e684 fixed one. `MacSidebarAccountBar` — the thing drawn
    /// ON TOP of the container, covering the whole strip — still ended `.background(Theme.bgPrimary)`.
    /// It observes only AuthManager, so its body never re-runs on a theme change: it painted
    /// whatever the cached global said the first time it rendered and stayed there. The container
    /// underneath being right changes nothing you can see.
    func testTheAccountBarDoesNotPaintWithTheCachedGlobalAITD307() throws {
        // The USE, not the mention: the file's comments name the trap on purpose, so a bare
        // substring check would fail on its own explanation of the bug.
        XCTAssertFalse(try accountBarSource().contains("background(Theme.bgPrimary)"),
                       "Theme.bgPrimary reads a cache this view has no reason to re-read")
    }

    /// A view that does not observe the theme has no reason to re-run, so whatever it painted
    /// first is what it paints forever. This is the actual mechanism of "white in all themes".
    func testTheAccountBarObservesTheThemeAITD307() throws {
        XCTAssertTrue(try accountBarSource().contains(#"@AppStorage("themeMode")"#),
                      "Without observing themeMode the account bar never redraws on a theme change")
    }

    /// Both layers of the strip resolve through ONE definition — writing the mapping twice is how
    /// they drifted apart in the first place.
    func testBothLayersOfTheStripShareOneDefinitionAITD307() throws {
        XCTAssertTrue(try accountBarSource().contains("MacSidebarChrome.background(mode:"))
        XCTAssertTrue(try rootSource().contains("MacSidebarChrome.background(mode:"))
    }

    /// The behavioural half: the shared mapping must actually answer differently per theme, or
    /// resolving through it correctly still paints the same colour everywhere.
    func testTheSharedStripColourDiffersPerThemeAITD307() {
        let light = MacSidebarChrome.background(mode: "light")
        let dark = MacSidebarChrome.background(mode: "dark")
        let ocean = MacSidebarChrome.background(mode: "ocean")
        XCTAssertNotEqual(light, dark)
        XCTAssertNotEqual(light, ocean)
        XCTAssertNotEqual(dark, ocean)
        XCTAssertEqual(light, .white, "light is the white the bug was stuck on — in light ONLY")
    }

    // MARK: - Theme, not a fixed colour

    /// The bug was a colour that did not follow the theme. Hardcoding one here — even the right
    /// one for the current theme — would reintroduce exactly that, so pin the token instead.
    func testTheStripsUseTheThemeTokenRatherThanALiteralColour() throws {
        let source = try rootSource()
        guard let top = source.range(of: ".safeAreaInset(edge: .top") else {
            return XCTFail("No top inset")
        }
        let block = String(source[top.lowerBound...].prefix(400))
        // Pins the PROPERTY, not the spelling. This used to require the literal
        // `Theme.bgPrimary`, which is how it kept passing while the strips were frozen on
        // ocean (task 6531e684) — that token reads a cached global. What matters is that the
        // colour is themed and resolved from the observed mode, which the helper does.
        XCTAssertTrue(block.contains("sidebarChromeBackground"),
                      "The strip must use the themed, mode-resolved background")
        XCTAssertFalse(block.contains("Color.black") || block.contains(".black"),
                       "A literal colour is the bug this task is about")
    }

    /// And the token itself must actually differ between themes, or painting with it changes
    /// nothing. This is the one assertion here that tests behaviour rather than source.
    func testTheThemeBackgroundDiffersBetweenThemes() {
        let light = Theme.Dark.bgPrimary
        let ocean = Theme.Ocean.bgPrimary
        XCTAssertNotEqual(light, ocean,
                          "If every theme's background matched, 'theme color' would be meaningless")
    }
}
#endif
