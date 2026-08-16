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
@testable import Astrid_Mac

final class MacSidebarChromeTests: XCTestCase {

    private func rootSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/App/MacRootView.swift")
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
        XCTAssertTrue(block.contains(".background(Theme.bgPrimary)"),
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

    // MARK: - Theme, not a fixed colour

    /// The bug was a colour that did not follow the theme. Hardcoding one here — even the right
    /// one for the current theme — would reintroduce exactly that, so pin the token instead.
    func testTheStripsUseTheThemeTokenRatherThanALiteralColour() throws {
        let source = try rootSource()
        guard let top = source.range(of: ".safeAreaInset(edge: .top") else {
            return XCTFail("No top inset")
        }
        let block = String(source[top.lowerBound...].prefix(400))
        XCTAssertTrue(block.contains("Theme.bgPrimary"),
                      "The strip must use the theme background token")
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
