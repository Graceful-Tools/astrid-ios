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
    /// A repeating task puts the photo, round, inside the repeat arrows instead of the priority
    /// square — the same frame iOS and web draw, at this same size (AITD-602, AITD-606, AITD-612).
    var repeating: Bool = false

    var body: some View {
        Group {
            if repeating {
                RepeatFramedMark(priority: priority, controlSize: size) { photo }
            } else {
                photo
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.25)
                            .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 2)
                    )
            }
        }
        .help(String(format: NSLocalizedString("mac.assigned_to", comment: ""), user.displayName))
    }

    /// The photo, or initials while it loads. Unsized and unclipped: the square and the repeat
    /// frame each give it their own shape.
    @ViewBuilder private var photo: some View {
        if let s = user.cachedImageURL, let url = URL(string: s) {
            CachedAsyncImage(url: url) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { initials }
        } else {
            initials
        }
    }

    private var initials: some View {
        ZStack {
            Rectangle().fill(Theme.accent)
            Text(user.initials)
                .macFont(.system(size: (repeating ? RepeatFrameGeometry.innerSize(control: size) : size) * 0.5,
                                 weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Nobody assigned: "U" in the priority square, or inside the repeat arrows when the task repeats
/// (AITD-606) — the row and the detail panel both draw it from here.
struct MacUnassignedMark: View {
    let priority: Task.Priority
    var size: CGFloat
    var repeating: Bool = false

    var body: some View {
        if repeating {
            RepeatFramedMark(priority: priority, controlSize: size) { glyph }
        } else {
            glyph
                .frame(width: size, height: size)
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusSmall)
                    .stroke(MacTaskVisuals.priorityColor(priority), lineWidth: 1.5))
        }
    }

    private var glyph: some View {
        Text(TaskLeadingControl.unassignedGlyph)
            .macFont(.system(size: repeating ? 9 : 11, weight: .semibold))
            .foregroundStyle(MacTaskVisuals.priorityColor(priority))
    }
}
#endif
