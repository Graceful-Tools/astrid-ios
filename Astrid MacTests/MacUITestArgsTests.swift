//  MacUITestArgsTests.swift
//  Regression tests for Task 69ff12e7 — "[mac tests] -uiTestSelectRow no longer reaches the shell".
//
//  The two-token form `-uiTestSelectRow 0` makes the app launch with zero windows, so every UI
//  test that needs a selected row died at "should reach the shell". The single-token form works,
//  so that is what the hook advertises — while still parsing the old form rather than ignoring it.

import XCTest
@testable import Astrid_Mac

final class MacUITestArgsTests: XCTestCase {

    /// The supported form: one token, no bare value for the launcher to choke on.
    func testParsesSingleTokenForm() {
        XCTAssertEqual(MacUITestArgs.selectedRowIndex(from: ["-uiTesting", "-uiTestSelectRow=2"]), 2)
        XCTAssertEqual(MacUITestArgs.selectedRowIndex(from: ["-uiTestSelectRow=0"]), 0)
    }

    /// The old form still parses — an existing invocation should not silently select nothing.
    func testStillParsesLegacyTwoTokenForm() {
        XCTAssertEqual(MacUITestArgs.selectedRowIndex(from: ["-uiTesting", "-uiTestSelectRow", "3"]), 3)
    }

    func testAbsentOrMalformedFlagSelectsNothing() {
        XCTAssertNil(MacUITestArgs.selectedRowIndex(from: ["-uiTesting"]))
        XCTAssertNil(MacUITestArgs.selectedRowIndex(from: []))
        XCTAssertNil(MacUITestArgs.selectedRowIndex(from: ["-uiTestSelectRow=abc"]))
        XCTAssertNil(MacUITestArgs.selectedRowIndex(from: ["-uiTestSelectRow"]), "Trailing flag, no value")
    }

    /// A flag that merely starts with the same letters must not be mistaken for this one.
    func testDoesNotMatchAPrefixedFlag() {
        XCTAssertNil(MacUITestArgs.selectedRowIndex(from: ["-uiTestSelectRowsAll=2"]))
    }
}
