//  MacDetailPopover.swift
//  Astrid for Mac — floating task-detail pop-out (Task 2766d9a4). Shows only for a single selected
//  task, so an unselected list uses the full width (no permanent empty detail column).

#if os(macOS)
import SwiftUI

enum MacDetailPopover {
    /// The pop-out is shown only when exactly one task is selected.
    static func isVisible(selectionCount: Int) -> Bool { selectionCount == 1 }
}

/// A small left-pointing arrow/notch on the pop-out's leading edge, pointing back at the task list
/// (like Astrid Web's detail panel).
struct MacPopoverArrow: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
#endif
