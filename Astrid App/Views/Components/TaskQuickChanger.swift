//  TaskQuickChanger.swift
//  The popover behind a task's leading control, in project mode (task 132d7b3f).
//
//  Jon: "task box in rows and boards should also have same behavior as task box in task details
//  when in project mode."
//
//  The detail screen already had this popover; rows and boards did not, so the same control
//  meant one thing in one place and another everywhere else. This is that popover as a
//  component, so "same behavior" is a shared view rather than a promise three call sites have
//  to keep independently.
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
    /// Confirming completion of a task that belongs to someone else (AITD-375).
    @State private var showingCompleteForAssigneePrompt = false

    /// Does finishing this one need asking first? Yes when it is not yours — the same rule the
    /// detail panel and the Mac use, so one task cannot answer it three ways.
    private var needsCompletionConfirmation: Bool {
        TaskLeadingControl.completionNeedsConfirmation(
            assigneeId: task.assigneeId,
            currentUserId: AuthManager.shared.currentUser?.id)
    }

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
                showLabel: false
            )

            Divider()

            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("board.project_state", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(Theme.textMuted)
                ProjectStateQuickPicker(task: task, onMoved: onDismiss)
            }

            Divider()

            Button {
                // Not yours? Ask first (AITD-375). This popover is what a row now offers instead
                // of completing another person's task outright, so the confirmation is the whole
                // point of routing through it.
                if needsCompletionConfirmation {
                    showingCompleteForAssigneePrompt = true
                    return
                }
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
        .padding(Theme.spacing16)
        .frame(width: 280)
        // Names the assignee: a dialog asking about "this task" over an unlabelled photo is the
        // blind confirm that teaches people to accept without reading.
        .confirmationDialog(NSLocalizedString("tasks.confirm_complete_title", comment: ""),
                            isPresented: $showingCompleteForAssigneePrompt,
                            titleVisibility: .visible) {
            Button(NSLocalizedString("tasks.complete_task", comment: "")) {
                onDismiss()
                complete()
            }
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
        } message: {
            Text(String(format: NSLocalizedString("tasks.confirm_complete_assigned", comment: ""),
                        assigneeDisplayName))
        }
    }

    /// Who the confirmation names. Resolved through the SHARED resolver, so the dialog names the
    /// person whose photo was actually tapped.
    private var assigneeDisplayName: String {
        AssigneeResolver.resolve(id: task.assigneeId, members: [], taskAssignee: task.assignee,
                                 agents: AIAgentCache.shared.load() ?? [])?.displayName
            ?? NSLocalizedString("assignee.unassigned", comment: "")
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
