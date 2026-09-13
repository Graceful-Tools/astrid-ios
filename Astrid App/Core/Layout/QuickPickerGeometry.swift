//  QuickPickerGeometry.swift
//  Where the row's quick picker opens, and how tall its member list is. (Task AITD-391)
//
//  The picker used to take both answers from whatever SwiftUI worked out on the spot, and on a
//  board it got them both wrong. The popover hung off the whole row rather than the control that
//  was tapped, so the system chose above or below from the space around the card — which on a
//  board column is barely any. And the assignee list inside it was an unbounded ScrollView, so
//  the popover asked for the height of every member and then got squeezed into the little room
//  the anchor had left. Each fault made the other worse.
//
//  The anchor took two more passes: AITD-393 moved it to the row's trailing edge, AITD-395 put
//  it back on the checkbox. The EDGE took a fourth (AITD-397): both earlier passes read
//  `arrowEdge` as the side of the anchor the popover leaves from, and on iOS it is the side of
//  the POPOVER the arrow sits on. See `arrowEdge`.
//
//  Both answers live here as values rather than as literals inside a view, for the reason
//  `TaskLeadingControl` next door exists: a number written into a view is a number no test can
//  reach, and there was no coverage of this picker's anchor or height on either platform.
//
//  Pure — no view, no state — so the geometry can be asserted without building anything.

import SwiftUI

enum QuickPickerGeometry {

    // MARK: - Where it opens

    /// The edge of the POPOVER its arrow sits on. `.leading` puts the arrow on the popover's
    /// left edge, so the picker opens to the RIGHT of the checkbox with the arrow aimed back at
    /// the control that was tapped.
    ///
    /// That is the definition on iOS, and it is the opposite of how AITD-393 and AITD-395 read
    /// it. Both took `arrowEdge` for the edge of the ANCHOR the popover leaves from — which is
    /// what NSPopover's `preferredEdge` means on the Mac, and why `MacTaskRow`'s `.bottom` opens
    /// BELOW its checkbox. On iOS SwiftUI hands the value to UIKit as the popover's arrow
    /// direction: `.trailing` became "arrow on the right", the popover was placed to the LEFT
    /// of its anchor, and with the checkbox at the head of the row there was no left to place
    /// it in. UIKit squashed it against the screen edge, arrow on its right, pointing at the
    /// checkbox — the AITD-397 report, and the same shape AITD-395 saw off the trailing pin and
    /// misread as UIKit "discarding" the direction. It was honouring it.
    ///
    /// Measured 2026-09-13 with a throwaway app on the iPhone 17 simulator: two buttons at the
    /// left edge, one popover per edge. `.trailing` — a sliver at the screen edge, arrow right.
    /// `.leading` — popover to the button's right, arrow on its left edge. This is the latter.
    ///
    /// A board card is short and its column is tall: there is a full height of room beside a
    /// card and almost none above or below it, so an unpinned popover flips above or below —
    /// the AITD-391 complaint, and why the edge is pinned at all.
    ///
    /// The anchor is `TaskRowView.leadingControl` — the checkbox. AITD-393's trailing pin had
    /// nothing to do with the arrow and is gone: the picker is a fixed 280pt and covers the
    /// card from either anchor, so the checkbox is the one that gives the arrow something to
    /// point at. Clearing the card would need above/below or a much narrower popover, and
    /// neither is a thing to change while fixing an arrow.
    static let arrowEdge: Edge = .leading

    // MARK: - How tall the member list is

    /// One assignee row: a 32pt avatar with `Theme.spacing8` above and below it.
    ///
    /// Derived rather than measured, so a row that grows moves the floor with it instead of
    /// silently showing two and a half people.
    static let assigneeRowHeight: CGFloat = 32 + 8 * 2

    /// The `VStack` spacing between rows in the editor (`Theme.spacing12`).
    static let assigneeRowSpacing: CGFloat = 12

    /// At least three people visible before you have to scroll. Fewer than that and the list
    /// reads as a cropped accident rather than as something to scroll.
    static let visibleAssigneeRows = 3

    /// The floor: three rows and the two gaps between them.
    static var assigneeListMinHeight: CGFloat {
        CGFloat(visibleAssigneeRows) * assigneeRowHeight
            + CGFloat(visibleAssigneeRows - 1) * assigneeRowSpacing
    }

    /// The ceiling, in the same units — five rows.
    ///
    /// A floor alone does not fix the report. Left unbounded above, a list with many members
    /// re-inflates the popover, the system squeezes it back, and the three rows are gone again —
    /// which is exactly the "sometimes isn't big enough" half. The ceiling is what keeps a
    /// popover a popover and turns the overflow into scrolling.
    static var assigneeListMaxHeight: CGFloat {
        5 * assigneeRowHeight + 4 * assigneeRowSpacing
    }
}
