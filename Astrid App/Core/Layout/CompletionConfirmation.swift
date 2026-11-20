import Foundation

/// "Complete this task?" — asked before finishing a task that is not yours (ADEV-70, web ADEV-56).
///
/// WHEN is `TaskLeadingControl.completionNeedsConfirmation`. This is WHAT it says: the popovers'
/// "Mark as done" row shows `message` under its label (ADEV-152), and the Mac's complete shortcut
/// asks the whole question in an alert. Mirrors web's `components/completion-confirmation.tsx`.
///
/// It names the assignee: a question about "this task" over an unlabelled photo is the blind
/// confirmation that trains people to accept without reading. With nobody assigned it says so.
enum CompletionConfirmation {

    static var title: String {
        NSLocalizedString("tasks.confirm_complete_title", comment: "")
    }

    static var confirmLabel: String {
        NSLocalizedString("reminders.complete", comment: "")
    }

    static var cancelLabel: String {
        NSLocalizedString("actions.cancel", comment: "")
    }

    /// "Assigned to Ada", or "Not assigned to anyone" when `assigneeLabel` is nil.
    static func message(assigneeLabel: String?) -> String {
        guard let assigneeLabel else {
            return NSLocalizedString("tasks.confirm_complete_unassigned", comment: "")
        }
        return String(format: NSLocalizedString("mac.assigned_to", comment: ""), assigneeLabel)
    }

    /// The person to name, or nil when nobody holds the task. Assigned to someone whose name has
    /// not loaded is still assigned: an empty name, never "nobody".
    static func assigneeLabel(assigneeId: String?, assignee: User?) -> String? {
        guard let assigneeId, !assigneeId.isEmpty else { return nil }
        return assignee?.name ?? assignee?.email ?? ""
    }

    /// The label for a task as it stands, resolving the assignee the same way the leading
    /// control does so the name matches the face on screen.
    static func assigneeLabel(for task: Task, assigneeId: String? = nil) -> String? {
        let id = assigneeId ?? task.assigneeId
        guard let id, !id.isEmpty else { return nil }
        let user = AssigneeResolver.resolve(id: id, members: [], taskAssignee: task.assignee,
                                            agents: AIAgentCache.shared.load() ?? [])
        return assigneeLabel(assigneeId: id, assignee: user)
    }
}
