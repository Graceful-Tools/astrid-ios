//  MacSymbolsTests.swift
//  Task 59d51b80 — "on task details use the ellipsis button for the top right … currently it is a ^".
//
//  The detail header's overflow menu was labelled `Image(systemName: "ellipsis.vertical")`.
//  That symbol does not exist on macOS, so the label rendered EMPTY and the only thing left
//  to see was the chevron that .menuStyle(.borderlessButton) draws for itself — the "^".
//
//  A wrong SF Symbol name fails silently at runtime: no crash, no warning, just a blank
//  control. These tests resolve the names through NSImage the way AppKit will, so a name
//  that does not exist fails here instead of shipping as an invisible button.

import XCTest
import AppKit
@testable import Astrid_Mac

final class MacSymbolsTests: XCTestCase {

    private func resolves(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// The regression: the overflow menu must be labelled with a symbol that actually renders.
    func testDetailMenuSymbolResolves() {
        XCTAssertTrue(resolves(MacSymbols.detailMenu),
                      "Task 59d51b80: an unresolvable symbol renders an empty label, leaving only the menu chevron")
    }

    /// The trap itself, pinned: this is the name that was there, and it does not exist.
    func testEllipsisVerticalIsNotARealMacSymbol() {
        XCTAssertFalse(resolves("ellipsis.vertical"),
                       "If Apple ever adds this, the workaround in MacSymbols can be revisited")
    }

    /// Every SF Symbol the Mac chrome names. A blank button is invisible in review but obvious here.
    func testEveryMacSymbolResolves() {
        let names = [
            "arrow.clockwise", "arrowshape.turn.up.left", "bubble.left.and.bubble.right",
            "checklist", "checkmark", "chevron.down", "circle", "ellipsis.circle",
            "exclamationmark.triangle.fill", "eye", "flame.fill", "gearshape",
            "line.3.horizontal.decrease.circle", "list.bullet", "magnifyingglass",
            "minus.circle.fill", "paperclip", "person.crop.circle.fill", "plus",
            "plus.circle", "plus.circle.fill", "sparkles", "square.and.arrow.up",
            "square.grid.2x2", "timer", "trash", "wifi.slash", "xmark", "xmark.circle.fill",
        ]
        for name in names {
            XCTAssertTrue(resolves(name), "SF Symbol '\(name)' does not resolve on macOS")
        }
    }
}
