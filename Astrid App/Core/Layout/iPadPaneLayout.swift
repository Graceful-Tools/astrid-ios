import CoreGraphics

/// How the iPad splits its window into panes (Task a34d0163).
///
/// The 2- and 3-column layouts were described one way in Settings and built another: the
/// list-messages pane was unreachable (`showChatPanel` was never set true), so "task list and
/// list messages" was really just a task list. The rule lived nowhere — widths and visibility
/// were inlined across two view builders that had already drifted apart.
///
/// Pure, so the layout can be pinned by tests instead of by looking at a simulator.
/// Companion to `HeaderViewToggle`, which decides the header's segments: that contract already
/// says `messages` is a rotator step ONLY in one-column layouts, precisely because on a wide
/// layout it is supposed to be a pane sitting beside the list rather than replacing it.
enum iPadPaneLayout {

    /// Pane widths, in points, left to right. A pane that is not shown is 0 wide.
    struct Panes: Equatable {
        let sidebar: CGFloat     // list picker; 0 unless it is permanently visible (3-column)
        let list: CGFloat        // task list, or the board
        let messages: CGFloat    // list messages
    }

    /// The permanently-visible list picker's share of the window in 3-column.
    private static let sidebarShare: CGFloat = 0.28
    /// The messages pane's share of what is left after the picker. Under a half, so the task
    /// list — the thing you came for — always stays the wider of the two.
    private static let messagesShare: CGFloat = 0.45

    /// Selections that are not a list with a chat channel. `my-tasks` is deliberately absent:
    /// it is virtual but DOES have a channel, which `ChatPanelView` resolves from a virtual key,
    /// the same one web and Mac resolve. Showing an empty pane for the others would be worse
    /// than showing none.
    private static let selectionsWithoutChannel: Set<String> = [
        "search", "shared", "favorites", "settings", "profile",
    ]

    /// Does the list-messages pane belong on screen for this selection?
    ///
    /// Only in list view: the board keeps the room it has (and a full-screen board keeps all of
    /// it). Messages replacing the list is a one-column behaviour; here it sits beside it.
    static func showsMessages(columns: Int, viewMode: HeaderToggleSegment,
                              listId: String?, boardFullScreen: Bool) -> Bool {
        guard viewMode == .list, !boardFullScreen else { return false }
        guard let listId, !listId.isEmpty else { return false }
        return !selectionsWithoutChannel.contains(listId)
    }

    /// Full screen is a board affordance — offering it on a list view would just hide the picker.
    static func offersFullScreen(viewMode: HeaderToggleSegment) -> Bool {
        viewMode == .board
    }

    static func widths(total: CGFloat, columns: Int,
                       showsMessages: Bool, boardFullScreen: Bool) -> Panes {
        if boardFullScreen {
            return Panes(sidebar: 0, list: total, messages: 0)
        }
        // In 2-column the picker is the sliding drawer, so it costs no width.
        let sidebar = columns >= 3 ? total * sidebarShare : 0
        let remaining = total - sidebar
        guard showsMessages else {
            return Panes(sidebar: sidebar, list: remaining, messages: 0)
        }
        let messages = remaining * messagesShare
        return Panes(sidebar: sidebar, list: remaining - messages, messages: messages)
    }

    /// How wide the task-detail panel is when it slides in.
    ///
    /// "Task details appearing over list messages" — so when there is a messages pane the detail
    /// is exactly as wide as it, and covers that pane and nothing else. The task list you are
    /// working in stays visible. With no messages pane there is nothing to cover, so the detail
    /// keeps the share it has always had.
    ///
    /// Expanded (task c5ba07ed) it fills the CONTENT AREA — everything but the list picker. That
    /// is what "full screen" means on the Mac, whose pop-out expands to fill the detail column
    /// and leaves its sidebar alone (42013da7); the iPad says the same thing with the same two
    /// glyphs. In 2-column the picker is a sliding drawer costing no width, so this is the window.
    static func detailWidth(total: CGFloat, columns: Int, showsMessages: Bool,
                            isFullScreen: Bool = false) -> CGFloat {
        if isFullScreen {
            return total - (columns >= 3 ? total * sidebarShare : 0)
        }
        if showsMessages {
            return widths(total: total, columns: columns,
                          showsMessages: true, boardFullScreen: false).messages
        }
        return columns >= 3 ? total * 0.40 : total * 0.50
    }
}
