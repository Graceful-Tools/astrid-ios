//  RepeatFramedMark.swift
//  Draws a photo or the "U" mark inside the repeat arrows (AITD-602). When it applies, and how
//  big, are `TaskLeadingControl.showsRepeatFrame` and `RepeatFrameGeometry` — never decided here.

import SwiftUI

struct RepeatFramedMark<Content: View>: View {
    let priority: Task.Priority
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Image(RepeatFrameGeometry.assetName(priority: priority))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: RepeatFrameGeometry.frameSize, height: RepeatFrameGeometry.frameSize)
                .accessibilityHidden(true)
            content()
                .frame(width: RepeatFrameGeometry.innerSize, height: RepeatFrameGeometry.innerSize)
                // Round inside the loop, as on web; sized first so the clip is the 24pt circle.
                .clipShape(Circle())
        }
        // Lays out as the 34pt square it replaces; the arrows overhang it.
        .frame(width: RepeatFrameGeometry.footprint, height: RepeatFrameGeometry.footprint)
        .accessibilityIdentifier("task.leading.repeatFrame")
    }
}
