//  ProjectStateQuickPicker.swift
//  The board-column choice inside the quick changer (task 729a190e).
//
//  Jon: "when it is project tapping ... brings up the quick changer of assignee, priority, and
//  project state."
//
//  It does NOT invent a list of states. The columns come from `getProjectBoardColumns`, the same
//  derivation the board itself uses, so a renamed "Ready" reads the same in both places. The
//  write goes through `planProjectColumnMove`, so moving to Done from here completes the task
//  exactly as dragging it there does — including the un-complete on the way back out.
//
//  The Mac has its own view (`MacProjectStateSection`) because the two platforms' chip styling
//  and pointer affordances differ, but both call the SAME planner and the SAME column
//  derivation. The duplicated part is the styling; the rule is shared.

import SwiftUI

struct ProjectStateQuickPicker: View {
    let task: Task
    let onMoved: () -> Void

    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared

    private var columns: [ProjectBoardColumn] {
        getProjectBoardColumns(listService.lists)
    }

    private var currentColumnId: String {
        getTaskProjectColumnId(task, lists: listService.lists)
    }

    var body: some View {
        // Wrapping: a project can have more columns than fit on one line, and truncating
        // them hides states the task can be moved to.
        FlowLayout(spacing: Theme.spacing8, rowSpacing: Theme.spacing8) {
            ForEach(columns) { column in
                Button { move(to: column) } label: {
                    Text(column.name)
                        .font(Theme.Typography.caption1())
                        .padding(.horizontal, Theme.spacing12)
                        .padding(.vertical, Theme.spacing8)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                .fill(column.id == currentColumnId
                                      ? Theme.accent.opacity(0.22) : Theme.bgSecondary))
                        .foregroundColor(column.id == currentColumnId
                                         ? Theme.accent : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(column.name)
            }
        }
    }

    private func move(to column: ProjectBoardColumn) {
        onMoved()
        let plan = planProjectColumnMove(task: task, column: column, lists: listService.lists)
        _Concurrency.Task {
            do {
                switch plan {
                case .none:
                    break
                case .setLists(let ids, let role):
                    _ = try await taskService.updateTask(taskId: task.id, listIds: ids,
                                                         task: task, statusRole: role)
                case .complete(let ids, let role):
                    _ = try await taskService.updateTask(taskId: task.id, listIds: ids,
                                                         task: task, statusRole: role)
                    // Completion goes through `completeTask`, never `updateTask(completed:)` —
                    // that is the only path that rolls a repeating task forward
                    // (ASTRID.md rule 2).
                    _ = try await taskService.completeTask(id: task.id, completed: true, task: task)
                case .uncomplete(let ids, let role):
                    _ = try await taskService.completeTask(id: task.id, completed: false, task: task)
                    _ = try await taskService.updateTask(taskId: task.id, listIds: ids,
                                                         task: task, statusRole: role)
                }
            } catch {
                // The Outbox owns the retry; surfacing a failure here would be a second,
                // contradictory story about whether the move happened.
            }
        }
    }
}
