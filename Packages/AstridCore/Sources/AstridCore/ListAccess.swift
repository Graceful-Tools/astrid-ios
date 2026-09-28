import Foundation

/// Everything one person may do with one list — astrid-core's `permissions`, which answers as the
/// web's `lib/list-permissions.ts` does (locked by the contract fixture there).
///
/// One call answers every question, so a view that needs two of them does not ask twice.
public struct ListAccess: Decodable, Equatable, Sendable {
    public enum Role: String, Decodable, Sendable {
        case owner, admin, member, viewer
    }

    /// `nil` when the person has no access at all.
    public let role: Role?
    public let canView: Bool
    /// Add to and change tasks in the list at all.
    public let canEditTasks: Bool
    /// A real role, as opposed to a passer-by on a public list.
    public let hasExplicitRole: Bool
    /// Rename, image, defaults, filters, sharing.
    public let canManage: Bool
    public let canManageMembers: Bool
    /// Owner only: deleting a shared list destroys other people's work.
    public let canDelete: Bool
    /// Change the task the question was asked about (its creator was passed in).
    public let canEditTask: Bool

    /// Nobody signed in, or a question the core could not read.
    public static let none = ListAccess(
        role: nil, canView: false, canEditTasks: false, hasExplicitRole: false, canManage: false,
        canManageMembers: false, canDelete: false, canEditTask: false)

    init(role: Role?, canView: Bool, canEditTasks: Bool, hasExplicitRole: Bool, canManage: Bool,
         canManageMembers: Bool, canDelete: Bool, canEditTask: Bool) {
        self.role = role
        self.canView = canView
        self.canEditTasks = canEditTasks
        self.hasExplicitRole = hasExplicitRole
        self.canManage = canManage
        self.canManageMembers = canManageMembers
        self.canDelete = canDelete
        self.canEditTask = canEditTask
    }
}

extension CoreRules {
    /// What `userId` may do with `list` (the list's wire shape), and with a task in it written by
    /// `taskCreatorId`. Never throws: a question the core cannot read answers "no access", the
    /// safe direction — the server would refuse anyway.
    public static func listAccess(
        of list: some Encodable, userId: String?, taskCreatorId: String? = nil
    ) -> ListAccess {
        (try? ask(
            ListAccessRequest(list: AnyEncodable(list), userId: userId, taskCreatorId: taskCreatorId),
            as: ListAccess.self)) ?? .none
    }
}

private struct ListAccessRequest: Encodable {
    let kind = "listAccess"
    let list: AnyEncodable
    let userId: String?
    let taskCreatorId: String?
}
