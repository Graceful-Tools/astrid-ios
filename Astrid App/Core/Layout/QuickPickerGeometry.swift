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
//  Both answers live here as values rather than as literals inside a view, for the reason
//  `TaskLeadingControl` next door exists: a number written into a view is a number no test can
//  reach, and there was no coverage of this picker's anchor or height on either platform.
//
//  Pure — no view, no state — so the geometry can be asserted without building anything.

import SwiftUI

enum QuickPickerGeometry {

    // MARK: - Where it opens

    /// The edge of the ANCHOR the popover's arrow leaves from, so the picker lands to the
    /// anchor's RIGHT.
    ///
    /// A board card is short and its column is tall: there is a full height of room beside a
    /// card and almost none above or below it, so an unpinned popover flips above or below.
    ///
    /// Pinning the edge is only half of it — what the popover attaches to decides where "right"
    /// begins. AITD-391 attached it to the 34pt leading control and so opened the picker just
    /// inside the card's LEFT edge, on top of the card (AITD-393). It hangs off
    /// `trailingPickerAnchor` instead: the same edge, measured from the far side of the row, so
    /// the picker clears the task box.
    static let arrowEdge: Edge = .trailing

    /// The width of that trailing pin.
    ///
    /// Wide enough to have a source rect — a zero-width view gives UIKit nothing to point an
    /// arrow at — and narrow enough that it is not layout: it sits after the row's `Spacer()`,
    /// so anything more would push the card's content off its right edge.
    static let trailingAnchorWidth: CGFloat = 1

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
