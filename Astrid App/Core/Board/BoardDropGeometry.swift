import CoreGraphics
import Foundation

/// Geometry for board drag-and-drop: where a released card lands, where the
/// drop indicator is drawn, and when a drag near an edge scrolls the board.
///
/// All of it is pure and lives outside the view so it can be tested — the
/// bugs these functions exist to fix (`BoardDropPlacementTests`,
/// `BoardDragEdgeAutoAdvanceTests`) were both invisible to the compiler and
/// only reproducible by hand on a device.

// MARK: - Where a released card lands

/// One card's vertical extent inside a board column, measured in the column's
/// own coordinate space. Reported by the cards themselves as they lay out, so
/// the numbers already account for scrolling.
struct BoardCardSlot: Equatable {
    let taskId: String
    let minY: CGFloat
    let maxY: CGFloat

    var midY: CGFloat { (minY + maxY) / 2 }
}

/// The insertion index for a card released at `dropY`.
///
/// Every y resolves to a slot — that is the whole point. The column used to
/// scatter one drop target per card plus a column-wide fallback that always
/// answered 0, which turned the gaps between cards, the header and the
/// add-task footer into dead zones that silently sent the card to the top.
///
/// A card's top half inserts above it and its bottom half below it, so the
/// boundary between "before card N" and "after card N" is that card's
/// midpoint. The gaps fall out of the same rule for free.
///
/// The result is always a valid `Array.insert(_:at:)` index for a column of
/// `slots.count` cards.
func boardDropInsertionIndex(dropY: CGFloat, slots: [BoardCardSlot]) -> Int {
    for (index, slot) in slots.enumerated() where dropY < slot.midY {
        return index
    }
    return slots.count
}

/// Where to draw the drop indicator for a given insertion index, in the same
/// coordinate space as `slots`.
///
/// The indicator is positioned from the existing card frames and drawn as an
/// overlay. It used to be a sibling view inside the card stack, which meant
/// showing it pushed the hovered card down and out from under the pointer —
/// ending the hover, hiding the indicator, and moving the card back. That
/// oscillation is the flicker the bug report calls "finiky".
func boardDropIndicatorOffset(forInsertionIndex index: Int, slots: [BoardCardSlot]) -> CGFloat {
    guard let first = slots.first, let last = slots.last else { return 0 }
    if index <= 0 { return first.minY }
    if index >= slots.count { return last.maxY }
    // Between two cards: centre the indicator in the gap.
    return (slots[index - 1].maxY + slots[index].minY) / 2
}

// MARK: - Dragging a card to an edge scrolls the board

/// Which side of the board a dragged card is hovering over.
enum BoardAutoAdvanceEdge {
    case leading
    case trailing
}

/// How long a dragged card must sit in an edge zone before the board moves,
/// and the interval between subsequent moves while it stays there.
///
/// Short enough to read as a response to the drag (the report is "it doesn't
/// respond quickly"), long enough that a card merely crossing the edge on its
/// way to a nearer column doesn't launch the board.
let boardAutoAdvanceDwell: TimeInterval = 0.3

/// Width of the leading/trailing hot zones. A proportion of the board width so
/// it scales, floored at a touch target so it stays hittable mid-drag, and
/// capped so a wide iPad board doesn't turn a quarter of the screen into a
/// scroll trigger.
func boardAutoAdvanceEdgeWidth(containerWidth: CGFloat) -> CGFloat {
    let proportional = max(0, containerWidth) * 0.18
    return min(96, max(44, proportional))
}

/// The edge zone containing `dragX`, or nil when the drag is over the cards.
/// Dragging across the middle of a column must never scroll the board out from
/// under the card being placed.
func boardAutoAdvanceEdge(dragX: CGFloat, containerWidth: CGFloat) -> BoardAutoAdvanceEdge? {
    let zone = boardAutoAdvanceEdgeWidth(containerWidth: containerWidth)
    if dragX <= zone { return .leading }
    if dragX >= containerWidth - zone { return .trailing }
    return nil
}

/// The column to scroll to, or nil when the board is already at that end.
///
/// One column per dwell — a held card walks the board rather than flinging it.
/// `currentIndex` comes from a scroll-position binding that can lag or hold a
/// stale id, so it is clamped rather than trusted.
func boardAutoAdvanceTarget(currentIndex: Int,
                            edge: BoardAutoAdvanceEdge,
                            columnCount: Int) -> Int? {
    guard columnCount > 1 else { return nil }
    let clamped = max(0, min(currentIndex, columnCount - 1))
    let target = edge == .leading ? clamped - 1 : clamped + 1
    guard target >= 0, target < columnCount else { return nil }
    return target
}
