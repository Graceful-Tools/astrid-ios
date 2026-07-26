//  MacDetailPopover.swift
//  Astrid for Mac — floating task-detail pop-out (Task 2766d9a4). Shows only for a single selected
//  task, so an unselected list uses the full width (no permanent empty detail column).

#if os(macOS)
import SwiftUI

enum MacDetailPopover {
    /// The pop-out is shown only when exactly one task is selected.
    static func isVisible(selectionCount: Int) -> Bool { selectionCount == 1 }
}

/// The pop-out's reveal: the panel unfolds horizontally OUT OF the arrow, and folds back into it
/// the same way. Not a fade — the geometry itself carries the motion, so the panel visibly comes
/// from the task it points at.
struct MacDetailReveal: ViewModifier {
    /// 0 = collapsed onto the arrow, 1 = the full panel.
    let progress: CGFloat
    /// Where the arrow sits vertically within the panel, 0...1 — the fold origin.
    let anchorY: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(x: max(progress, 0.001),
                         // Collapsed, the panel is about as tall as the arrow; it grows to full
                         // height as it unfolds.
                         y: MacDetailReveal.verticalScale(progress: progress),
                         anchor: UnitPoint(x: 0, y: anchorY))
    }

    /// Vertical growth lags slightly behind the horizontal unfold, which is what makes it read as
    /// the ARROW widening rather than a box being stretched.
    static func verticalScale(progress: CGFloat) -> CGFloat {
        let collapsed: CGFloat = 0.08          // ≈ the arrow's height against a tall panel
        return collapsed + (1 - collapsed) * min(max(progress, 0), 1)
    }

    /// The arrow's vertical position as a 0...1 anchor inside the content area. Falls back to the
    /// middle when the selected row has not been measured (e.g. scrolled out of view).
    static func anchor(rowMidY: CGFloat?, contentMinY: CGFloat, contentHeight: CGFloat) -> CGFloat {
        guard let rowMidY, contentHeight > 0 else { return 0.5 }
        return min(max((rowMidY - contentMinY) / contentHeight, 0), 1)
    }
}

/// The selected row reports its vertical center (in the content coordinate space) so the pop-out
/// arrow can point at it (a1cb6083). First non-nil wins.
struct MacSelectedRowMidYKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
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
