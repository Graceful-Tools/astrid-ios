//  MacAssigneeAvatar.swift
//  Astrid for Mac — assignee avatar for task rows (Task 942e49df).
//
//  Mirrors iOS TaskRowView: a task assigned to SOMEONE ELSE shows that person's avatar (with a
//  priority-colored border) in place of the completion checkbox, so shared-list ownership is
//  scannable. Own/unassigned tasks keep the checkbox. Pure decision helper is unit-tested.

#if os(macOS)
import SwiftUI

enum MacAssignee {
    /// Show the assignee avatar (instead of the checkbox) only when the task is assigned to a
    /// user OTHER than the current one — matches iOS/web.
    /// Delegates to the SHARED rule rather than restating it.
    ///
    /// This was its own copy — "assigned, and not to me" — which is why project mode did not
    /// reach it: there a task assigned to YOU shows your photo too (task 132d7b3f), and a rule
    /// written out separately here could not know that. Two spellings of "whose face goes on
    /// this task" is how the Mac and the phone start disagreeing about the same task.
    static func showsAvatar(assigneeId: String?,
                            currentUserId: String?,
                            displayMode: TaskDisplayMode) -> Bool {
        if case .avatar = TaskLeadingControl.kind(assigneeId: assigneeId,
                                                  currentUserId: currentUserId,
                                                  displayMode: displayMode) { return true }
        return false
    }
}

struct MacAssigneeAvatar: View {
    let user: User
    let priority: Task.Priority
    var size: CGFloat = 20

    var body: some View {
        Group {
            if let s = user.cachedImageURL, let url = URL(string: s) {
                CachedAsyncImage(url: url) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.25)
                .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 2)
        )
        .help(String(format: NSLocalizedString("mac.assigned_to", comment: ""), user.displayName))
    }

    private var initials: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(Theme.accent)
            Text(user.initials).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
        }
    }
}
#endif
