//  TaskBoardStatusPill.swift
//  The board-status pill on a list row (AITD-613) — iOS `TaskRowView` and Mac `MacTaskRow`.
//
//  Jon: "red pills for inbox, yellow for waiting, green for ready, another green for doing, and
//  a blue for done." The colours are the theme's semantic tokens, so they follow light/dark/ocean
//  with everything else: error, warning, success, info (a cyan-green) and the accent blue.
//  A board's own custom column is grey. Never drawn on a board card.

import SwiftUI

struct TaskBoardStatusPill: View {
    /// The font comes from the row (`.font` on iOS, `.macFont` on Mac), so the pill matches the
    /// date and list chips beside it.
    let status: TaskBoardStatus

    static func tint(for kind: TaskBoardStatus.Kind) -> Color {
        switch kind {
        case .inbox: return Theme.error
        case .waiting: return Theme.warning
        case .ready: return Theme.success
        case .doing: return Theme.info
        case .done: return Theme.accent
        case .custom: return Theme.textMuted
        }
    }

    var body: some View {
        AstridPill(text: status.name, tint: Self.tint(for: status.kind))
            .accessibilityIdentifier("taskRow.boardStatus.\(status.kind.rawValue)")
    }
}
