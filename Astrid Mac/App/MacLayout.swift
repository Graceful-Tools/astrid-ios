//  MacLayout.swift
//  Astrid for Mac — responsive 2/3-column rule (Task 23c98550), mirroring the web's
//  lib/layout-detection.ts: a ≥1100px window is 3-column with chat always visible as the right
//  column. The Mac content area sits next to a ~240pt sidebar, so the equivalent CONTENT width
//  threshold is 1100 − 240 = 860pt. Below that, chat stays a content mode (2-column).

#if os(macOS)
import Foundation

enum MacLayout {
    /// Web's 3-column threshold, measured on the WINDOW (not the content area).
    ///
    /// It used to be measured on the content area (1100 − 240 sidebar = 860), which meant opening
    /// the sidebar shrank the content below the threshold and the chat column vanished — toggling
    /// the left rail should never close the right one. The window width does not change when the
    /// sidebar opens, so the decision is now stable.
    static let chatColumnWindowThreshold: CGFloat = 1_100

    // MARK: - Detail pop-out geometry
    //
    // The pop-out floats over the CHAT column, never over the task rows, and the task list never
    // gives up width for it — rows must not resize when a task is selected. That is only possible
    // if the chat column is permanently at least as wide as the pop-out plus its margins, which is
    // how chatColumnWidth is derived below rather than being a magic number.
    static let detailPanelWidth: CGFloat = 380
    static let detailArrowWidth: CGFloat = 12
    /// Breathing room on each side of the floating panel: the arrow needs room on the leading
    /// edge, and the panel needs a matching margin on the trailing edge.
    static let detailPanelMargin: CGFloat = 14

    /// Total width the floating pop-out occupies, margins included.
    static var detailPopoutWidth: CGFloat {
        detailPanelWidth + detailArrowWidth + detailPanelMargin * 2
    }

    /// Space between a row card's edge and the column edge: the card's own 8pt padding plus
    /// `.listStyle(.inset)`'s row inset. MEASURED from a rendered capture (the inset is ~16pt, not
    /// the ~10 first assumed), because it decides two things that must line up with the rows: the
    /// quick-add card's margins and where the pop-out's arrow tip lands.
    static let rowTrailingGap: CGFloat = 24
    /// The 1pt divider between the task column and the chat column.
    static let columnDividerWidth: CGFloat = 1
    /// The arrow overlaps the card by 1pt so its base merges into the card surface.
    static let arrowOverlap: CGFloat = 1

    /// Chat column width, derived so the ARROW TIP lands exactly on the row card's trailing edge.
    ///
    /// With the pop-out right-aligned in the content area:
    ///   card right   = contentRight − margin
    ///   card left    = contentRight − margin − panel
    ///   arrow tip    = card left − (arrow − overlap)
    ///   row right    = contentRight − chatWidth − divider − rowTrailingGap
    /// Setting arrow tip == row right and solving for chatWidth gives the expression below, so the
    /// tip touches the row instead of floating short of it.
    static var chatColumnWidth: CGFloat {
        detailPanelMargin + detailPanelWidth + (detailArrowWidth - arrowOverlap)
            - rowTrailingGap - columnDividerWidth
    }

    /// Show the persistent chat column? Wide WINDOW + a selection that has a channel, and NOT in
    /// board mode — a board needs the full horizontal width for its columns, so the two are
    /// mutually exclusive (task f1430338).
    static func showsChatColumn(windowWidth: CGFloat, isRealList: Bool, isBoard: Bool = false) -> Bool {
        isRealList && !isBoard && windowWidth >= chatColumnWindowThreshold
    }
}
#endif
