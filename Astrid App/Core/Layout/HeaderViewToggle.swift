import Foundation

/// Swift port of `lib/header-view-toggle.ts` (astrid-web). Pure logic
/// describing which segments the header's view-toggle should render and
/// whether they live in a unified 3-way segmented control or the legacy
/// split layout. Tests in HeaderViewToggleTests pin both platforms to
/// the same behavior.

enum HeaderToggleSegment: String, Equatable {
    case list, board, messages
}

struct HeaderViewToggleState: Equatable {
    /// True when the layout is a 1-column mobile layout.
    var isOneColumn: Bool
    /// True when the selected list has a project status board attached.
    var hasProjectBoard: Bool
    /// True when the chat panel is wired (caller has an onToggleActivePanel).
    var chatAvailable: Bool
    /// Current top-level view.
    var activeView: ActiveView
    /// True when a search input is active.
    var isSearching: Bool

    enum ActiveView: String, Equatable {
        case list, settings, search
    }
}

struct HeaderViewToggleConfig: Equatable {
    let segments: [HeaderToggleSegment]
    /// `true`  → render a single unified segmented control containing
    ///           all segments (1-col mode).
    /// `false` → render the legacy split layout: List/Board as a
    ///           segmented control, Messages as a separate ChatToggle.
    let unified: Bool
}

/// The segment the header's rotator button moves to next (Task a34d0163).
///
/// `includesMessages` is false wherever list messages are a PANE beside the list rather than a
/// view that replaces it — the iPad's 2- and 3-column layouts. Rotating into messages there
/// would hide the task list to show something already on screen. This is the same rule
/// `getHeaderViewToggle` applies when it withholds `.messages` from a non-one-column layout.
func nextRotatorSegment(after current: HeaderToggleSegment,
                        hasBoard: Bool,
                        includesMessages: Bool) -> HeaderToggleSegment {
    switch current {
    case .list:
        if includesMessages { return .messages }
        return hasBoard ? .board : .list
    case .messages:
        return hasBoard ? .board : .list
    case .board:
        return .list
    }
}

/// Decide which segments the header's view-toggle should render and how.
/// See `lib/header-view-toggle.ts` in astrid-web for the canonical spec.
func getHeaderViewToggle(_ state: HeaderViewToggleState) -> HeaderViewToggleConfig {
    if state.activeView != .list || state.isSearching {
        return HeaderViewToggleConfig(segments: [], unified: false)
    }

    var segments: [HeaderToggleSegment] = [.list]
    if state.hasProjectBoard { segments.append(.board) }

    if state.isOneColumn {
        if state.chatAvailable { segments.append(.messages) }
        if segments.count <= 1 {
            return HeaderViewToggleConfig(segments: [], unified: false)
        }
        return HeaderViewToggleConfig(segments: segments, unified: true)
    }

    return HeaderViewToggleConfig(segments: segments, unified: false)
}
