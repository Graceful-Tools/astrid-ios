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
    static func showsAvatar(assigneeId: String?, currentUserId: String?) -> Bool {
        guard let assigneeId, !assigneeId.isEmpty else { return false }
        return assigneeId != currentUserId
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
        .help("Assigned to \(user.displayName)")
    }

    private var initials: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.25).fill(Theme.accent)
            Text(user.initials).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white)
        }
    }
}
#endif
