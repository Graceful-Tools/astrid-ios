//  MacFlowRowsTests.swift
//  The Mac list pills wrap through the shared `FlowRows` / `FlowLayout` in `Astrid App/Core/Layout`
//  (a Mac-only copy existed until the 2026-09-13 dedupe pass).
//  Regression guard for Task 459caa56 — "[mac] list pills should wrap at the pill and not become
//  multiline within the list."
//
//  Two separate faults produced one symptom in `MacListPicker`:
//
//  1. The pills sat in a plain `HStack`, which never wraps. With several lists it just squeezed.
//  2. The pill's own `Text` had no line limit, so the squeeze pushed the NAME onto a second line —
//     a two-line pill, which is what "multiline within the list" describes.
//
//  So the row has to break BETWEEN pills, and a pill has to stay one line. This covers the first
//  half: the pure geometry of where the breaks fall, testable without laying out a view.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacFlowRowsTests: XCTestCase {

    // MARK: - The second half: a pill stays one line

    func testThePillTextIsLimitedToOneLine() throws {
        let root = RepositoryLocator.root
        let source = try String(
            contentsOf: root.appendingPathComponent("Astrid Mac/Views/MacListPicker.swift"),
            encoding: .utf8)
        let chips = try SourceSlice.after("private var chips", in: source)
        XCTAssertTrue(chips.contains("lineLimit(1)"),
                      "a pill must not wrap its own name onto a second line")
        XCTAssertTrue(chips.contains("FlowLayout"),
                      "the pills must sit in the wrapping layout, not a plain HStack")
    }
}
#endif
