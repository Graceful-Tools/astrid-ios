//  MacEditingSessionTests.swift
//  Task 55010e29 — the Mac half of "one editing session at a time on iOS + Mac".
//
//  `EditingSession` lives in Core/Layout, which the Mac target compiles, so the coordinator is
//  ALREADY available here. This asserts that rather than assuming it: the rule is only
//  cross-platform if the Mac can actually reach it, and a shared file silently dropping out of
//  the Mac target is a thing that has happened in this project before.
//
//  The Mac detail is the reason this matters. It carries three separate focus flags —
//  `titleFocused`, `notesFocused`, `commentFocused` — plus an `isEditing` for row rename, each
//  with its own save moment. That is the same dozen-editors-one-rule-each problem the iOS side
//  has, so both platforms need the same coordinator rather than a Mac-shaped copy of it.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

@MainActor
final class MacEditingSessionTests: XCTestCase {

    /// The shared coordinator is reachable from the Mac target at all.
    func testTheCoordinatorIsAvailableOnMac() {
        let session = EditingSession()
        XCTAssertNil(session.activeEditor)
    }

}
#endif
