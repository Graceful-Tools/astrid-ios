import Foundation

/// Who may change a list (Task da56d096).
///
/// This rule was written out three separate times — `ListMembershipTab.canEditSettings`,
/// `ListSettingsModal.canEditSettings`, and Mac's `MacListMembersView.canManage` — and the Mac
/// copy was not equivalent: it compared role STRINGS against a separately-fetched member roster,
/// while iOS asked the shared model. Two sources of truth for one question, which is the shape of
/// bug where a control appears for someone who cannot use it.
///
/// Permission decisions are a cross-platform contract with Web (see astrid-web
/// `docs/PRODUCT_CONTRACT.md`), so they belong in one place that both platforms read. This mirrors
/// web's `canUserManageList`.
enum ListPermissions {

    /// May this user change the list's settings — name, image, defaults, filters, sharing?
    ///
    /// Owner or admin. A plain member can use the list but not reconfigure it, and a viewer of a
    /// public list certainly cannot.
    static func canEditSettings(_ list: TaskList, userId: String?) -> Bool {
        guard let userId else { return false }
        switch list.role(for: userId) {
        case .owner, .admin: return true
        default:             return false
        }
    }

    /// May this user delete the list?
    ///
    /// Deliberately its own question rather than an alias. Deleting a shared list destroys other
    /// people's work, so it stays with the owner even though an admin may edit everything else.
    static func canDelete(_ list: TaskList, userId: String?) -> Bool {
        guard let userId else { return false }
        return list.role(for: userId) == .owner
    }

    /// May this user add tasks to the list? Mirrors web's `canUserEditTasks`.
    ///
    /// A public copy-only list (the default for public) takes tasks only from its owner and
    /// admins — members and viewers copy the list to work in it. A public collaborative list
    /// takes them from anyone with a role, viewers included. Any other list: owner, admin, member.
    static func canAddTasks(_ list: TaskList, userId: String?) -> Bool {
        guard let userId else { return false }
        let role = list.role(for: userId)
        if list.privacy == .PUBLIC && (list.publicListType == "copy_only" || list.publicListType == nil) {
            return role == .owner || role == .admin
        }
        if list.privacy == .PUBLIC && list.publicListType == "collaborative" {
            return role != nil
        }
        return role == .owner || role == .admin || role == .member
    }

    /// Is `task` read-only for this user in `list`? Mirrors web's `canUserEditTask`.
    ///
    /// The list's owner and admins edit everything. On a public copy-only list nobody else does;
    /// on a public collaborative list the task's creator does too; on any other list every
    /// member does. Lived inline in `TaskListView` (four role checks) until the 2026-09-13 pass.
    static func isTaskReadOnly(_ task: Task, in list: TaskList, userId: String?) -> Bool {
        guard let userId else { return true }
        // Owner check by id first: a copied list carries its owner in `ownerId` / `owner` before
        // its member roster is populated.
        if (list.ownerId ?? list.owner?.id) == userId { return false }
        let role = list.role(for: userId)
        if role == .owner || role == .admin { return false }
        if list.privacy == .PUBLIC && (list.publicListType == "copy_only" || list.publicListType == nil) {
            return true
        }
        if list.privacy == .PUBLIC && list.publicListType == "collaborative" {
            return !task.isCreatedBy(userId)
        }
        return role != .member
    }
}
