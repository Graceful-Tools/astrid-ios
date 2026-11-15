//  MacSelectionModel.swift
//  Astrid for Mac — pure selection/tap/arrow/scroll rules (Tasks 0f695ef2 + a1cb6083).
//
//  Selection is managed manually (no List(selection:) binding) so the native macOS accent
//  highlight never paints the whole row — the card stays white and only the border shows
//  selection. Manual management also gives us web-style behaviors: tapping the selected task
//  again closes the detail, and an intentional scroll dismisses it.

#if os(macOS)
import Foundation

enum MacSelectionModel {
    /// New selection after a row tap. Plain click: select; clicking the single selected row
    /// again DESELECTS (closes the pop-out). ⌘-click toggles membership (multi-select).
    static func tap(current: Set<String>, tapped: String, commandKey: Bool) -> Set<String> {
        if commandKey {
            var next = current
            if next.contains(tapped) { next.remove(tapped) } else { next.insert(tapped) }
            return next
        }
        return current == [tapped] ? [] : [tapped]
    }

    /// Arrow center in the ARROW COLUMN'S OWN coordinates, given the row's midY measured in the
    /// content coordinate space.
    ///
    /// The pop-out is vertically padded AND centered, so its origin inside the content area shifts
    /// with the panel's height — it is NOT a fixed inset. Subtracting a hardcoded constant aimed
    /// the arrow at whatever row happened to sit at that offset (task 69fd1f19). Converting through
    /// the panel's measured origin is self-correcting for any padding, centering or panel size.
    /// Clamped off the corners by astrid-core's callout rule — one rule with the iPad panel's
    /// arrow and every board card's (AITD-607, AITD-678): `DetailPanelChrome` owns the call.
    static func arrowLocalY(rowMidY: CGFloat?, panelOriginY: CGFloat, panelHeight: CGFloat) -> CGFloat {
        DetailPanelChrome.arrowLocalY(rowMidY: rowMidY, panelOriginY: panelOriginY,
                                      panelHeight: panelHeight)
    }

    /// An intentional scroll (offset moved beyond the threshold) closes the detail pop-out.
    static func scrollShouldClose(delta: CGFloat, threshold: CGFloat = 24) -> Bool {
        abs(delta) > threshold
    }
}
#endif
