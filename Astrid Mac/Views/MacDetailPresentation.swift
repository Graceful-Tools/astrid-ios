//  MacDetailPresentation.swift
//  Which task detail is on screen, and how (Task 9a98f996).
//
//  This used to be a condition inside `MacRootView`'s overlay: `contentMode != .board, …`. That
//  suppressed the detail on a board ENTIRELY, which quietly made the board card's existing
//  "Open full detail…" link do nothing — it selects the task, and nothing appears.
//
//  The suppression is right for the pop-out and wrong for full screen. The pop-out floats at the
//  trailing edge and would sit over the columns; full screen takes the whole content area, so a
//  board has no quarrel with it. Splitting those two cases is the fix, and it lives here rather
//  than in a view so it can be asserted — a control going dead is exactly the kind of failure a
//  buried condition hides.

#if os(macOS)
import SwiftUI

enum MacDetailPresentation {

    enum Style: Equatable {
        /// Nothing to show.
        case none
        /// The floating panel at the trailing edge, with its arrow back at the selected row.
        case popout
        /// The panel fills the content area — the description gets the whole window.
        case fullScreen
    }

    /// - Parameter selectionCount: a detail describes ONE task; a multi-selection has no subject.
    static func style(mode: MacRootView.ContentMode,
                      selectionCount: Int,
                      fullScreen: Bool) -> Style {
        guard selectionCount == 1 else { return .none }
        switch mode {
        case .list:
            return fullScreen ? .fullScreen : .popout
        case .board:
            // The card expands INLINE on a board (web parity) — that is the board's own affordance,
            // so the pop-out stays suppressed. Full screen is a different question and is allowed.
            return fullScreen ? .fullScreen : .none
        case .chat:
            // Chat replaces the content area; there is nothing to overlay onto.
            return .none
        }
    }

    /// Full screen centres in the content area it fills; the pop-out hugs the trailing edge.
    static func alignment(for style: Style) -> Alignment {
        style == .fullScreen ? .center : .trailing
    }

    // MARK: - The affordance, shared by both places that offer it

    /// The glyph, so the board card and the detail header cannot drift into two different icons.
    static func fullScreenSymbol(isFullScreen: Bool) -> String {
        isFullScreen ? "arrow.down.right.and.arrow.up.left"
                     : "arrow.up.left.and.arrow.down.right"
    }

    static func fullScreenTooltipKey(isFullScreen: Bool) -> String {
        isFullScreen ? "board.exit_full_screen" : "board.full_screen"
    }
}
#endif
