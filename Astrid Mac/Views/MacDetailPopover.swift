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
            // Keep AppKit-backed controls at their natural scale. Scaling the whole hierarchy
            // makes SwiftUI's PlatformTextFieldAdaptor generate invalid min/max constraints.
            .clipShape(MacDetailRevealMask(progress: progress, anchorY: anchorY))
            // Dissolve on the way out instead of shrinking at full strength (65b81ff8).
            .opacity(MacDetailReveal.fade(progress: progress))
    }

    /// Opacity for a given unfold progress, BELOW linear on purpose: the panel has to be mostly
    /// gone while it is still visibly collapsing, or it reads as a solid panel being squashed
    /// rather than dissolving. A first attempt at 1.8× linear left it 54% opaque at a third
    /// closed, which the test rejected — quadratic puts it at 9% there.
    static func fade(progress: CGFloat) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return p * p
    }

    /// The collapse converges on the panel's LEADING edge — the arrow, which sits at the task
    /// row's right border. Any other anchor sweeps the panel leftward across the rows as it
    /// shrinks, which is the motion this task is about: a centre anchor would drag it half a panel
    /// width to the left of where it started.
    static let collapseAnchorX: CGFloat = 0

    /// The leftmost point the panel occupies at a given progress, measured from its resting
    /// leading edge. Zero for every progress while the anchor is the leading edge; it is the
    /// property that must hold, so it is asserted rather than assumed.
    static func leftmostOffset(progress: CGFloat, panelWidth: CGFloat) -> CGFloat {
        let p = min(max(progress, 0), 1)
        return -collapseAnchorX * panelWidth * (1 - p)
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

/// Reveals the panel from its arrow without transforming AppKit-backed child controls.
struct MacDetailRevealMask: Shape {
    var progress: CGFloat
    var anchorY: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, anchorY) }
        set {
            progress = newValue.first
            anchorY = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path(Self.visibleRect(in: rect, progress: progress, anchorY: anchorY))
    }

    static func visibleRect(in rect: CGRect, progress: CGFloat, anchorY: CGFloat) -> CGRect {
        let clampedProgress = min(max(progress, 0), 1)
        let clampedAnchor = min(max(anchorY, 0), 1)
        let width = rect.width * clampedProgress
        let height = rect.height * MacDetailReveal.verticalScale(progress: clampedProgress)
        let fixedY = rect.minY + rect.height * clampedAnchor
        return CGRect(x: rect.minX,
                      y: fixedY - height * clampedAnchor,
                      width: width,
                      height: height)
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

/// The arrow's two OUTER edges as an OPEN path — the outline that carries the card's selection
/// border around the notch (AITD-302).
///
/// Stroking `MacPopoverArrow` itself would draw its base as well: a vertical accent line across
/// the card's face, exactly where the notch is supposed to merge into it. The fill and this
/// outline are the same geometry, so they cannot disagree about where the arrow is.
struct MacPopoverArrowEdges: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return p
    }
}
#endif
