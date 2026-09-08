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
    /// The task the move produced, handed back so a view holding its own snapshot can redraw
    /// (task AITD-352). The board does not need this — it reads from the observed `TaskService`
    /// — but `TaskDetailViewNew` keeps a `@State` copy taken when it opened, and without this
    /// the chips kept lighting the pre-move column and the buttons looked dead.
    var onTaskUpdated: ((Task) -> Void)? = nil

    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared

    /// Every state EXCEPT Done (task 7574067b). Done is what the Complete button below is
    /// for; offering it as a chip too gave the same action twice, and the chip was the one
    /// that never said it would finish the task.
    private var columns: [ProjectBoardColumn] {
        ProjectStatePicker.columns(from: getProjectBoardColumns(listService.lists))
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
                // The sequencing (and ASTRID.md rule 2 — completion only ever through
                // `completeTask`) lives in `ProjectStateMove`, shared rather than spelled here.
                let moved = try await ProjectStateMove.apply(
                    plan: plan,
                    update: { ids, role in
                        try await taskService.updateTask(taskId: task.id, listIds: ids,
                                                         task: task, statusRole: role)
                    },
                    complete: { flag in
                        try await taskService.completeTask(id: task.id, completed: flag, task: task)
                    }
                )
                // `updateTask` / `completeTask` return the OPTIMISTIC task with nothing awaited,
                // so this lands as fast as any other control in the detail view.
                if let moved { onTaskUpdated?(moved) }
            } catch {
                // The Outbox owns the retry; surfacing a failure here would be a second,
                // contradictory story about whether the move happened.
            }
        }
    }
}
