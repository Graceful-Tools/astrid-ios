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
    var isSelected: Bool = false
    @State private var hovering = false  // Mac hover affordance (77225941)
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
        // O(1) lookups via listsById (was an O(lists) scan per id, per reference — Task 4e0ce183).
        (task.listIds ?? [])
            .filter { !hiddenListIds.contains($0) }
            .compactMap { listService.listsById[$0] }
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
                .macPointingHand()
                .help(task.completed ? "Mark incomplete" : "Mark complete")
                .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Title", text: $editingTitle)
                        .textFieldStyle(.plain)
                        .font(MacTypography.rowTitle)
                        .onSubmit(onCommitEdit)
                        .onExitCommand(perform: onCancelEdit)
                } else {
                    Text(task.title)
                        .font(MacTypography.rowTitle)
                        .strikethrough(task.completed)
                        .foregroundStyle(task.completed ? Theme.textMuted : Theme.textPrimary)
                        .lineLimit(2)
                }

                let chips = chipLists   // computed ONCE per row render (was 3 references = 3 computations)
                if dueText != nil || !chips.isEmpty {
                    HStack(spacing: 8) {
                        if let dueText {
                            Text(dueText)
                                .font(MacTypography.rowMeta)
                                .foregroundStyle(Theme.textMuted)
                        }
                        ForEach(chips.prefix(2)) { list in
                            HStack(spacing: 4) {
                                MacListIcon(list: list, size: 11)
                                Text(list.name).font(MacTypography.rowMeta).lineLimit(1)
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Theme.bgSecondary, in: Capsule())
                        }
                        if chips.count > 2 {
                            Text("+\(chips.count - 2)")
                                .font(MacTypography.rowMeta)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Themed card so the row surface reflects the theme (Ocean = light card on cyan, Dark = raised
        // card on dark). Selection is a SUBTLE thin accent (b8d1ec16); hover a lighter wash (77225941).
        .background(MacSelectionStyle.fill(isSelected: isSelected, hovering: hovering),
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(MacSelectionStyle.borderColor(isSelected: isSelected, hovering: hovering),
                    lineWidth: MacSelectionStyle.borderWidth(isSelected: isSelected)))
        .onHover { h in withAnimation(.easeOut(duration: 0.1)) { hovering = h } }
        .padding(.leading, 8 + CGFloat(min(indent, 4)) * 16)   // per-level indent, capped at 4
        .padding(.trailing, 8)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}
#endif
