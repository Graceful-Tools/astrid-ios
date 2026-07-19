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
    let onToggle: () -> Void
    let onCommitEdit: () -> Void
    let onCancelEdit: () -> Void

    @ObservedObject private var listService = ListService.shared

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
            Button(action: onToggle) {
                MacTaskCheckbox(completed: task.completed, priority: task.priority, size: 20)
            }
            .buttonStyle(.plain)
            .help(task.completed ? "Mark incomplete" : "Mark complete")
            .accessibilityLabel(task.completed ? "Completed, mark incomplete" : "Not completed, mark complete")

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

            // Subtle assignee indicator (mirrors iOS surfacing an avatar for assigned tasks).
            if task.assigneeId != nil {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(Theme.accent)
                    .font(.system(size: 14))
                    .help("Assigned")
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
#endif
