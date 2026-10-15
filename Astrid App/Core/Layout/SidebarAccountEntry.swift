import Foundation

/// Where the sidebar's account controls lead (AITD-493).
///
/// The user card and the gear sit side by side in the sidebar's footer. AITD-493 sent both to
/// Settings, matching web's single user menu (AWTD-1179); Jon then asked for them apart — *"gear
/// take you to settings. User profile to user profile"* (AITD-502). Both controls ask here.
enum SidebarAccountEntry: CaseIterable {
    /// The avatar and name.
    case userCard
    case gear

    var destination: SidebarAccountDestination {
        switch self {
        case .userCard: return .profile
        case .gear: return .settings
        }
    }
}

enum SidebarAccountDestination: Equatable {
    case settings
    /// The Completed / Inspired / Supported screen — the user card's destination.
    case profile
}
