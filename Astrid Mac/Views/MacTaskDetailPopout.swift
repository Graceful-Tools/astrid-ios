//  MacTaskDetailPopout.swift
//  Astrid for Mac — the floating task detail pop-out (2766d9a4): a rounded card with an arrow back
//  at the selected row, or at a board card (AITD-679), docked on the side the caller picked.
//  Moved out of MacRootView (AITD-346's size ratchet) when it learned to dock on either side.

#if os(macOS)
import SwiftUI

struct MacTaskDetailPopout: View {
    let task: Task
    /// Beside a board card: the core's box, the arrow's tip touching the card (AITD-679). nil
    /// beside a list, where the pop-out docks trailing with margins of its own.
    let placed: BoardCardCallout.Placement?
    /// The content area the pop-out lies in (global), which `placed` is measured against.
    let viewport: CGRect
    let panelWidth: CGFloat
    /// Beside a board's cards rather than a list's rows.
    let besideBoard: Bool
    /// The selected list row's middle (global).
    let selectedRowMidY: CGFloat?
    /// The open board card's frame (global).
    let selectedCardFrame: CGRect?
    let onClose: () -> Void

    private var side: BoardCardCallout.Side { placed?.side ?? .trailing }
    /// No margins of its own beside a card, and exactly the arrow's reach on the card side.
    private var besideCard: Bool { placed != nil }
    private static var arrowRoom: CGFloat {
        BoardCardCallout.arrowRoom(arrowWidth: MacLayout.detailArrowWidth, overlap: MacLayout.arrowOverlap)
    }

    /// The pop-out's box beside `card`: a panel `panelWidth` wide plus the arrow's reach.
    static func placement(card: CGRect, viewport: CGRect, panelWidth: CGFloat) -> BoardCardCallout.Placement? {
        guard viewport.width > 0 else { return nil }
        return BoardCardCallout.placement(card: card, viewport: viewport, panelWidth: panelWidth + arrowRoom)
    }

    var body: some View {
        if let placed {
            popout
                .frame(width: placed.frame.width, height: placed.frame.height)
                .offset(x: placed.frame.minX - viewport.minX, y: placed.frame.minY - viewport.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            popout
        }
    }

    private var popout: some View {
        // ✕ / "Task Details" / ⋯ live in the detail's own web-style header (df22157f).
        MacTaskDetailView(task: task, onClose: onClose)
            .frame(width: panelWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(MacDetailChrome.background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            // The SELECTION outline, not a neutral hairline (AITD-302). The panel unfolds out of
            // the selected row, so it wears the same border that row wears — the same call, so
            // the two cannot drift, and every theme follows Theme.accent for free. In the grey
            // hairline it read as an unrelated card resting against the row.
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(MacSelectionStyle.borderColor(isSelected: true),
                        lineWidth: MacSelectionStyle.selectedWidth))
            .shadow(color: .black.opacity(0.18), radius: 16, x: side == .trailing ? -2 : 2, y: 4)
            // The arrow is drawn ON TOP of the card, overlapping its edge by a point, so its base
            // MERGES into the card surface. Previously it sat in its own column beside the card:
            // the card's border stroke ran across the arrow's base (it looked cut off) and the
            // arrow carried its own drop shadow, which tinted it darker than the card.
            // Same fill as the card + no shadow of its own = it blends.
            .overlay(alignment: side == .trailing ? .topLeading : .topTrailing) {
                GeometryReader { g in
                    // Convert the row's content-space midY through the CARD's measured origin.
                    // A hardcoded offset was wrong because the panel is centered, so its origin
                    // moves with the panel's height — the arrow aimed at the wrong task (69fd1f19).
                    // Global on BOTH sides (row + panel): a named-space mismatch offset the arrow
                    // by about one row height, so it pointed one row below the tapped one.
                    let originY = g.frame(in: .global).minY
                    // Beside a board card the arrow aims at the card's middle and keeps off the
                    // corners by astrid-core's rule (AITD-679); no card on screen, no arrow.
                    if !besideBoard || selectedCardFrame != nil {
                    ZStack {
                        // The fill erases the card's border along the 1pt overlap, which is what
                        // lets the notch's mouth open into the card face — and is why the outline
                        // has to be redrawn around the two outer edges, or the selection border
                        // would simply stop for the arrow's height (AITD-302).
                        MacPopoverArrow().fill(MacDetailChrome.background)
                        MacPopoverArrowEdges()
                            .stroke(MacSelectionStyle.borderColor(isSelected: true),
                                    lineWidth: MacSelectionStyle.selectedWidth)
                    }
                        .frame(width: MacLayout.detailArrowWidth, height: 24)
                        // The notch points left at a row; mirrored, it points right at a card.
                        .scaleEffect(x: side == .trailing ? 1 : -1, y: 1)
                        .position(x: side == .trailing
                                    ? -MacLayout.detailArrowWidth / 2 + MacLayout.arrowOverlap
                                    : g.size.width + MacLayout.detailArrowWidth / 2 - MacLayout.arrowOverlap,
                                  y: besideBoard
                                    ? BoardCardCallout.arrowY(card: selectedCardFrame, panel: g.frame(in: .global))
                                    : MacSelectionModel.arrowLocalY(rowMidY: selectedRowMidY,
                                                                    panelOriginY: originY,
                                                                    panelHeight: g.size.height))
                        .animation(MacMotion.fast, value: besideBoard ? selectedCardFrame?.midY : selectedRowMidY)
                    }
                }
            }
            .padding(side == .trailing ? .leading : .trailing,
                     besideCard ? Self.arrowRoom : MacLayout.detailArrowWidth + MacLayout.detailPanelMargin)
            // One margin, always: the panel WIDTH grows with the chat column instead (AITD-334), so
            // the card reaches the trailing margin while its leading edge — and the arrow's
            // AITD-302 clearance from the row edge — stays exactly where it was.
            .padding(side == .trailing ? .trailing : .leading,
                     besideCard ? 0 : MacLayout.detailPopoutTrailingPadding)
        .padding(.vertical, besideCard ? 0 : 14)
        // FULL height, not centred-and-intrinsic: a shorter card cannot reach rows outside its own
        // vertical extent, so the arrow clamped to the card's edge and pointed at the wrong row.
        .frame(maxHeight: .infinity)
    }
}
#endif
