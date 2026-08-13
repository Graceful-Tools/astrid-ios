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
}
