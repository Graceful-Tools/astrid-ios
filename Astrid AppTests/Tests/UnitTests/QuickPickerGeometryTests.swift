//  QuickPickerGeometryTests.swift
//  Regression guard for Task AITD-391 — "[ios] quick picker on boards should open to the right of
//  the checkbox with the height of the select box big enough to show at least 3 rows of assignees
//  on scroll. Currently it opens above or below and sometimes isn't big enough".
//
//  Two faults that compounded each other.
//
//  The ANCHOR: `TaskRowView`'s `.popover` sat at the end of the root HStack, so its source rect
//  was the whole card body — not the 34pt control that was tapped — and no `arrowEdge` was given.
//  UIKit therefore chose a direction from the space around the card, which on a board column is
//  above or below. The Mac has always done this properly (`MacTaskRow` attaches the popover to
//  the checkbox column and pins an edge); iOS never got the same treatment.
//
//  The HEIGHT: `TaskQuickChanger` fixes its width and leaves height fully intrinsic, and the
//  assignee editor inside it is an UNBOUNDED ScrollView over every member, agent and the
//  "Someone else" field. The popover asked for whatever that list wanted and the system squeezed
//  it into the little room the bad anchor had left. Opening to the side is what gives it room;
//  bounding the list is what stops it demanding more than three rows' worth in the first place.
//
//  The numbers are pinned here rather than spelled inline in a view because there was NO test
//  coverage of this picker's anchor or height on either platform — the helper is what makes the
//  fix assertable at all. The repo's precedent for pure, testable popover geometry is
//  `MacDetailReveal.anchor(...)`.

import XCTest
import SwiftUI
@testable import Astrid_App

final class QuickPickerGeometryTests: XCTestCase {

    private func appSource(_ path: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // UnitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // Astrid AppTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - To the right of the checkbox

    /// The report's first half, as a value. `.trailing` is the edge of the CONTROL the arrow
    /// leaves from, so the popover lands to its right — a board column has a full height of room
    /// beside a card and almost none above or below it.
    func testThePickerOpensToTheRightOfTheControl() {
        XCTAssertEqual(QuickPickerGeometry.arrowEdge, .trailing,
                       "above/below is the bug — a board column has room to the side, not vertically")
    }

    // MARK: - At least three assignees, then scroll

    /// A row is a 32pt avatar with 8pt of padding above and below, and rows sit 12pt apart. So
    /// three of them is 3×48 + 2×12. Spelled out because the point of the constant is that the
    /// floor is *derived* from the row, not guessed — a row that grows must move this with it.
    func testTheListIsTallEnoughForThreeAssignees() {
        XCTAssertEqual(QuickPickerGeometry.assigneeRowHeight, 48,
                       "32pt avatar + 8pt padding top and bottom")
        XCTAssertEqual(QuickPickerGeometry.assigneeListMinHeight,
                       3 * QuickPickerGeometry.assigneeRowHeight + 2 * QuickPickerGeometry.assigneeRowSpacing,
                       "the floor is three rows and the two gaps between them")
        XCTAssertEqual(QuickPickerGeometry.assigneeListMinHeight, 168, accuracy: 0.001)
    }

    /// A floor alone does not fix it. Without a ceiling the unbounded list re-inflates the
    /// popover for a list with many members, the system squeezes it again, and the three rows
    /// are gone — which is the reported "sometimes isn't big enough".
    func testTheListHasACeilingSoALongMemberListCannotReinflateThePopover() {
        XCTAssertGreaterThan(QuickPickerGeometry.assigneeListMaxHeight,
                             QuickPickerGeometry.assigneeListMinHeight,
                             "a ceiling below the floor would be a fixed height, not a scrolling list")
        XCTAssertLessThanOrEqual(QuickPickerGeometry.assigneeListMaxHeight, 400,
                                 "the ceiling exists to keep the popover a popover")
    }

    /// The floor must never fall below three rows, whatever anyone tunes the ceiling to. This is
    /// the sentence from the task, held as an invariant rather than as a literal.
    func testThreeRowsIsAFloorNotACoincidence() {
        XCTAssertGreaterThanOrEqual(QuickPickerGeometry.visibleAssigneeRows, 3)
        XCTAssertGreaterThanOrEqual(
            QuickPickerGeometry.assigneeListMinHeight,
            CGFloat(3) * QuickPickerGeometry.assigneeRowHeight,
            "three rows must fit in the floor even before the gaps are counted")
    }

    // MARK: - …and the views actually ask for it

    /// A helper nobody calls changes nothing. The popover has to hang off the leading control,
    /// not off the row — that source rect is the whole reason it flipped above and below.
    func testThePopoverIsAnchoredToTheLeadingControlAndNotTheRow() throws {
        let source = try appSource("Astrid App/Views/Tasks/TaskRowView.swift")
        XCTAssertTrue(source.contains("QuickPickerGeometry.arrowEdge"),
                      "the row must pin the arrow edge — an unpinned popover is the reported bug")
        XCTAssertTrue(source.contains("leadingControl"),
                      "the control the popover hangs off has to be a view of its own to hang off")
        XCTAssertTrue(source.contains(".presentationCompactAdaptation(.popover)"),
                      "without this it becomes a full sheet on iPhone")
    }

    /// The bound list, likewise — and only for the popover. The compact path puts the same editor
    /// in a sheet with its own detents, where a 168–320pt clamp would be a new bug.
    func testTheAssigneeEditorAsksForTheBoundedHeightOnlyInThePopover() throws {
        let picker = try appSource("Astrid App/Views/Components/InlineAssigneePicker.swift")
        XCTAssertTrue(picker.contains("QuickPickerGeometry.assigneeListMinHeight"),
                      "the editor must take the floor from the shared helper")
        XCTAssertTrue(picker.contains("QuickPickerGeometry.assigneeListMaxHeight"),
                      "…and the ceiling, or a long list re-inflates the popover")

        let changer = try appSource("Astrid App/Views/Components/TaskQuickChanger.swift")
        XCTAssertTrue(changer.contains("boundsListHeight: true"),
                      "the quick changer is the popover surface — it is what opts in")
    }
}
