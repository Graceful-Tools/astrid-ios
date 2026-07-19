//  MacTaskRow.swift
//  Astrid for Mac — iOS-style task row for the list view (replaces the flat Table).
//  Mirrors iOS `TaskRowView`: a priority-colored completion checkbox, the title (strikethrough
//  when done), and a metadata line with the due date + list chips. Priority is conveyed by the
//  checkbox ring, so there is NO separate priority column. Supports inline rename in place.

#if os(macOS)
import SwiftUI

struct MacTaskRow: View {
    let task: Task
    /// List ids the surrounding view already conveys (the currently-viewed list) — filtered out
    /// of the chip set so the row doesn't repeat the list you're already looking at.
    var hiddenListIds: Set<String> = []
    let isEditing: Bool
    @Binding var editingTitle: String
    var indent: Int = 0                  // subtask nesting depth (0 = top level)
    let onToggle: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void

    @ObservedObject private var listService = ListService.shared
    @ObservedObject private var auth = AuthManager.shared

    /// The assignee to surface as an avatar (task.assignee, or a minimal User from the id so the
    /// shared UserImageCache can still resolve a picture) — nil for own/unassigned tasks.
    private var avatarAssignee: User? {
        guard MacAssignee.showsAvatar(assigneeId: task.assigneeId, currentUserId: auth.userId),
              let id = task.assigneeId else { return nil }
        return task.assignee ?? User(id: id, email: nil, name: nil, image: nil)
    }

    private var chipLists: [TaskList] {
        (task.listIds ?? [])
            .filter { !hiddenListIds.contains($0) }
            .compactMap { id in listService.lists.first { $0.id == id } }
    }

    private var dueText: String? {
        guard let due = task.dueDateTime else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = task.isAllDay ? .none : .short
        return f.string(from: due)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let assignee = avatarAssignee {
                // Assigned to someone else → show their avatar in place of the checkbox (iOS parity).
                MacAssigneeAvatar(user: assignee, priority: task.priority, size: 20)
            } else {
                Button(action: onToggle) {
                    MacTaskCheckbox(completed: task.completed, priority: task.priority, size: 20)
                }
                .buttonStyle(.plain)
                .help(task.completed ? "Mark incomplete" : "Mark complete")
                .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .medium))
                        .onSubmit(onCommitEdit)
                        .onExitCommand(perform: onCancelEdit)
                } else {
                    Text(task.title)
                        .font(.system(size: 15, weight: .medium))
                        .strikethrough(task.completed)
                        .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                        .lineLimit(2)
                }

                if dueText != nil || !chipLists.isEmpty {
                    HStack(spacing: 8) {
                        if let dueText {
                            Text(dueText)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted)
                        }
                        ForEach(chipLists.prefix(2)) { list in
                            HStack(spacing: 4) {
                                MacListIcon(list: list, size: 11)
                                Text(list.name).font(.system(size: 12)).lineLimit(1)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.bgSecondary, in: Capsule())
                        }
                        if chipLists.count > 2 {
                            Text("+\(chipLists.count - 2)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.leading, CGFloat(min(indent, 4)) * 16)   // per-level indent, capped at 4 (deeper still shows)
        .contentShape(Rectangle())
    }
}
#endif
