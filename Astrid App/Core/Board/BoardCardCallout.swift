//  BoardCardCallout.swift
//  How a board card opens its details (AITD-679). Jon: "Stop opening board task details by
//  expanding the board task. Open, just like task details from a task row, but pick the left or
//  right side based on the spacing on screen."
//
//  A card used to open its details inline, in place of its face (AITD-628, AITD-661). On a
//  multi-column board it now opens the SAME details panel a list row opens, docked on whichever
//  side of the card has more room, with the panel's arrow aimed at the card. Where the panel goes
//  and where its arrow points are astrid-core's `calloutPlacement` (`rows::callout`, AITD-678): the
//  arithmetic is not repeated here. iPhone, with one column the width of the screen, keeps the
//  full-screen push (AITD-642).
//
//  The rules are here, not in a view, so the iPad board and the Mac board cannot mean different
//  things by the same tap.

import AstridCore
import CoreGraphics

enum BoardCardCallout {

    /// Where a card tap takes the task.
    enum Route: Equatable {
        /// The details panel beside the card — iPad's split layout.
        case panel
        /// The full-screen push — iPhone, or an iPad set to push.
        case push
    }

    static func route(splitLayout: Bool, forcePush: Bool) -> Route {
        splitLayout && !forcePush ? .panel : .push
    }

    /// Tapping the card whose details are open closes them; tapping any other card opens that one.
    static func toggle(current: String?, tapped: String) -> String? {
        current == tapped ? nil : tapped
    }

    /// Which edge of the board the panel docks on.
    enum Side: Equatable {
        case leading, trailing
    }

    /// Where the panel goes beside a card: its side and its box, in the same space as `card`.
    struct Placement: Equatable {
        let side: Side
        let frame: CGRect
    }

    /// The panel beside `card`, inside `viewport`, `panelWidth` wide — its arrow included — and as
    /// tall as the viewport allows. The side has more room (core: ties go right) and the panel's
    /// near edge, where the arrow's tip is, TOUCHES the card (AITD-679, Jon: "the arrow doesn't
    /// touch the task row... It should"); it used to dock at the screen's edge instead. Decided
    /// once, when the card is tapped: a panel that moved as the board scrolled would chase it.
    static func placement(card: CGRect, viewport: CGRect, panelWidth: CGFloat) -> Placement? {
        guard let placed = try? CoreRules.calloutPlacement(
            anchor: card, viewport: viewport,
            size: CGSize(width: panelWidth, height: max(0, viewport.height - gutter * 2)))
        else { return nil }
        return Placement(side: placed.side == .left ? .leading : .trailing, frame: placed.frame)
    }

    /// The side alone (`placement`'s), trailing when the core could not answer.
    static func side(card: CGRect, viewport: CGRect, panelWidth: CGFloat) -> Side {
        placement(card: card, viewport: viewport, panelWidth: panelWidth)?.side ?? .trailing
    }

    /// How much of the panel's width, on its card side, the arrow takes: its width less the point
    /// it overlaps the face by. With exactly this much room the arrow's tip lands on the panel's
    /// near edge — on the card, since the core puts that edge there.
    static func arrowRoom(arrowWidth: CGFloat, overlap: CGFloat) -> CGFloat {
        arrowWidth - overlap
    }

    /// The arrow's centre down the panel's edge, in the panel's own coordinates, for a card at
    /// `card` (nil: it scrolled away, so the arrow centres). The core places a callout of the
    /// panel's size in a viewport one gutter wider than the panel, which pins the core's box to
    /// the panel exactly; its `arrowOffset` is then the panel's own y — aimed at the card's middle
    /// and kept off the rounded corners.
    static func arrowY(card: CGRect?, panel: CGRect) -> CGFloat {
        guard let card, panel.height > 0,
              let placed = try? CoreRules.calloutPlacement(
                anchor: card, viewport: panel.insetBy(dx: -gutter, dy: -gutter), size: panel.size)
        else { return panel.height / 2 }
        return CGFloat(placed.top + placed.arrowOffset) - panel.minY
    }

    // MARK: - The open card moving column — ADEV-175

    /// Where the open task's card is: the task and the column holding it.
    struct Spot: Equatable {
        let taskId: String
        let columnId: String
    }

    /// The open card moved to another column — completed into Done, marked to-do out of it, or
    /// set to another status from its details (ADEV-175, Jon: "update where the arrow on the task
    /// details points so it points to the moved task item"). Another task opening, the panel
    /// opening or closing, and the card staying put are not moves. The new spot, or nil.
    static func moved(from old: Spot?, to new: Spot?) -> Spot? {
        guard let old, let new, old.taskId == new.taskId, old.columnId != new.columnId else { return nil }
        return new
    }

    /// Which edge of the board the column a card moved into scrolls to: the edge the card was
    /// opened on, so it lands on the same side it left and the panel — docked on the other side —
    /// does not cover it. No opened card (a panel opened from elsewhere): the leading edge, as a
    /// selection's column always scrolled.
    static func scrollEdge(openedCard: CGRect?, board: CGRect) -> Side {
        guard let openedCard, board.width > 0 else { return .leading }
        return openedCard.midX > board.midX ? .trailing : .leading
    }

    /// astrid-core's `rows::callout::GUTTER`, published in its fixture.
    static let gutter: CGFloat = 8
}
