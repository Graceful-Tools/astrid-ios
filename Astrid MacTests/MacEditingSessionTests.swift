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

    /// The Mac's three detail editors are exactly the case this exists for: opening the notes
    /// field while the title is being edited must commit the title, not leave both live.
    func testOpeningNotesWhileEditingTheTitleCommitsTheTitle() {
        var committed: [String] = []
        let session = EditingSession(onCommit: { committed.append($0) })

        session.begin("mac.title")
        session.begin("mac.notes")

        XCTAssertEqual(session.activeEditor, "mac.notes")
        XCTAssertEqual(committed, ["mac.title"], "the title's edit was dropped on the floor")
    }

    /// Closing the detail commits whatever was open — the Mac equivalent of navigating away.
    func testClosingTheDetailCommitsTheOpenEditor() {
        var committed: [String] = []
        let session = EditingSession(onCommit: { committed.append($0) })

        session.begin("mac.comment")
        session.commitAll()

        XCTAssertNil(session.activeEditor)
        XCTAssertEqual(committed, ["mac.comment"])
    }

    /// Both platforms must agree on the save policy, or "click out to save" means two different
    /// things depending on which app you are in.
    func testResigningSavesRatherThanDiscarding() {
        var committed: [String] = []
        var cancelled: [String] = []
        let session = EditingSession(onCommit: { committed.append($0) },
                                     onCancel: { cancelled.append($0) })

        session.begin("mac.title")
        session.begin("mac.notes")

        XCTAssertTrue(cancelled.isEmpty, "displacing an editor must never discard the edit")
        XCTAssertEqual(committed, ["mac.title"])
    }
}
#endif
