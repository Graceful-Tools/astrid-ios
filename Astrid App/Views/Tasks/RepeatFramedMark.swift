//  RepeatFramedMark.swift
//  Draws a photo or the "U" mark bordered by the repeat arrows (AITD-602), on iOS and the Mac (AITD-606). When it applies, and how
//  big, are `TaskLeadingControl.showsRepeatFrame` and `RepeatFrameGeometry` — never decided here.

import SwiftUI

struct RepeatFramedMark<Content: View>: View {
    let priority: Task.Priority
    /// The leading control this mark stands in for — 34pt on iOS, the Mac's own checkbox size
    /// there. The arrows and the photo scale from it (AITD-606), so every surface frames at the square's own size (AITD-612).
    var controlSize: CGFloat = RepeatFrameGeometry.footprint
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            // The whole square, clipped as the non-repeating photo is — so a repeating task's face
            // is the same size as every other face in the column (AITD-612 reopened).
            .frame(width: innerSize, height: innerSize)
            .clipShape(RoundedRectangle(cornerRadius: corner))
            // The arrows ARE the border, where the plain mark has its priority outline.
            .overlay(RepeatArrowsBorder(cornerRadius: corner).fill(priorityColor).accessibilityHidden(true))
            .frame(width: controlSize, height: controlSize)
            .accessibilityIdentifier("task.leading.repeatFrame")
    }

    private var innerSize: CGFloat { RepeatFrameGeometry.innerSize(control: controlSize) }
    private var corner: CGFloat { RepeatFrameGeometry.cornerRadius(control: controlSize) }

    private var priorityColor: Color {
        switch priority {
        case .none: return Theme.priorityNone
        case .low: return Theme.priorityLow
        case .medium: return Theme.priorityMedium
        case .high: return Theme.priorityHigh
        }
    }
}

/// The repeat arrows drawn round a rounded square: two brackets, each ending in an arrowhead
/// halfway along the top or bottom edge, rotationally symmetric like `check_box_repeat_<p>`.
/// Drawn rather than the bitmap so they can follow the edge of a full-size photo.
struct RepeatArrowsBorder: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height)
        let r = min(cornerRadius, s / 2)
        let length = s * RepeatFrameGeometry.headLength
        let halfWidth = s * RepeatFrameGeometry.headHalfWidth

        // The left bracket: from the bottom edge, round the left side, along the top to the middle.
        var bracket = Path()
        bracket.move(to: CGPoint(x: r, y: s))
        bracket.addArc(tangent1End: CGPoint(x: 0, y: s), tangent2End: CGPoint(x: 0, y: s - r), radius: r)
        bracket.addLine(to: CGPoint(x: 0, y: r))
        bracket.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: r, y: 0), radius: r)
        bracket.addLine(to: CGPoint(x: s / 2, y: 0))

        var half = bracket.strokedPath(StrokeStyle(lineWidth: RepeatFrameGeometry.lineWidth, lineCap: .butt))
        // Its arrowhead, pointing right along the top edge.
        half.move(to: CGPoint(x: s / 2, y: -halfWidth))
        half.addLine(to: CGPoint(x: s / 2 + length, y: 0))
        half.addLine(to: CGPoint(x: s / 2, y: halfWidth))
        half.closeSubpath()

        // The right bracket is the same half turned half a turn about the centre.
        let turn = CGAffineTransform(translationX: s, y: s).rotated(by: .pi)
        var path = half
        path.addPath(half, transform: turn)
        let origin = CGPoint(x: rect.midX - s / 2, y: rect.midY - s / 2)
        return path.offsetBy(dx: origin.x, dy: origin.y)
    }
}
