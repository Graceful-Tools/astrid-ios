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

    init(task: Task, onDismiss: @escaping () -> Void) {
        self.task = task
        self.onDismiss = onDismiss
        _priority = State(initialValue: task.priority)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("tasks.priority", comment: ""))
                    .macFont(MacTypography.label).foregroundStyle(Theme.textMuted)
                // Per-tap callback, NOT `.onChange(of:)`: watching the value swallows a tap
                // that picks the priority the task already has, and the popover sits there
                // looking dead (task a6cd1367).
                MacPriorityPicker(selection: $priority, onSelect: { newValue in
                    onDismiss()
                    AppActions.perform("Save priority") {
                        try await MacQuickChangerWrite.priority(newValue).apply(to: taskService, task: task)
                    }
                })
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("tasks.assignee", comment: ""))
                    .macFont(MacTypography.label).foregroundStyle(Theme.textMuted)
                MacAssigneePicker(
                    task: task,
                    priority: priority,
                    onSelect: { newId in
                        onDismiss()
                        AppActions.perform("Set assignee") {
                            try await MacQuickChangerWrite.assignee(newId).apply(to: taskService, task: task)
                        }
                    }
                )
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(NSLocalizedString("board.project_state", comment: ""))
                    .macFont(MacTypography.label).foregroundStyle(Theme.textMuted)
                MacProjectStateSection(task: task, onMoved: onDismiss)
            }

            Divider()

            Button {
                onDismiss()
                AppActions.perform("Toggle completion") {
                    try await MacQuickChangerWrite.toggleCompletion.apply(to: taskService, task: task)
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
            // Refreshes the roster the core answers the assignee picker from.
            try? await ListMemberService.shared.fetchMembers(listId: listId)
        }
    }
}
/// What each control in the quick changer writes, and through which call (AITD-540).
///
/// Completion goes through `completeTask`, never `updateTask(completed:)` — the only path that
/// rolls a repeating task forward (ASTRID.md rule 2). Clearing the assignee sends "", which the
/// service reads as unassigned.
enum MacQuickChangerWrite: Equatable {
    case priority(Task.Priority)
    case assignee(String?)
    case toggleCompletion

    @MainActor
    func apply(to writer: MacTaskWriting, task: Task) async throws {
        switch self {
        case .priority(let priority): try await writer.writePriority(priority.rawValue, of: task)
        case .assignee(let id): try await writer.writeAssignee(id ?? "", of: task)
        case .toggleCompletion: try await writer.writeCompletion(!task.completed, of: task)
        }
    }
}

/// The three task writes a quick change can make. `TaskService` in the app; a recorder in tests.
@MainActor
protocol MacTaskWriting {
    func writePriority(_ priority: Int, of task: Task) async throws
    func writeAssignee(_ assigneeId: String, of task: Task) async throws
    func writeCompletion(_ completed: Bool, of task: Task) async throws
}

extension TaskService: MacTaskWriting {
    func writePriority(_ priority: Int, of task: Task) async throws {
        _ = try await updateTask(taskId: task.id, priority: priority, task: task)
    }
    func writeAssignee(_ assigneeId: String, of task: Task) async throws {
        _ = try await updateTask(taskId: task.id, assigneeId: assigneeId, task: task)
    }
    func writeCompletion(_ completed: Bool, of task: Task) async throws {
        _ = try await completeTask(id: task.id, completed: completed, task: task)
    }
}
#endif
