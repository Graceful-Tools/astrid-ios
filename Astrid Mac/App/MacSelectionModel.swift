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

    /// Arrow vertical center for the pop-out, clamped inside the panel so it always touches it.
    static func arrowY(rowMidY: CGFloat, panelHeight: CGFloat, inset: CGFloat = 28) -> CGFloat {
        guard panelHeight > inset * 2 else { return panelHeight / 2 }
        return min(max(rowMidY, inset), panelHeight - inset)
    }

    /// Arrow center in the ARROW COLUMN'S OWN coordinates, given the row's midY measured in the
    /// content coordinate space.
    ///
    /// The pop-out is vertically padded AND centered (`maxHeight: .infinity, alignment: .center`),
    /// so its origin inside the content area shifts with the panel's height — it is NOT a fixed
    /// inset. Subtracting a hardcoded constant therefore aimed the arrow at whatever row happened
    /// to sit at that offset: it pointed at the wrong task (task 69fd1f19). Converting through the
    /// panel's measured origin is self-correcting for any padding, centering or panel size.
    static func arrowLocalY(rowMidY: CGFloat?, panelOriginY: CGFloat, panelHeight: CGFloat,
                            inset: CGFloat = 28) -> CGFloat {
        // No measured row (e.g. the selected row scrolled out of view): centre the arrow.
        guard let rowMidY else { return panelHeight / 2 }
        return arrowY(rowMidY: rowMidY - panelOriginY, panelHeight: panelHeight, inset: inset)
    }

    /// An intentional scroll (offset moved beyond the threshold) closes the detail pop-out.
    static func scrollShouldClose(delta: CGFloat, threshold: CGFloat = 24) -> Bool {
        abs(delta) > threshold
    }
}
#endif
