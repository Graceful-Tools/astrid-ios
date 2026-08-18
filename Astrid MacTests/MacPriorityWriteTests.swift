//  MacPriorityWriteTests.swift
//  Regression guard for Task e761d369 — "[mac] list mode tapping on priority buttons is
//  sometimes unresponsive. should be optimistic update and update in the background!"
//
//  The update was ALREADY optimistic and already backgrounded: the picker sets its binding
//  before it notifies, and `MacActions.perform` runs the write in a detached Task. What was
//  missing is that some taps never wrote anything:
//
//      guard newValue != task.priority else { return }
//
//  `task` is the value the panel was handed when it opened; `priority` is local state that has
//  been moving since. Open a task that is High, tap None (writes), tap High again — the guard
//  compares High against the SNAPSHOT, which is still High, and returns without writing. The
//  button lights up, nothing is saved, and the next refresh pulls it back to None.
//
//  Which taps are affected depends on what the priority happened to be when the panel opened,
//  which is why it reads as random.
//
//  The rule is now about the last value THIS PANEL WROTE, not about a snapshot — and it is a
//  named function so the detail panel and the quick changer cannot drift apart again.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacPriorityWriteTests: XCTestCase {

    // MARK: - The bug

    /// THE BUG, exactly: tap away and back again. The second tap must write, because the
    /// server has the value from the first tap, not the one the panel opened with.
    func testReselectingTheOriginalPriorityStillWrites() {
        var lastWritten: Task.Priority? = nil   // nothing written yet — panel just opened on .high

        XCTAssertTrue(MacPriorityWrite.shouldWrite(tapped: .none, lastWritten: lastWritten))
        lastWritten = Task.Priority.none

        XCTAssertTrue(MacPriorityWrite.shouldWrite(tapped: .high, lastWritten: lastWritten),
                      "Tapping back to the priority the panel OPENED with must still write — "
                      + "the server has the value from the previous tap")
    }

    /// The first tap always writes, even onto the priority already shown. A tap is an
    /// instruction, and the panel cannot know the snapshot still matches the server.
    func testTheFirstTapAlwaysWrites() {
        for priority in [Task.Priority.none, .low, .medium, .high] {
            XCTAssertTrue(MacPriorityWrite.shouldWrite(tapped: priority, lastWritten: nil),
                          "\(priority)")
        }
    }

    // MARK: - What the rule still suppresses

    /// Tapping the same button twice in a row does not write twice. That is the only case
    /// worth suppressing, and it is the one case the panel can be sure about.
    func testRepeatingTheSameTapDoesNotWriteTwice() {
        XCTAssertFalse(MacPriorityWrite.shouldWrite(tapped: .medium, lastWritten: .medium))
    }

    func testADifferentPriorityAlwaysWrites() {
        XCTAssertTrue(MacPriorityWrite.shouldWrite(tapped: .low, lastWritten: .medium))
    }

    // MARK: - The panel must actually use the rule

    /// A rule nothing calls is a rule that is not enforced. The stale comparison lived at the
    /// call site, so this pins that the call site is gone.
    func testTheDetailPanelDoesNotCompareAgainstItsSnapshot() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacTaskFieldsView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("guard newValue != task.priority"),
                       "Comparing the tap against the snapshot is the bug — ask MacPriorityWrite")
        XCTAssertTrue(source.contains("MacPriorityWrite.shouldWrite"),
                      "The panel must ask the shared rule")
    }
}
#endif
