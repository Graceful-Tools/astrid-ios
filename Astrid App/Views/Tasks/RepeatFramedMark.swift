//  RepeatFramedMark.swift
//  Draws a photo or the "U" mark inside the repeat arrows (AITD-602), on iOS and the Mac (AITD-606). When it applies, and how
//  big, are `TaskLeadingControl.showsRepeatFrame` and `RepeatFrameGeometry` — never decided here.

import SwiftUI

struct RepeatFramedMark<Content: View>: View {
    let priority: Task.Priority
    /// The leading control this mark stands in for — 34pt on iOS, the Mac's own checkbox size
    /// there. The arrows and the photo scale from it (AITD-606), so every surface frames at the square's own size (AITD-612).
    var controlSize: CGFloat = RepeatFrameGeometry.footprint
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Image(RepeatFrameGeometry.assetName(priority: priority))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: frameSize, height: frameSize)
                .accessibilityHidden(true)
            content()
                .frame(width: innerSize, height: innerSize)
                // Round inside the loop, as on web; sized first so the clip is the inner circle.
                .clipShape(Circle())
        }
        // Lays out as the square it replaces, and the arrows are that size too (AITD-612).
        .frame(width: controlSize, height: controlSize)
        .accessibilityIdentifier("task.leading.repeatFrame")
    }

    private var frameSize: CGFloat { RepeatFrameGeometry.frameSize(control: controlSize) }
    private var innerSize: CGFloat { RepeatFrameGeometry.innerSize(control: controlSize) }
}
