//  MacBoardLeadingControlTests.swift
//  Regression guard for Task 9be8cb1b — "[mac] in board view checkbox should provide options to
//  change priority and assignee just like task details. currently completes task!"
//
//  The board card wrapped the checkbox artwork in a button whose only action was complete. So the
//  most prominent control on a card was a trapdoor: the click that looks like "pick this one"
//  finished the task, and there was no way back except finding it again in the Done column.
//
//  Task details had solved this already. `MacLeadingControlButton` shows the same artwork and
//  opens a popover with priority, assignee and an explicit Complete — its header makes the case:
//  the control already DEPICTS priority (its colour) and assignee (whose photo it is), so those
//  are the two things it should let you set.
//
//  So this is a call site adopting a component, and the guard is against it drifting back: the
//  board must not grow its own leading control, because the copy is what made the two surfaces
//  disagree in the first place.

#if os(macOS)
import XCTest
@testable import Astrid_Mac

final class MacBoardLeadingControlTests: XCTestCase {

    private func boardSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Astrid MacTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Astrid Mac/Views/MacBoardView.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The bug

    /// The card offers the same control the detail panel does.
    func testTheBoardCardUsesTheSharedLeadingControl() throws {
        XCTAssertTrue(try boardSource().contains("MacLeadingControlButton("),
                      "The board card must use the shared leading control, not its own checkbox button")
    }

    /// A bare checkbox whose only action is complete is what this task is about. If one comes
    /// back, the trapdoor is back.
    func testTheCardHasNoBareCompleteOnlyCheckbox() throws {
        let source = try boardSource()
        // The old shape, as it stood: a Button whose action was toggleComplete wrapping the
        // checkbox artwork.
        let bareButton = source.contains("Button { toggleComplete(t) } label: {")
        XCTAssertFalse(bareButton,
                       "The card's checkbox must open the picker, not complete the task outright")
    }

    // MARK: - What the control needs to be useful

    /// The assignee section is only worth offering if the members are actually loaded. An empty
    /// picker is worse than none — it reads as "this task can be assigned to nobody".
    func testTheBoardLoadsListMembersForTheAssigneePicker() throws {
        let source = try boardSource()
        XCTAssertTrue(source.contains("ListMemberService"),
                      "The board needs the list's members to build the assignee picker")
        XCTAssertTrue(source.contains("fetchMembers"),
                      "Members must be fetched, not assumed already cached by another screen")
    }

    // MARK: - The rules the picker itself relies on

    /// Completing does not disappear; it moves into the popover. The picker's own section list
    /// is what guarantees that, so pin it — a board card that offered priority and assignee but
    /// no way to complete would trade one missing action for another.
    /// In BOTH modes. Completion is the action a card must never lose, and the two modes
    /// now build different section lists — so check the promise against each of them rather
    /// than against whichever one happens to be the default.
    func testTheLeadingPickerStillOffersCompletion() {
        for mode in TaskDisplayMode.allCases {
            let sections = MacLeadingPicker.sections(for: mode)
            XCTAssertTrue(sections.contains(.complete),
                          "The popover must keep an explicit Complete action in \(mode)")
            XCTAssertTrue(sections.contains(.priority), "\(mode)")
            XCTAssertTrue(sections.contains(.assignee), "\(mode)")
        }
    }

    /// Tapping the priority a task already has still notifies, so the popover can close and save.
    /// Watching the bound value instead swallowed that tap and left the popover looking dead
    /// (task a6cd1367) — the board now depends on the same behaviour.
    func testTappingTheCurrentPriorityStillNotifies() {
        let outcome = MacPriorityTap.outcome(tapped: .high, current: .high)
        XCTAssertTrue(outcome.notify,
                      "A tap on the already-selected priority must still notify, or the popover hangs")
    }
}
#endif
