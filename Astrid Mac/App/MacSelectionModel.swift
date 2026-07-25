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

    /// An intentional scroll (offset moved beyond the threshold) closes the detail pop-out.
    static func scrollShouldClose(delta: CGFloat, threshold: CGFloat = 24) -> Bool {
        abs(delta) > threshold
    }
}
#endif
