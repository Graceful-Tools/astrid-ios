import Foundation

/// What an empty member list actually means (Task 4a338b53).
///
/// The members endpoint stopped 403-ing plain members, which is the fix — a member can now see who
/// they are collaborating with, as they always could on web. Neither client gated the fetch, so
/// that half needed no change.
///
/// What the change introduces is an ambiguity. A NON-member viewing a PUBLIC list gets HTTP 200
/// with an EMPTY array and `user_role: "viewer"`, because the member payload carries email
/// addresses and an outsider must not see them. So two different situations arrive looking
/// identical:
///
///   - the list genuinely has nobody on it
///   - you may look at the list, but not at who is on it
///
/// Only `user_role` tells them apart, and saying "No members yet" to the second is simply false.
enum ListMemberVisibility {

    enum EmptyState: Equatable {
        /// The list really has no other members.
        case genuinelyEmpty
        /// There may well be members; this viewer is not allowed to see them.
        case hiddenFromViewer
    }

    /// Roles that receive the real roster. Anything else — including an absent role from an older
    /// server — is treated as a viewer, because claiming a list is empty when we cannot know is the
    /// worse of the two mistakes.
    static let rolesThatSeeTheRoster: Set<String> = ["member", "admin", "owner"]

    static func emptyState(userRole: String?) -> EmptyState {
        guard let userRole, rolesThatSeeTheRoster.contains(userRole) else { return .hiddenFromViewer }
        return .genuinelyEmpty
    }

    /// Only relevant when there is nothing to show; with members present, just render them.
    static func showsEmptyState(memberCount: Int, userRole: String?) -> Bool {
        memberCount == 0
    }
}
