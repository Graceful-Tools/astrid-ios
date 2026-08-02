import SwiftUI

/// A symbol with a line through it, for a field that is deliberately OFF (Task 42013da7).
///
/// A crossed-out clock says "no time" in the space a symbol takes; the words "Add time" needed a
/// chip wide enough to truncate to "Add…", which told the reader nothing at all.
///
/// Hand-drawn rather than an SF Symbol `.slash` variant: `clock.badge.xmark` exists but `repeat`
/// has no slashed counterpart, and two fields sitting in the same row must not be drawn in two
/// different idioms.
struct SlashedSymbol: View {
    let systemName: String
    var size: CGFloat = 14
    var color: Color = .secondary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size))
            .foregroundColor(color)
            .overlay {
                // Slightly over-long so the stroke visibly crosses the glyph's corners.
                Capsule()
                    .fill(color)
                    .frame(width: size * 1.35, height: max(1, size * 0.09))
                    .rotationEffect(.degrees(-45))
            }
            .accessibilityHidden(true)
    }
}
