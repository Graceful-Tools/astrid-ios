import Foundation

/// Who is on a list, who is merely invited, and whether you may walk away from it.
///
/// Extracted so the Mac can answer these the way iOS and Web already do (AITD-388). The
/// pending-invitation rule below was private to `ListMembershipTab`, and the Mac — which had no
/// copy at all — showed pending invitations as though they were full members, complete with a
/// role picker and a Remove button that called the wrong endpoint.
///
/// Membership and permission decisions are a cross-platform contract with Web (astrid-web
/// `docs/PRODUCT_CONTRACT.md`), which is the same argument `ListPermissions` makes.
enum ListMembershipRoster {

    // MARK: - Pending invitations

    /// Invitations nobody has accepted yet.
    ///
    /// AN INVITATION IS NOT DELETED WHEN IT IS ACCEPTED — the row survives, so the raw
    /// `invitations` array keeps listing people who joined days ago. Showing it unfiltered means
    /// the same person appears twice: once as a member, once as "pending" forever.
    ///
    /// Matched by EMAIL, because that is all an unaccepted invitation has. It has no `userId` —
    /// there may not be an account yet — which is also why cancelling one goes to
    /// `/invitations` by email rather than to `/members/{userId}`.
    ///
    /// The roster is `listMembers` plus the owner (ASTRID.md §8 row 3). The owner is included
    /// because an owner who invited themselves before creating the list is otherwise pending on
    /// their own list.
    static func pendingInvitations(in list: TaskList) -> [ListInvite] {
        guard let invitations = list.invitations else { return [] }

        var joined = Set<String>()
        if let listMembers = list.listMembers {
            joined.formUnion(listMembers.compactMap { $0.user?.email })
        }
        if let ownerEmail = list.owner?.email {
            joined.insert(ownerEmail)
        }

        return invitations.filter { !joined.contains($0.email) }
    }

    // MARK: - Leaving

    /// What the leave control offers this person, if anything.
    enum LeaveOption: Equatable {
        /// No control at all — they are not a member, or leaving would strand the list.
        case none
        /// Ordinary "Leave List".
        case leave
        /// "Transfer Ownership & Leave" — the owner cannot simply vanish.
        case transferOwnership
    }

    /// May this person leave, and on what terms?
    ///
    /// THE LIST MUST BE LEFT ADMINISTRABLE. Web's `canCurrentUserLeave` counts the admins and
    /// refuses when the leaver is the last one; without that guard a shared list can end up with
    /// nobody who can invite, rename or delete it, and no way back short of support.
    ///
    /// An OWNER always gets `transferOwnership` rather than `leave`, even when other admins
    /// exist. Ownership is a distinct thing from administration — it is what `canDelete` keys on
    /// — so it has to be handed to someone explicitly rather than implied by whoever happens to
    /// remain.
    ///
    /// A plain MEMBER leaving costs the list nothing, so they are never blocked.
    static func leaveOption(for list: TaskList, userId: String?) -> LeaveOption {
        guard let userId, let role = list.role(for: userId) else { return .none }

        switch role {
        case .owner:
            return .transferOwnership
        case .admin:
            return hasAnotherAdministrator(list, excluding: userId) ? .leave : .none
        case .member:
            return .leave
        case .viewer:
            // Looking at a public list you never joined. There is nothing to leave.
            return .none
        }
    }

    /// Is there someone OTHER than this person who could still administer the list?
    ///
    /// The owner counts, whether or not they also appear in `listMembers` — on most lists the
    /// owner is not a member row at all, and missing them would tell the one admin on a healthy
    /// list that they are trapped.
    static func hasAnotherAdministrator(_ list: TaskList, excluding userId: String) -> Bool {
        if let ownerId = list.ownerId ?? list.owner?.id, ownerId != userId { return true }
        guard let listMembers = list.listMembers else { return false }
        return listMembers.contains { $0.role == "admin" && $0.userId != userId }
    }
}
