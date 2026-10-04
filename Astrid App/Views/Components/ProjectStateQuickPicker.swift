//  ProjectStateQuickPicker.swift
//  The board-column choice inside the quick changer (task 729a190e).
//
//  Jon: "when it is project tapping ... brings up the quick changer of assignee, priority, and
//  project state."
//
//  It does NOT invent a list of states. The columns are the core's `taskStatusOptions` — the
//  task's own board, named as the board names them, never Done (CONTRACTS D46) — and the write is
//  the core's move (`TaskService.moveToBoardColumn`), so moving here does exactly what dragging
//  the card does, including the un-complete on the way out of Done (D45).
//
//  The Mac has its own view (`MacProjectStateSection`) because the two platforms' chip styling
//  and pointer affordances differ, but both read the SAME answer and make the SAME move. The
//  duplicated part is the styling; the rule is the core's.

import SwiftUI

struct ProjectStateQuickPicker: View {
    let task: Task
    let onMoved: () -> Void
    /// The task the move produced, handed back so a view holding its own snapshot can redraw
    /// (task AITD-352). The board does not need this — it reads from the observed `TaskService`
    /// — but `TaskDetailViewNew` keeps a `@State` copy taken when it opened, and without this
    /// the chips kept lighting the pre-move column and the buttons looked dead.
    var onTaskUpdated: ((Task) -> Void)? = nil

    /// The task's columns and which one it is in, from the core (AITD-461). Shared, so a picker
    /// opened again draws its last answer at once while the core is asked again.
    @ObservedObject private var options = TaskStatusOptions.shared

    private var answer: TaskStatusOptions.Answer? { options.answers[task.id] }

    private var columns: [ProjectBoardColumn] {
        answer?.columns.map(\.column) ?? []
    }

    private var currentColumnId: String? { answer?.current }

    /// What the core reads to answer: asked again whenever the task moves.
    private var askKey: String {
        "\(task.id)|\(task.statusRole ?? "")|\(task.completed)|\(task.listIds ?? [])"
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
        .task(id: askKey) { await options.refresh(task.id) }
    }

    private func move(to column: ProjectBoardColumn) {
        onMoved()
        _Concurrency.Task {
            do {
                // The task's own board, the core's move: nothing when it is already there,
                // completion only ever through the completion service (ASTRID.md rule 2).
                let moved = try await TaskService.shared.moveToBoardColumn(taskId: task.id,
                                                                            columnId: column.id)
                // The OPTIMISTIC task, with nothing awaited on the network, so this lands as fast
                // as any other control in the detail view.
                onTaskUpdated?(moved)
                await options.refresh(task.id)
            } catch {
                // The Outbox owns the retry; surfacing a failure here would be a second,
                // contradictory story about whether the move happened.
            }
        }
    }
}
