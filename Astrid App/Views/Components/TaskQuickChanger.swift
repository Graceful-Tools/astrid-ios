//  TaskQuickChanger.swift
//  The popover behind a task's leading control on a row or board card when a tap does not
//  complete — a board card, someone else's task, nobody's task (task 132d7b3f, AITD-375/382).
//
//  The detail screen has the same popover; this is it as a component, so "same behavior" is a
//  shared view rather than a promise three call sites have to keep independently.
//
//  SELF-CONTAINED ON PURPOSE. It takes a task and saves through `TaskService` itself, rather
//  than taking four bindings and four callbacks. A row has no edit state to bind to — the
//  detail's `editedPriority` exists because the detail is an editor — and inventing per-row
//  state just to feed this would be state that can go stale the moment the task syncs.
//
//  Completion goes through `TaskService.completeTask`, never `updateTask(completed:)`: that is
//  the only path that rolls a repeating task forward (ASTRID.md rule 2).

// iOS only: `PriorityButtonPicker` and `InlineAssigneePicker` are UIKit-flavoured iOS views.
// The Mac's equivalent is `MacQuickChanger`, which presents the same four choices through the
// Mac's own pickers. This file sits in a directory the Mac target also compiles, so without
// the guard the Mac build fails on views that do not exist there.
#if !os(macOS)
import SwiftUI

struct TaskQuickChanger: View {
    let task: Task
    /// Called once the user has picked something, so the presenter can dismiss.
    let onDismiss: () -> Void

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared

    @State private var priority: Task.Priority
    /// The assignee this popover has picked. Seeded from the task; the picker needs somewhere
    /// real to write, or its selection cannot move (task 1484ea4a).
    @State private var pickedAssigneeId: String?

    init(task: Task, onDismiss: @escaping () -> Void) {
        self.task = task
        self.onDismiss = onDismiss
        _priority = State(initialValue: task.priority)
        _pickedAssigneeId = State(initialValue: task.assigneeId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing16) {
            // Each choice dismisses straight away — you came here to set ONE thing, and
            // leaving it open makes you tap outside to confirm nothing happened (42013da7).
            PriorityButtonPicker(priority: $priority, onSave: { newPriority in
                _ = try await taskService.updateTask(taskId: task.id,
                                                     priority: newPriority.rawValue, task: task)
                await MainActor.run { onDismiss() }
            })

            InlineAssigneePicker(
                label: NSLocalizedString("tasks.assignee", comment: ""),
                // A real binding, not `.constant`: with a constant the picker's own selection
                // could never move, so the row you tapped did not become the selected one
                // (task 1484ea4a). The detail panel has always passed a real one.
                assigneeId: $pickedAssigneeId,
                taskListIds: task.listIds ?? [],
                taskId: task.id,
                availableLists: listService.lists,
                onSave: { newAssigneeId in
                    _ = try? await taskService.updateTask(taskId: task.id,
                                                          assigneeId: newAssigneeId ?? "", task: task)
                    await MainActor.run { onDismiss() }
                },
                showLabel: false,
                // This is a popover, so the member list scrolls inside a fixed window rather
                // than sizing the popover to the whole membership (AITD-391).
                boundsListHeight: true
            )

            Divider()

            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("board.project_state", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(Theme.textMuted)
                ProjectStateQuickPicker(task: task, onMoved: onDismiss)
            }

            Divider()

            // A task that is not yours — someone else's or nobody's — opens on the question
            // itself: the checkbox, then Complete (ADEV-79; ADEV-70, web ADEV-56). Reopening and
            // your own tasks never ask.
            if TaskLeadingControl.completionNeedsConfirmation(
                assigneeId: task.assigneeId,
                currentUserId: AuthManager.shared.currentUser?.id,
                completed: task.completed) {
                CompletionConfirmationPrompt(
                    assigneeLabel: CompletionConfirmation.assigneeLabel(for: task),
                    onCancel: { onDismiss() },
                    onConfirm: {
                        onDismiss()
                        complete()
                    })
            } else {
            Button {
                onDismiss()
                complete()
            } label: {
                Label(task.completed ? NSLocalizedString("mac.mark_incomplete", comment: "")
                                     : NSLocalizedString("tasks.complete_task", comment: ""),
                      systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle.fill")
                    .font(Theme.Typography.body())
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            }
        }
        .padding(Theme.spacing16)
        .frame(width: 280)
    }

    /// Completion goes through `completeTask`, never `updateTask(completed:)` — that is the only
    /// path that rolls a repeating task forward (ASTRID.md rule 2).
    private func complete() {
        _Concurrency.Task {
            _ = try? await taskService.completeTask(id: task.id,
                                                    completed: !task.completed, task: task)
        }
    }
}
#endif
