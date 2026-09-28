import AstridCore
import Foundation

/// Who may do what with a list (Task da56d096) — answered by astrid-core.
///
/// Permission decisions are a cross-platform contract with Web (see astrid-web
/// `docs/PRODUCT_CONTRACT.md`): astrid-core's `permissions` runs web's own rules, locked by the
/// contract fixture generated from `lib/list-permissions.ts`. This type is the Swift face of that
/// answer and holds no rule of its own. The Swift copy it replaced matched roles case-sensitively
/// and only on `userId`, so members written as `MEMBER` by an old endpoint were locked out on Apple
/// only (astrid-core `docs/CONTRACTS.md` D6).
enum ListPermissions {

    /// Everything `userId` may do with `list`, and with `task` in it when one is given.
    static func access(_ list: TaskList, userId: String?, task: Task? = nil) -> ListAccess {
        CoreRules.listAccess(of: AccessFields(list), userId: userId,
                             taskCreatorId: task?.effectiveCreatorId)
    }

    /// The part of a list that decides access, in its wire shape — all the core reads. A list can
    /// carry its whole task array, and a row asks this once per task.
    private struct AccessFields: Encodable {
        struct Ref: Encodable { let id: String }
        struct Member: Encodable {
            let userId: String
            let role: String?
            let user: Ref?
        }
        let ownerId: String?
        let owner: Ref?
        let privacy: String?
        let publicListType: String?
        let listMembers: [Member]

        init(_ list: TaskList) {
            ownerId = list.ownerId
            owner = list.owner.map { Ref(id: $0.id) }
            privacy = list.privacy?.rawValue
            publicListType = list.publicListType
            listMembers = (list.listMembers ?? []).map {
                Member(userId: $0.userId, role: $0.role, user: $0.user.map { Ref(id: $0.id) })
            }
        }
    }

    /// May this user change the list's settings — name, image, defaults, filters, sharing?
    /// Owner or admin.
    static func canEditSettings(_ list: TaskList, userId: String?) -> Bool {
        access(list, userId: userId).canManage
    }

    /// May this user delete the list? The owner only: deleting a shared list destroys other
    /// people's work, so it stays with the owner even though an admin may edit everything else.
    static func canDelete(_ list: TaskList, userId: String?) -> Bool {
        access(list, userId: userId).canDelete
    }

    /// May this user add tasks to the list? Web's `canUserEditTasks`.
    static func canAddTasks(_ list: TaskList, userId: String?) -> Bool {
        access(list, userId: userId).canEditTasks
    }

    /// Is `task` read-only for this user in `list`? Web's `canUserEditTask`, negated.
    static func isTaskReadOnly(_ task: Task, in list: TaskList, userId: String?) -> Bool {
        !access(list, userId: userId, task: task).canEditTask
    }
}
