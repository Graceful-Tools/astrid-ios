//  ChipBackground.swift
//  The compact chip behind task-detail values: the When row (`InlineDatePicker(compact: true)`),
//  the occurrences and blockers rows (AITD-491), and the estimate card on iOS and Mac (ADEV-329).

import SwiftUI

extension View {
    /// The When row's compact chip, so every row that draws one matches.
    func chipBackground(_ palette: AstridTokens.Palette) -> some View {
        padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing4)
            .background(palette.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
    }
}
