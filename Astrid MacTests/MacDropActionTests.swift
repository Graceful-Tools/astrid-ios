//  MacDropActionTests.swift
//  Regression for task 83f45d49 — drag tasks between lists, with Option to copy.

#if os(macOS)
import XCTest
import AppKit
@testable import Astrid_Mac

final class MacDropActionTests: XCTestCase {

    func testPlainDragMoves() {
        XCTAssertEqual(MacDropAction.forModifiers([]), .move)
    }

    /// Option-drag copies — the Finder convention, so it needs no explanation in the UI.
    func testOptionDragCopies() {
        XCTAssertEqual(MacDropAction.forModifiers(.option), .copy)
    }

    /// Option still wins when combined with other modifiers a user happens to be holding.
    func testOptionWinsAlongsideOtherModifiers() {
        XCTAssertEqual(MacDropAction.forModifiers([.option, .shift]), .copy)
        XCTAssertEqual(MacDropAction.forModifiers([.option, .command]), .copy)
    }

    /// Other modifiers alone must NOT copy — ⌘-drag and ⇧-drag stay a move.
    func testOtherModifiersStillMove() {
        XCTAssertEqual(MacDropAction.forModifiers(.command), .move)
        XCTAssertEqual(MacDropAction.forModifiers(.shift), .move)
        XCTAssertEqual(MacDropAction.forModifiers(.control), .move)
    }
}
#endif
