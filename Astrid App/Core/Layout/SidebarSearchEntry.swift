import Foundation

/// Where the sidebar's search controls lead (AITD-494).
///
/// There are two: the Search row among the lists, and the icon at the far right of the brand
/// header (AWTD-1180 — Jon: *"(a) but add search icon inline on far right"*, where (a) is the
/// row). The icon is an addition, not a replacement, so both ask here and cannot drift to
/// different destinations.
enum SidebarSearchEntry: CaseIterable {
    /// The magnifying glass in the brand header.
    case headerIcon
    /// The Search row among the lists.
    case row

    var destination: SidebarSearchDestination {
        switch self {
        case .headerIcon, .row: return .search
        }
    }
}

enum SidebarSearchDestination: Equatable {
    /// The search over all tasks, completed included.
    case search
}
