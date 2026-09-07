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

    /// Clearance between the selected row's trailing edge and the arrow's TIP (AITD-302).
    ///
    /// The tip used to be derived to land exactly ON that edge. A filled notch meeting a 1.5pt
    /// accent outline does not read as "meeting" — it reads as overlapping, which is how it was
    /// reported. The points come out of the row column (chatColumnWidth below) rather than out of
    /// the arrow: shifting the arrow toward the card would have shortened the notch to a stub,
    /// since the card's leading edge is fixed by the panel's width and margin.
    static let detailArrowRowGap: CGFloat = 6

    /// Height of the opaque strip painted across the top of the sidebar (task 46f66cb8).
    ///
    /// The sidebar sits under a transparent titlebar, so without this the list scrolls up behind
    /// the sidebar toggle and the window's red/yellow/green buttons. 28pt clears the standard
    /// titlebar control row; it is a strip of colour rather than a layout inset, so being a
    /// couple of points generous costs nothing and being short is immediately visible.
    static let sidebarTitlebarInset: CGFloat = 28

    /// Chat column width, derived so the ARROW TIP clears the row card's trailing edge by
    /// `detailArrowRowGap`.
    ///
    /// With the pop-out right-aligned in the content area:
    ///   card right   = contentRight − margin
    ///   card left    = contentRight − margin − panel
    ///   arrow tip    = card left − (arrow − overlap)
    ///   row right    = contentRight − chatWidth − divider − rowTrailingGap
    /// Setting arrow tip == row right + gap and solving for chatWidth gives the expression below.
    /// The gap term is why the rows give up those points rather than the arrow: the card's leading
    /// edge is pinned by the panel width and margin, so taking the clearance out of the arrow
    /// would shorten the notch instead of moving it (AITD-302).
    static var chatColumnWidth: CGFloat {
        detailPanelMargin + detailPanelWidth + (detailArrowWidth - arrowOverlap)
            - rowTrailingGap - columnDividerWidth + detailArrowRowGap
    }

    // MARK: - Resizable columns (AITD-329)
    //
    // Both side columns can be dragged. The widths that used to be fixed become the FLOOR, per
    // Jon: "current column width a fine minimum". Nothing gets narrower than it is today; the
    // window just stops being the only thing that decides how the space is split.

    /// Sidebar floor. Was 200 while the ideal was 240, so a drag could take the list rail
    /// noticeably below the width it ships at; the shipped width is the floor now.
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarIdealWidth: CGFloat = 240
    /// A rail past this stops being a rail. It is a cap on the DRAG, not on the window.
    static let sidebarMaxWidth: CGFloat = 420

    /// What the middle column keeps no matter how wide the chat column is dragged. Roughly a task
    /// title plus its due date and assignee — below this the rows stop being readable, which is a
    /// worse outcome than refusing the drag.
    static let listColumnMinWidth: CGFloat = 320

    /// The chat column's floor: the derived width above, which is the one that makes the pop-out's
    /// arrow meet the rows.
    static var chatColumnMinWidth: CGFloat { chatColumnWidth }

    /// The chat column width actually used, given what the user dragged and the space available.
    ///
    /// The upper bound is whatever leaves `listColumnMinWidth` for the rows — and when the content
    /// area is too narrow to satisfy both, the FLOOR wins: a chat column below `chatColumnMinWidth`
    /// would put the pop-out's arrow through the rows it is pointing at.
    static func resolvedChatColumnWidth(requested: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let available = contentWidth - listColumnMinWidth - columnDividerWidth
        return max(chatColumnMinWidth, min(requested, max(chatColumnMinWidth, available)))
    }

    /// Trailing padding for the floating detail pop-out at a given chat column width.
    ///
    /// The arrow-meets-the-rows geometry (AITD-302) is derived from `chatColumnWidth`, so a
    /// dragged-wider chat column would leave the arrow pointing at empty space where the rows used
    /// to end. Giving the pop-out back exactly the width the chat column gained keeps the tip the
    /// same `detailArrowRowGap` from the row edge at every column width — the invariant survives
    /// the resize instead of holding only at the default.
    static func detailPopoutTrailingPadding(chatColumnWidth width: CGFloat) -> CGFloat {
        detailPanelMargin + max(0, width - chatColumnMinWidth)
    }

    /// Show the persistent chat column? Wide WINDOW + a selection that has a channel, and NOT in
    /// board mode — a board needs the full horizontal width for its columns, so the two are
    /// mutually exclusive (task f1430338).
    static func showsChatColumn(windowWidth: CGFloat, isRealList: Bool, isBoard: Bool = false) -> Bool {
        isRealList && !isBoard && windowWidth >= chatColumnWindowThreshold
    }
}
#endif
