//  MacBoardPriorityStallTests.swift
//  Regression guard for the Mac priority stall.
//
//  Jon: "open either the task details or the task details quick picker in the board view and
//  tap on the priority, another priority, another priority, and eventually it stalls and won't
//  update the priority. I expect it to update instantly."
//
//  Two independent causes, both in `MacBoardView`, and both about comparing against a STALE
//  value rather than what the user just did.
//
//  1. `guard priority != t.priority else { priorityDraft[t.id] = nil; return }`
//     `t` is the task as captured when the card was rendered. Tap away from High and back to
//     High and the guard sees "no change", writes nothing — AND wipes the draft, so the button
//     snaps back to the snapshot. That is the stall: it always lands on whichever priority the
//     card happened to be rendered with, which is why it takes a few taps to hit.
//
//  2. The completion handler clears the draft unconditionally. Tap again while a write is in
//     flight and the earlier write's completion discards the newer tap.
//
//  This is the same defect as task e761d369, in a second place: that fix corrected the DETAIL
//  panel's `savePriority` and left the board's `setPriority` comparing against its snapshot.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardPriorityStallTests: XCTestCase {

    // MARK: - THE STALL

    /// Tapping the priority the card was RENDERED with must still write. The snapshot is not
    /// evidence about the server: the previous tap has already moved it.
    func testTappingTheSnapshotsOwnPriorityStillWrites() {
        // Card rendered while the task was .high; the user has since tapped .none (written).
        let outcome = MacBoardPriorityTap.tap(.high, lastWritten: Task.Priority.none)
        XCTAssertEqual(outcome.write, .high,
                       "tapping back to the snapshot's value must write — the server holds the "
                       + "previous tap, not the snapshot")
        XCTAssertEqual(outcome.draft, .high, "and the card must show what was pressed")
    }

    /// The first tap always writes, even onto the value already shown.
    func testTheFirstTapAlwaysWrites() {
        for p in [Task.Priority.none, .low, .medium, .high] {
            let outcome = MacBoardPriorityTap.tap(p, lastWritten: nil)
            XCTAssertEqual(outcome.write, p, "\(p)")
        }
    }

    /// A tap NEVER leaves the card showing something other than what was pressed. This is the
    /// half that made it look frozen rather than merely unsaved.
    func testEveryTapShowsWhatWasPressed() {
        for tapped in [Task.Priority.none, .low, .medium, .high] {
            for lastWritten in [Task.Priority.none, .low, .medium, .high] {
                XCTAssertEqual(MacBoardPriorityTap.tap(tapped, lastWritten: lastWritten).draft,
                               tapped, "tapped \(tapped) after writing \(lastWritten)")
            }
        }
    }

    /// The only repeat worth suppressing: the same button twice in a row, already written.
    func testTappingTheSameButtonTwiceWritesOnce() {
        XCTAssertNil(MacBoardPriorityTap.tap(.medium, lastWritten: .medium).write)
    }

    // MARK: - Rapid taps

    /// A write completing must not discard a NEWER tap. Tap high, then medium before the first
    /// finishes: high's completion must leave medium on screen.
    func testACompletingWriteDoesNotDiscardANewerTap() {
        XCTAssertEqual(MacBoardPriorityTap.draftAfterWriting(.high, currentDraft: .medium), .medium,
                       "the newer tap must survive an older write finishing")
    }

    /// When the draft IS what was written, the task becomes the truth again and the draft goes,
    /// so a later change from anywhere else is not shadowed by a stale local value.
    func testACompletingWriteClearsItsOwnDraft() {
        XCTAssertNil(MacBoardPriorityTap.draftAfterWriting(.high, currentDraft: .high))
    }

    // MARK: - The board must use the rule

    func testTheBoardDoesNotCompareAgainstItsSnapshot() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Astrid Mac/Views/MacBoardView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("guard priority != t.priority"),
                       "comparing the tap against the card's snapshot is the stall")
        XCTAssertTrue(source.contains("MacBoardPriorityTap.tap"),
                      "the board must ask the shared rule")
    }
}
#endif
