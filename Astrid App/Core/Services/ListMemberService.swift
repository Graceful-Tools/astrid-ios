import AstridCore
import Combine
import Foundation

/// Who a list is shared with, and every way to change it — through astrid-core.
///
/// A membership change is a question the server answers (there may be no such person, or this
/// account may not be allowed), so the core sends it at once and a refusal comes back as an error
/// with nothing changed. Only when the network is what failed does the core queue it, show it in
/// its cache, and send it when the connection returns — a queued invitation as a pending
/// invitation, never as a member (astrid-core `services::members`, CONTRACTS D31).
///
/// The roster lives on the cached list (`TaskList.listMembers` / `invitations`); this service
/// keeps the per-list rows the views bind to, drawn from there, plus the in-flight placeholder a
/// view shows while the server is being asked (task 33fc21fc).
@MainActor
class ListMemberService: ObservableObject {
    static let shared = ListMemberService()

    /// The people on whichever list was fetched last, for the older screens that read one roster.
    @Published var members: [User] = []
    /// listId → its rows: members, then invitations waiting (ids `invite_…`, or `temp_…` while an
    /// invitation made offline is still queued).
    @Published var membersByList: [String: [ListMember]] = [:]
    /// The caller's role per list, as the server reported it (Task 4a338b53). "viewer" means a
    /// non-member looking at a PUBLIC list, where the roster comes back EMPTY rather than 403 —
    /// so an empty list means "not shown to you", not "nobody here". See `ListMemberVisibility`.
    @Published var viewerRoleByList: [String: String] = [:]
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0

    /// Which list the flat `members` array reflects. An edit to some OTHER list must not rewrite
    /// it — that would blank the roster on whatever screen is open (task 33fc21fc).
    private var membersReflectListId: String?

    private var core: CoreSession { AppCore.shared.session }

    private init() {}

    // MARK: - Reading

    /// Ask the server for the roster, and show it. Offline, what the cache holds is shown and the
    /// error is thrown.
    func fetchMembers(listId: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        struct Roster: Decodable { let viewerRole: String? }
        do {
            let roster = try await core.run(
                CoreCommand(kind: "refreshListMembers", ["listId": .value(listId)]), as: Roster.self)
            if let role = roster.viewerRole { viewerRoleByList[listId] = role }
            await show(listId: listId, reflect: true)
        } catch {
            errorMessage = error.localizedDescription
            await show(listId: listId, reflect: true)
            throw error
        }
    }

    /// The cache at once, then the server's roster in the background.
    func fetchMembersLocalFirst(listId: String) async {
        await show(listId: listId, reflect: true)
        _Concurrency.Task { try? await self.fetchMembers(listId: listId) }
    }

    /// Draw `listId`'s rows from the core's cached list.
    private func show(listId: String, reflect: Bool = false) async {
        await ListService.shared.reload()
        guard let list = ListService.shared.getList(id: listId) else { return }
        let rows = Self.rows(for: list)
        membersByList[listId] = rows
        if reflect { membersReflectListId = listId }
        if membersReflectListId == listId {
            members = rows.filter { !Self.isInvitation($0.id) }.compactMap(\.user)
        }
    }

    /// A list's rows as the views draw them: its members, then the invitations waiting.
    static func rows(for list: TaskList) -> [ListMember] {
        let people = list.listMembers ?? []
        let invited = (list.invitations ?? []).map { invite in
            let id = ListMemberOptimistic.isPlaceholder(invite.id) ? invite.id : "invite_\(invite.id)"
            return ListMember(id: id, listId: list.id, userId: id, role: invite.role,
                              createdAt: invite.createdAt, updatedAt: nil,
                              user: User(id: id, email: invite.email, name: nil, image: nil, isPending: true))
        }
        return people + invited
    }

    private static func isInvitation(_ id: String) -> Bool {
        id.hasPrefix("invite_") || ListMemberOptimistic.isPlaceholder(id)
    }

    // MARK: - Changing

    /// What the core answers a membership change with.
    private struct Change: Decodable {
        let queued: Bool
        let member: ListMember?
        let invitation: ListInvite?
    }

    /// Invite someone, or add them outright if they already have an account.
    ///
    /// A placeholder row shows while the server is asked. The answer is the member it made, or a
    /// stub for an invitation waiting (`invite_…`) or queued offline (`temp_…`); a refusal takes
    /// the placeholder back off and is thrown.
    func addMember(listId: String, email: String, role: String = "member") async throws -> ListMember {
        let placeholderId = ListMemberOptimistic.newPlaceholderId()
        let placeholder = ListMemberOptimistic.placeholder(id: placeholderId, listId: listId, email: email, role: role)
        applyOptimistic(listId: listId) { ListMemberOptimistic.applyingAdd($0, member: placeholder) }

        let change: Change
        do {
            change = try await core.run(
                CoreCommand(kind: "inviteToList", [
                    "listId": .value(listId), "email": .value(email), "role": .value(role),
                ]),
                as: Change.self)
        } catch {
            applyOptimistic(listId: listId) { ListMemberOptimistic.applyingRemoval($0, memberId: placeholderId) }
            throw error
        }
        await show(listId: listId)
        refreshOutboxCounts()
        if let member = change.member { return member }
        let stubId = change.queued
            ? (change.invitation?.id ?? placeholderId)
            : "invite_\(change.invitation?.id ?? placeholderId)"
        return ListMember(id: stubId, listId: listId, userId: stubId, role: role,
                          createdAt: Date(), updatedAt: Date(), user: placeholder.user)
    }

    /// Change a member's role — at once on screen, reverted if the server refuses.
    func updateMemberRole(listId: String, userId: String, role: String) async throws {
        try await change(listId: listId,
                         optimistic: { ListMemberOptimistic.applyingRoleChange($0, userId: userId, role: role) },
                         CoreCommand(kind: "setMemberRole", [
                            "listId": .value(listId), "userId": .value(userId), "role": .value(role),
                         ]))
    }

    /// Remove a member — at once on screen, restored if the server refuses.
    func removeMember(listId: String, userId: String) async throws {
        try await change(listId: listId,
                         optimistic: { ListMemberOptimistic.applyingRemoval($0, userId: userId) },
                         CoreCommand(kind: "removeMember", ["listId": .value(listId), "userId": .value(userId)]))
    }

    /// Withdraw an invitation not yet accepted. Addressed by EMAIL: an unaccepted invitation has no
    /// user to name (AITD-388).
    func cancelInvitation(listId: String, invitationId: String, email: String) async throws {
        try await change(listId: listId,
                         optimistic: { $0.filter { !Self.isRow($0, invitation: invitationId) } },
                         CoreCommand(kind: "cancelInvitation", ["listId": .value(listId), "email": .value(email)]))
    }

    /// Change an invitation's role before it is accepted — the invitation twin of
    /// `updateMemberRole`, which addresses a member by user id an invitation does not have.
    func updateInvitationRole(listId: String, invitationId: String, email: String, role: String) async throws {
        try await change(listId: listId,
                         optimistic: { rows in
                             rows.map { row in
                                 guard Self.isRow(row, invitation: invitationId) else { return row }
                                 return ListMember(id: row.id, listId: row.listId, userId: row.userId, role: role,
                                                   createdAt: row.createdAt, updatedAt: Date(), user: row.user)
                             }
                         },
                         CoreCommand(kind: "setInvitationRole", [
                            "listId": .value(listId), "email": .value(email), "role": .value(role),
                         ]))
    }

    private static func isRow(_ row: ListMember, invitation invitationId: String) -> Bool {
        row.id == invitationId || row.id == "invite_\(invitationId)"
    }

    /// One change: shown at once, then the core's answer — the cache it leaves behind, or the
    /// rows as they were and the refusal thrown.
    private func change(listId: String, optimistic: ([ListMember]) -> [ListMember], _ command: CoreCommand) async throws {
        let before = membersByList[listId]
        let listBefore = ListService.shared.getList(id: listId)
        applyOptimistic(listId: listId, optimistic)
        do {
            _ = try await core.run(command, as: Change.self)
        } catch {
            if let before { membersByList[listId] = before }
            if let listBefore { ListService.shared.restoreCachedList(listId: listId, from: listBefore) }
            throw error
        }
        await show(listId: listId)
        refreshOutboxCounts()
    }

    /// Show a change before anyone has answered: on this service's rows and on the cached list
    /// every other screen reads.
    private func applyOptimistic(listId: String, _ transform: ([ListMember]) -> [ListMember]) {
        let updated = transform(membersByList[listId] ?? [])
        membersByList[listId] = updated
        if membersReflectListId == listId {
            members = updated.filter { !Self.isInvitation($0.id) }.compactMap(\.user)
        }
        ListService.shared.applyMemberChange(listId: listId) { list in
            var mirrored = list
            mirrored.listMembers = transform(list.listMembers ?? [])
            return mirrored
        }
    }

    // MARK: - Delivery

    /// Send what is queued now rather than at the delivery loop's next turn.
    func syncPendingOperations() async throws {
        try await core.run(CoreCommand(kind: "drain"))
        refreshOutboxCounts()
    }

    /// Give changes the server refused another go.
    func retryFailedOperations() async {
        _ = try? await core.run(CoreCommand(kind: "retryDeadLetters"))
        refreshOutboxCounts()
    }

    private func refreshOutboxCounts() {
        _Concurrency.Task {
            guard let stats = await JournalStats.load() else { return }
            pendingOperationsCount = stats.pending + stats.running
            failedOperationsCount = stats.failed
        }
    }

    func getMember(id: String) -> User? {
        members.first { $0.id == id }
    }
}
