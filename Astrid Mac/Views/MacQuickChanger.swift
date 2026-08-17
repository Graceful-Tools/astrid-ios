//  MacQuickChanger.swift
//  Astrid for Mac — the popover behind a task's leading control, in project mode (task 132d7b3f).
//
//  Jon: "task box in rows and boards should also have same behavior as task box in task details
//  when in project mode."
//
//  The detail panel and the board card both reach this through `MacLeadingControlButton`. A
//  LIST row cannot: a `Button` inside a macOS `List` row never fires, because the cell's own
//  click handling swallows it (task 652edb22) — which is why rows draw their faces inline with
//  tap gestures instead. So the popover's CONTENTS live here, and both the button and the row
//  present the same view rather than each building its own.
//
//  Self-contained for the same reason `TaskQuickChanger` is on iOS: a row has no edit state to
//  bind to, and inventing per-row state to feed this would be state that goes stale the moment
//  the task syncs.

#if os(macOS)
import SwiftUI

struct MacQuickChanger: View {
    let task: Task
    let onDismiss: () -> Void

    @StateObject private var taskService = TaskService.shared
    @State private var priority: Task.Priority
    @State private var members: [ListMember] = []

    init(task: Task, onDismiss: @escaping () -> Void) {
        self.task = task
        self.onDismiss = onDismiss
        _priority = State(initialValue: task.priority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("tasks.priority", comment: ""))
                    .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                // Per-tap callback, NOT `.onChange(of:)`: watching the value swallows a tap
                // that picks the priority the task already has, and the popover sits there
                // looking dead (task a6cd1367).
                MacPriorityPicker(selection: $priority, onSelect: { newValue in
                    onDismiss()
                    MacActions.perform("Save priority") {
                        _ = try await taskService.updateTask(taskId: task.id,
                                                             priority: newValue.rawValue, task: task)
                    }
                })
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("tasks.assignee", comment: ""))
                    .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                MacAssigneePicker(
                    options: MacAssigneeOptions.build(members: members,
                                                      currentUserId: AuthManager.shared.userId,
                                                      taskAssignee: task.assignee),
                    selectedId: task.assigneeId,
                    priority: priority,
                    onSelect: { newId in
                        onDismiss()
                        MacActions.perform("Set assignee") {
                            _ = try await taskService.updateTask(taskId: task.id,
                                                                 assigneeId: newId ?? "", task: task)
                        }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("board.project_state", comment: ""))
                    .font(MacTypography.label).foregroundStyle(Theme.textMuted)
                MacProjectStateSection(task: task, onMoved: onDismiss)
            }

            Divider()

            Button {
                onDismiss()
                MacActions.perform("Toggle completion") {
                    // `completeTask`, never `updateTask(completed:)` — the only path that rolls
                    // a repeating task forward (ASTRID.md rule 2).
                    _ = try await taskService.completeTask(id: task.id,
                                                           completed: !task.completed, task: task)
                }
            } label: {
                Label(task.completed
                      ? NSLocalizedString("mac.mark_incomplete", comment: "")
                      : NSLocalizedString("tasks.complete_task", comment: ""),
                      systemImage: task.completed ? "arrow.uturn.backward" : "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .macPointingHand()
        }
        .padding(12)
        .frame(width: 240)
        .task(id: task.id) {
            guard let listId = task.listIds?.first else { return }
            try? await ListMemberService.shared.fetchMembers(listId: listId)
            members = ListMemberService.shared.membersByList[listId] ?? []
        }
    }
}
#endif
