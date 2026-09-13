//  QuickPickerGeometryTests.swift
//  Regression guard for Task AITD-393 — "Quick picker should be on the right of the task box on
//  board view. You put it on left!" — and, underneath it, for Task AITD-391.
//
//  Rewritten for Task AITD-395 — "arrow on quick set popover should be on the left of the
//  popover pointing at the checkbox" — and again for Task AITD-397 — "Arrow on Right of
//  popover, pointing Left at the checkbox. You did it wrong again."
//
//  Four reports on one popover. AITD-391 hung it off the 34pt leading control; AITD-393 moved
//  it to a 1pt pin at the row's trailing edge; AITD-395 put it back on the checkbox. All three
//  kept `arrowEdge: .trailing`, reading it as the edge of the ANCHOR the popover leaves from.
//  On iOS it is the edge of the POPOVER the arrow sits on — UIKit's arrow direction — so
//  `.trailing` asked for the arrow on the popover's RIGHT and the popover to the LEFT of the
//  checkbox, where a phone has no room. That is the squashed popover with a right-hand arrow in
//  every one of these reports; AITD-395 saw it off the trailing pin and misread it as UIKit
//  discarding the direction. Measured 2026-09-13 in a throwaway app: `.leading` opens to the
//  right with the arrow on the left. `QuickPickerGeometry.arrowEdge` has the write-up.
//
//  The popover covers the card from either anchor. What the checkbox anchor buys is an arrow
//  that points at the control you tapped. Clearing the card is not reachable at 280pt on a phone
//  and would be its own decision. The height half of AITD-391 was right and is unchanged.
//
//  The original report, for the record — Task AITD-391 — "[ios] quick picker on boards should open to the right of
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

    // MARK: - To the right, not above or below

    /// The edge, as a value. On iOS `arrowEdge` is the edge of the POPOVER the arrow sits on,
    /// so `.leading` is "arrow on the left, popover to the right of the checkbox". A board
    /// column has a full height of room beside a card and almost none above or below it, which
    /// is why the edge is pinned rather than left to UIKit.
    ///
    /// This constant WAS the AITD-397 bug — `.trailing`, read the Mac way — after two passes that
    /// only moved the anchor. The UI test in `QuickPickerPopoverUITests` measures the real
    /// popover's frame against the checkbox; this test keeps the value from drifting back.
    func testThePickerOpensToTheRightOfItsAnchor_AITD397() {
        XCTAssertEqual(QuickPickerGeometry.arrowEdge, .leading,
                       "AITD-397: on iOS `arrowEdge` is the edge of the POPOVER the arrow sits on. "
                       + "`.leading` puts the arrow on the popover's left edge, so the popover opens to "
                       + "the RIGHT of the checkbox. `.trailing` is the bug: arrow on the right, popover "
                       + "shoved off the left of the screen.")
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

    /// A helper nobody calls changes nothing — and hanging it off the wrong view is what these
    /// three reports have been circling.
    ///
    /// AITD-395: "arrow on quick set popover should be on the left of the popover pointing at
    /// the checkbox". The arrow points at whatever the popover is attached to, so the anchor
    /// decides what it points AT and `arrowEdge` decides which side of the popover it is ON.
    /// This test covers the first; `testThePickerOpensToTheRightOfItsAnchor_AITD397` the second.
    ///
    /// AITD-393 moved the anchor to a 1pt pin at the row's trailing edge to clear the task box.
    /// The changer is a fixed 280pt, so it covers the card from either anchor; only the checkbox
    /// anchor also points the arrow at something.
    func testThePopoverHangsOffTheCheckboxSoItsArrowPointsAtIt() throws {
        let source = try appSource("Astrid App/Views/Tasks/TaskRowView.swift")

        XCTAssertTrue(source.contains("QuickPickerGeometry.arrowEdge"),
                      "the row must pin the arrow edge — an unpinned popover picks above/below")
        XCTAssertTrue(source.contains(".presentationCompactAdaptation(.popover)"),
                      "without this it becomes a full sheet on iPhone")

        let marker = ".popover(isPresented: $showingQuickChanger"
        guard let range = source.range(of: marker) else {
            return XCTFail("the quick changer popover moved — this guard needs rewriting")
        }

        // The view the popover modifies is the last token before the modifier.
        let anchor = source[..<range.lowerBound]
            .split(whereSeparator: { $0.isWhitespace })
            .last
            .map(String.init) ?? ""

        XCTAssertEqual(anchor, "leadingControl",
                       "AITD-395: anchored to \(anchor). The arrow sits on the popover's leading "
                       + "edge only when the popover opens off the checkbox")
    }

    /// The trailing pin AITD-393 added is gone, not merely unused. Left in the file it reads as
    /// a second, live anchor, which is how the next person re-attaches the popover to it.
    func testTheTrailingPinIsGoneRatherThanLeftLyingAround() throws {
        let source = try appSource("Astrid App/Views/Tasks/TaskRowView.swift")
        XCTAssertFalse(source.contains("trailingPickerAnchor"),
                       "the row's trailing pin has no remaining purpose — remove it with its anchor")
        XCTAssertFalse(source.contains("trailingAnchorWidth"),
                       "…and the width constant that only that pin used")
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
