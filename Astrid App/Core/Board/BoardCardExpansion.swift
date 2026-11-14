//  BoardCardExpansion.swift
//  Which board card is open inline (AITD-628). Tapping a card on the iOS board opens its details
//  in place, where the card face was (AITD-661), as web and the Mac board do; it used to leave
//  the board for the full-screen push (iPhone) or the side panel (iPad).
//
//  The rules are here, not in the view, so they can be pinned and so the iOS board and the Mac
//  board (`MacBoardExpand`) cannot mean different things by the same tap.

import CoreGraphics

enum BoardCardExpansion {

    /// Tapping the open card closes it; tapping any other card opens that one instead. One card is
    /// open at a time across the whole board.
    static func toggle(current: String?, tapped: String) -> String? {
        current == tapped ? nil : tapped
    }

    /// The open card, unless it has left the board — completed out of the Done window, deleted,
    /// moved to another list. An editor left open on a card that is gone edits nothing.
    static func retained(current: String?, visibleTaskIds: Set<String>) -> String? {
        guard let current, visibleTaskIds.contains(current) else { return nil }
        return current
    }

    /// Does this card draw its face? Not while it is the open card (AITD-661, "Hide unexpanded
    /// card on open"): the details open in its place rather than under it, so the open card no
    /// longer shows its title twice, once on the face and again in the details header. The Mac
    /// board's card turns into its editor the same way.
    static func showsCardFace(taskId: String, expandedTaskId: String?) -> Bool {
        expandedTaskId != taskId
    }

    /// How tall the inline details are. The details scroll on their own, so they get a bounded
    /// share of the board — enough to read and edit, with the column's other cards and its edge
    /// still on screen to tap — and never less than a usable minimum.
    static func inlineDetailHeight(boardHeight: CGFloat) -> CGFloat {
        max(minimumInlineDetailHeight, boardHeight * inlineDetailShareOfBoard)
    }

    /// Does a card tap open the details inline? Only where the board has room for them (AITD-642,
    /// "On iPhone open task details old way on board"): on iPhone a column is the width of the
    /// screen, so the inline details are a cramped scroll inside a scroll, and a tap opens the
    /// full-screen push as it did before AITD-628. iPad keeps them inline.
    static func cardTapOpensInline(splitLayout: Bool) -> Bool {
        splitLayout
    }

    /// Where the inline details' full-screen button takes the task (AITD-636).
    enum FullDetailsRoute: Equatable {
        /// iPad's detail panel, already in its full-screen state.
        case panel(fullScreen: Bool)
        /// The full-screen push — iPhone, or an iPad set to push.
        case push
    }

    /// Jon: "full screen doesn't go directly to full screen on iPad. It should." On iPad the button
    /// used to open the side panel, which needed a second tap to go full screen. It opens the panel
    /// full screen now, and always opens it: unlike a card tap, the button never toggles it closed.
    static func fullDetailsRoute(splitLayout: Bool, forcePush: Bool) -> FullDetailsRoute {
        splitLayout && !forcePush ? .panel(fullScreen: true) : .push
    }

    static let minimumInlineDetailHeight: CGFloat = 320
    static let inlineDetailShareOfBoard: CGFloat = 0.72
}
