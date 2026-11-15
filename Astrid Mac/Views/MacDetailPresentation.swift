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
            // A card opens the pop-out, as a list row does, docked on the side of the card with
            // more room (AITD-679). It used to expand the card inline and suppress the pop-out.
            return fullScreen ? .fullScreen : .popout
        case .chat:
            // Chat replaces the content area; there is nothing to overlay onto.
            return .none
        }
    }

    /// Full screen centres in the content area it fills; the pop-out hugs the edge it docks on —
    /// trailing beside a list, either edge beside a board card (AITD-679).
    static func alignment(for style: Style, side: BoardCardCallout.Side = .trailing) -> Alignment {
        if style == .fullScreen { return .center }
        return side == .leading ? .leading : .trailing
    }

    /// Full screen belongs to the task it was opened for (AITD-464). The flag is persisted, and
    /// closing the detail — the close button, Escape, switching lists — only clears the
    /// selection, so without this every task opened afterwards came up full screen as well.
    static func fullScreen(current: Bool, selectionCount: Int) -> Bool {
        selectionCount == 0 ? false : current
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

/// What a selection change means outside the content area: menu commands read the selection
/// from the app model, and closing the detail ends its full screen (AITD-464). Lives here rather
/// than in `MacRootView` so the root stays under its size ceiling.
struct MacDetailSelectionSync: ViewModifier {
    let selection: Set<String>
    let appModel: MacAppModel
    @AppStorage("macDetailFullScreen") private var detailFullScreen = false

    func body(content: Content) -> some View {
        content.onChange(of: selection, initial: true) { _, ids in
            appModel.selectedTaskIds = ids
            detailFullScreen = MacDetailPresentation.fullScreen(current: detailFullScreen,
                                                                selectionCount: ids.count)
        }
    }
}
#endif
