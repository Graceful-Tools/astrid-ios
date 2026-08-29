import Foundation

/// The state math behind optimistic member add / remove / role change (task 33fc21fc).
///
/// `ListMemberService` used to do this only when OFFLINE. Online it awaited the
/// round-trip and never touched `membersByList`, so every caller's "optimistic"
/// update actually happened after the network answered — adding or removing a
/// person did nothing visible until a `fetchLists()` came back. `cancelInvitation`
/// was the one method that already did it properly; these functions are that
/// pattern, extracted so all four share it.
///
/// Pure on purpose: `ListMemberService` is a `@MainActor` singleton with no
/// dependency injection (its integration tests are all `XCTSkip`'d for exactly
/// that), so this is the only layer where the behavior can be pinned by tests.
enum ListMemberOptimistic {

    /// Marks a row the server has not confirmed yet. `ListMembershipTab` already
    /// keys its pending styling off this prefix, and `syncPendingOperations`
    /// keys the offline queue off it, so it stays the one spelling.
    static let placeholderPrefix = "temp_"

    static func newPlaceholderId() -> String { "\(placeholderPrefix)\(UUID().uuidString)" }

    static func isPlaceholder(_ id: String) -> Bool { id.hasPrefix(placeholderPrefix) }

    /// A stand-in row for someone we know only by the email that was typed.
    /// The email doubles as the display name until the server sends the real one —
    /// `User.displayName` already falls back to `email`.
    static func placeholder(id: String, listId: String?, email: String, role: String) -> ListMember {
        ListMember(
            id: id,
            listId: listId,
            userId: id,
            role: role,
            createdAt: Date(),
            updatedAt: Date(),
            user: User(id: id, email: email, name: nil, image: nil, isPending: true)
        )
    }

    // MARK: - Roster

    /// Append `member`, unless the roster already holds that person. Double-tapping
    /// Add, or re-adding someone who is already on the list, must not split them
    /// into two rows — and when the existing row is the real one, it wins.
    static func applyingAdd(_ roster: [ListMember], member: ListMember) -> [ListMember] {
        guard !roster.contains(where: { matches($0, member) }) else { return roster }
        return roster + [member]
    }

    /// Drop the row for `userId`. Matches the nested user too: server rosters key
    /// the row `id` off the membership rather than the user, so comparing only `id`
    /// left the row on screen.
    static func applyingRemoval(_ roster: [ListMember], userId: String) -> [ListMember] {
        roster.filter { $0.userId != userId && $0.user?.id != userId && $0.id != userId }
    }

    /// Drop one specific row by its own id — the rollback for a failed add, where
    /// only the placeholder's id is known.
    static func applyingRemoval(_ roster: [ListMember], memberId: String) -> [ListMember] {
        roster.filter { $0.id != memberId }
    }

    /// Rewrite one person's role in place. `ListMember.role` is a `let`, so the row
    /// is rebuilt — carrying `user` across, or the promotion would blank the avatar
    /// and name until the next fetch.
    static func applyingRoleChange(_ roster: [ListMember], userId: String, role: String) -> [ListMember] {
        roster.map { existing in
            guard existing.userId == userId || existing.user?.id == userId else { return existing }
            return ListMember(
                id: existing.id,
                listId: existing.listId,
                userId: existing.userId,
                role: role,
                createdAt: existing.createdAt,
                updatedAt: Date(),
                user: existing.user
            )
        }
    }

    /// Swap the placeholder for what the server actually created.
    ///
    /// `confirmed == nil` means the server queued an invitation instead of a
    /// membership — nobody has joined yet, so the pending row STAYS. Dropping it
    /// there is what made an invite look like the add had done nothing.
    static func reconcilingAdd(_ roster: [ListMember],
                               placeholderId: String,
                               confirmed: ListMember?) -> [ListMember] {
        guard let confirmed else { return roster }
        guard let index = roster.firstIndex(where: { $0.id == placeholderId }) else {
            return applyingAdd(roster, member: confirmed)
        }
        var result = roster
        result.remove(at: index)
        // Guard against the server row already being present under its real id.
        guard !result.contains(where: { matches($0, confirmed) }) else { return result }
        result.insert(confirmed, at: index)
        return result
    }

    // MARK: - TaskList mirror
    //
    // The membership views read `listMembers`, but the permission helpers and the
    // older surfaces read `admins` / `members`. An optimistic update that touched
    // only one of them shows a half-applied list, so all three move together.

    static func applyingAdd(_ list: TaskList, member: ListMember) -> TaskList {
        var result = list
        let roster = applyingAdd(list.listMembers ?? [], member: member)
        guard roster.count != (list.listMembers ?? []).count else { return result }
        result.listMembers = roster
        if let user = member.user {
            if isAdminRole(member.role) {
                result.admins = (result.admins ?? []) + [user]
            } else {
                result.members = (result.members ?? []) + [user]
            }
        }
        return result
    }

    static func applyingRemoval(_ list: TaskList, userId: String) -> TaskList {
        var result = list
        result.listMembers = list.listMembers.map { applyingRemoval($0, userId: userId) }
        result.admins?.removeAll { $0.id == userId }
        result.members?.removeAll { $0.id == userId }
        return result
    }

    /// Roll one specific row back off the list — the failed-add path, where only
    /// the placeholder's id is known.
    static func applyingRemoval(_ list: TaskList, memberId: String) -> TaskList {
        var result = list
        result.listMembers = list.listMembers.map { applyingRemoval($0, memberId: memberId) }
        result.admins?.removeAll { $0.id == memberId }
        result.members?.removeAll { $0.id == memberId }
        return result
    }

    static func reconcilingAdd(_ list: TaskList,
                               placeholderId: String,
                               confirmed: ListMember?) -> TaskList {
        guard let confirmed else { return list }
        return applyingAdd(applyingRemoval(list, memberId: placeholderId), member: confirmed)
    }

    static func applyingRoleChange(_ list: TaskList, userId: String, role: String) -> TaskList {
        var result = list
        result.listMembers = list.listMembers.map { applyingRoleChange($0, userId: userId, role: role) }

        // A promotion MOVES the person between the two rosters. Copying instead
        // would render them twice.
        let user = result.listMembers?.first { $0.userId == userId || $0.user?.id == userId }?.user
            ?? list.admins?.first { $0.id == userId }
            ?? list.members?.first { $0.id == userId }
        guard let user else { return result }

        result.admins?.removeAll { $0.id == userId }
        result.members?.removeAll { $0.id == userId }
        if isAdminRole(role) {
            result.admins = (result.admins ?? []) + [user]
        } else {
            result.members = (result.members ?? []) + [user]
        }
        return result
    }

    // MARK: - Internals

    static func isAdminRole(_ role: String) -> Bool {
        role == "admin" || role == "owner"
    }

    /// Same person? By row id, by user id, or by email — the last one matters
    /// because a placeholder is known only by the email that was typed.
    private static func matches(_ lhs: ListMember, _ rhs: ListMember) -> Bool {
        if lhs.id == rhs.id { return true }
        if lhs.userId == rhs.userId { return true }
        if let a = lhs.user?.id, let b = rhs.user?.id, a == b { return true }
        if let a = lhs.user?.email?.lowercased(), let b = rhs.user?.email?.lowercased(), a == b { return true }
        return false
    }
}
