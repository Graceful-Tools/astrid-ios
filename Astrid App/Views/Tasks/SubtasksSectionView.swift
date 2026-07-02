import SwiftUI

/// "Sub tasks" section in the task detail: lists the parent's subtasks with
/// completion checkboxes, and an inline add field. Completion routes through
/// `TaskService.completeTask` per subtask (canonical control point — repeating
/// subtasks roll forward correctly). Subtasks inherit the parent's lists.
struct SubtasksSectionView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    @StateObject private var taskService = TaskService.shared

    let parentTask: Task
    var isReadOnly: Bool = false

    @State private var newSubtaskTitle = ""
    @FocusState private var isAddFieldFocused: Bool

    private var effectiveTheme: String {
        themeMode == "auto" ? (colorScheme == .dark ? "dark" : "light") : themeMode
    }
    private var textPrimary: Color {
        effectiveTheme == "dark" ? Theme.Dark.textPrimary : Theme.textPrimary
    }
    private var textMuted: Color {
        effectiveTheme == "dark" ? Theme.Dark.textMuted : Theme.textMuted
    }

    private var subtasks: [Task] {
        taskService.tasks
            .filter { $0.parentTaskId == parentTask.id }
            .sorted { $0.createdAt ?? .distantPast < $1.createdAt ?? .distantPast }
    }

    var body: some View {
        // Hidden entirely for read-only viewers with no subtasks.
        if !(isReadOnly && subtasks.isEmpty) {
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                HStack(spacing: 6) {
                    Text(NSLocalizedString("task_detail.subtasks", comment: "Sub tasks"))
                        .font(Theme.Typography.subheadline())
                        .foregroundColor(textMuted)
                    if !subtasks.isEmpty {
                        Text("\(subtasks.filter(\.completed).count)/\(subtasks.count)")
                            .font(Theme.Typography.caption2())
                            .foregroundColor(textMuted)
                    }
                }

                ForEach(subtasks) { subtask in
                    HStack(spacing: Theme.spacing8) {
                        Button {
                            guard !isReadOnly else { return }
                            _Concurrency.Task {
                                // Canonical completion — never updateTask(completed:).
                                _ = try? await taskService.completeTask(
                                    id: subtask.id, completed: !subtask.completed, task: subtask)
                            }
                        } label: {
                            Image(systemName: subtask.completed ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundColor(subtask.completed ? Theme.accent : textMuted)
                        }
                        .buttonStyle(.plain)

                        Text(subtask.title)
                            .font(Theme.Typography.body())
                            .foregroundColor(subtask.completed ? textMuted : textPrimary)
                            .strikethrough(subtask.completed)
                            .lineLimit(2)

                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { TaskPresenter.shared.showTask(subtask) }
                }

                if !isReadOnly {
                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 20))
                            .foregroundColor(textMuted)
                        TextField(NSLocalizedString("task_detail.add_subtask", comment: "Add a sub task"),
                                  text: $newSubtaskTitle)
                            .font(Theme.Typography.body())
                            .focused($isAddFieldFocused)
                            .onSubmit(addSubtask)
                    }
                }
            }
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        newSubtaskTitle = ""
        _Concurrency.Task {
            // Subtasks inherit the parent's lists (spec: no independent membership).
            _ = try? await taskService.createTask(
                listIds: parentTask.listIds ?? [],
                title: title,
                parentTaskId: parentTask.id
            )
        }
        isAddFieldFocused = true
    }
}
