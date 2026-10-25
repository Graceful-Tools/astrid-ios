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

    /// Every SF Symbol the Mac target names, read from its source rather than a hand-kept list
    /// (AITD-539) — a list goes stale the first time someone adds a button without adding a line
    /// here, and the blank button ships. Interpolated names are skipped; they are not literals.
    func testEveryMacSymbolResolves() throws {
        let root = RepositoryLocator.root.appendingPathComponent("Astrid Mac")
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        let literal = try NSRegularExpression(pattern: #"(?:systemName|systemImage|systemSymbolName):\s*"([^"\\]+)""#)
        var names: [String: String] = [:]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for match in literal.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
                guard let range = Range(match.range(at: 1), in: source) else { continue }
                names[String(source[range]), default: file.lastPathComponent] = file.lastPathComponent
            }
        }
        XCTAssertGreaterThan(names.count, 20, "found only \(names.count) symbols — the scan is reading nothing")
        for (name, file) in names.sorted(by: { $0.key < $1.key }) where !resolves(name) {
            // The one deliberate non-symbol, pinned by the test above.
            guard name != "ellipsis.vertical" else { continue }
            XCTFail("SF Symbol '\(name)' (\(file)) does not resolve on macOS — it renders as a blank control")
        }
    }
}
