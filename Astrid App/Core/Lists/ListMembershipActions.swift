//  ListMembershipActions.swift
//  Astrid — the membership mutations both platforms make (AITD-399).
//
//  `ListMembershipTab` (iOS) and `MacListMembershipTab` (Mac) had written these wrappers twice.
//  What they share is ONLY the middle of each action: which service call it makes, and how its
//  arguments are derived. They deliberately do NOT share the layers on either side of it —
//
//    · iOS is optimistic. It edits its own `list` snapshot through `ListMemberOptimistic`, hands
//      it back with `onUpdate`, tracks `removedMemberEmails` so stale data cannot resurrect a
//      removed row, and refreshes with `ListService.fetchLists()`.
//    · The Mac is not. It reads `ListMemberService.membersByList` and refreshes with
//      `fetchMembers(listId:)`.
//
//  Those are different designs over different membership sources, not copies of each other, so
//  folding them together would be inventing a merge rather than removing one. Everything here
//  therefore `throws` and returns: no optimistic edit, no refresh, and no error presentation.
//  iOS sets `errorMessage`; the Mac wraps the call in `AppActions.perform`.
//
//  Writes go through `ListMemberService` / `ListService`, never `AstridAPIClient` — ASTRID.md §0
//  rule 1 — which is also what puts them in the pending-ops queue so they survive being offline.

import Foundation

enum ListMembershipActions {

    /// An agent is invited by EMAIL but removed by USER ID, and a `User` for an agent may carry
    /// neither. Each tab used to discover that with its own `guard ... else { return }`, so the
    /// failure was silent on the Mac and a debug log on iOS.
    enum AgentError: LocalizedError {
        /// The agent record has no email, so there is nothing to invite.
        case noEmail
        /// The agent is not on this list, so there is no membership to remove.
        case notAMember(email: String)

        var errorDescription: String? {
            switch self {
            case .noEmail:
                return NSLocalizedString("lists.agent_missing_email", comment: "")
            case .notAMember(let email):
                return String(format: NSLocalizedString("lists.agent_not_a_member", comment: ""), email)
            }
        }
    }

    private static var members: ListMemberService { .shared }
    private static var lists: ListService { .shared }

    // MARK: - People

    /// Invite someone, or add them outright if they already have an account.
    ///
    /// The returned `ListMember` may be a STUB — an invitation, or an add still queued offline —
    /// which callers tell apart with `ListMemberOptimistic.isPlaceholder` / an `invite_` prefix.
    @discardableResult
    static func addMember(listId: String, email: String, role: String) async throws -> ListMember {
        try await members.addMember(listId: listId, email: email, role: role)
    }

    static func changeRole(listId: String, userId: String, to role: String) async throws {
        try await members.updateMemberRole(listId: listId, userId: userId, role: role)
    }

    static func removeMember(listId: String, userId: String) async throws {
        try await members.removeMember(listId: listId, userId: userId)
    }

    /// An invitation is addressed by EMAIL on its own resource — it has no userId, because there
    /// may not be an account yet. That is why this is not `removeMember`.
    static func cancelInvitation(listId: String, invitationId: String, email: String) async throws {
        try await members.cancelInvitation(listId: listId, invitationId: invitationId, email: email)
    }

    static func changeInvitationRole(listId: String, invitationId: String, email: String, to role: String) async throws {
        try await members.updateInvitationRole(listId: listId, invitationId: invitationId, email: email, role: role)
    }

    /// Hand the list over and leave it, in ONE call.
    ///
    /// Deliberately NOT followed by a leave: the server moves ownership and drops the caller's
    /// membership in a single transaction, so a second call would act on a list this user is no
    /// longer a member of.
    static func transferOwnership(listId: String, to successorId: String) async throws {
        try await lists.transferOwnership(listId: listId, to: successorId)
    }

    // MARK: - AI agents

    /// Agents join as ordinary members — there is no separate agent role.
    @discardableResult
    static func addAgent(_ agent: User, toList listId: String) async throws -> ListMember {
        guard let email = agent.email, !email.isEmpty else { throw AgentError.noEmail }
        return try await members.addMember(listId: listId, email: email, role: "member")
    }

    /// Remove an agent, resolving its membership id from its email first.
    ///
    /// `roster` is whichever membership rows the caller has — iOS passes the ones on its `list`
    /// snapshot, the Mac passes `ListMemberService.membersByList`.
    static func removeAgent(_ agent: User, fromList list: TaskList, roster: [ListMember]) async throws {
        guard let email = agent.email, !email.isEmpty else { throw AgentError.noEmail }
        guard let userId = ListMembershipRoster.memberId(forEmail: email, in: list, roster: roster) else {
            throw AgentError.notAMember(email: email)
        }
        try await members.removeMember(listId: list.id, userId: userId)
    }

    /// Every AI agent this account can add to a list, newest answer first and the cache behind it.
    ///
    /// The cache WRITE is the part that used to be iOS-only, which left the Mac's offline
    /// fallback permanently empty — it read a cache nothing on that platform ever filled.
    static func availableAgents() async -> [User] {
        do {
            let users = try await RemoteResourceService.shared.searchUsersWithAIAgents(
                query: "", taskId: nil, listIds: nil
            )
            let agents = users.filter { $0.isAIAgent == true }
            AIAgentCache.shared.save(agents)
            return agents
        } catch {
            AppLog.debug("❌ [ListMembershipActions] Failed to load AI agents: \(error)")
            return AIAgentCache.shared.load() ?? []
        }
    }
}
