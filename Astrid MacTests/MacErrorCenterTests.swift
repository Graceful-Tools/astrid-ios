//  MacErrorCenterTests.swift
//  Regression for task 8a5f3066 — write failures must surface (not be swallowed) and clear.

import XCTest
@testable import Astrid_Mac

@MainActor
final class MacErrorCenterTests: XCTestCase {

    func testShowSetsCurrentBanner() {
        let center = MacErrorCenter.shared
        center.clear()
        center.show("Something failed")
        XCTAssertEqual(center.current?.text, "Something failed")
        center.clear()
        XCTAssertNil(center.current)
    }

    /// The banner pairs a LOCALIZED description of what failed with whatever the server said.
    /// It used to print the call-site context verbatim ("Invite user: network down") — English in
    /// every language, since those contexts are developer strings (task 29b673c0). They now go to
    /// the log instead.
    func testReportShowsLocalizedCopyAndTheUnderlyingError() {
        struct E: LocalizedError { var errorDescription: String? { "network down" } }
        let center = MacErrorCenter.shared
        center.clear()
        center.report("Invite user", E())
        let text = center.current?.text
        XCTAssertEqual(text, "\(MacFailureCopy.message(for: "Invite user")): network down")
        XCTAssertFalse(text?.contains("Invite user") ?? true,
                       "The developer context must not reach the user")
        center.clear()
    }
}
