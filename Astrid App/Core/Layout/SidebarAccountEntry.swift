import Foundation

/// Where the sidebar's account controls lead (AITD-493).
///
/// The user card and the gear sit side by side — at the top of the iOS sidebar, at the bottom
/// of the Mac's — and used to go to two places: the card to the Profile screen, the gear to
/// Settings. Web's user menu leads to Settings, and that is the pattern chosen across clients
/// (AWTD-1179). Both controls ask here, so they cannot drift to different destinations again.
enum SidebarAccountEntry: CaseIterable {
    /// The avatar and name.
    case userCard
    case gear

    var destination: SidebarAccountDestination {
        switch self {
        case .userCard, .gear: return .settings
        }
    }
}

enum SidebarAccountDestination: Equatable {
    case settings
    /// The Completed / Inspired / Supported screen. No sidebar control leads here now; it is
    /// reached from inside Settings (iOS) and from the gear menu (Mac).
    case profile
}
