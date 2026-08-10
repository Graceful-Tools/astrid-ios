import SwiftUI

/// Task action buttons: Copy, Share, Delete
struct TaskActionsView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let task: Task
    var currentListId: String? = nil  // Pass current list context for copy defaults

    @State private var showingCopySheet = false
    @State private var showingShareModal = false
    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: Theme.spacing12) {
            // Copy Task
            Button {
                showingCopySheet = true
            } label: {
                HStack {
                    Image(systemName: "doc.on.doc")
                    Text(NSLocalizedString("tasks.copy_task", comment: ""))
                }
                .font(Theme.Typography.body())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingCopySheet) {
                CopyTaskView(task: task, currentListId: currentListId)
            }

            // Share Task
            Button {
                showingShareModal = true
            } label: {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text(NSLocalizedString("tasks.share_task", comment: ""))
                }
                .font(Theme.Typography.body())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingShareModal) {
                ShareTaskView(task: task)
            }

            // Move out of parent task — iOS's route to the promotion the Mac offers by dragging
            // onto a drop strip (task 2ed0d0de). iOS has no task drag-and-drop outside the Board,
            // so the same decision is reached through an action rather than a gesture; the rule
            // for WHETHER it is offered is the shared one, so the platforms cannot disagree.
            if SubtaskPromotion.canPromoteToTopLevel(task) {
                Button {
                    moveOutOfParent()
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.left")
                        Text(NSLocalizedString("subtasks.move_out_of_parent", comment: ""))
                    }
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .buttonStyle(.plain)
            }

            // Delete Task
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text(NSLocalizedString("tasks.delete_task", comment: ""))
                }
                .font(Theme.Typography.body())
                .foregroundColor(Theme.error)
                .frame(maxWidth: .infinity)
                .padding(Theme.spacing12)
                .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
            }
            .buttonStyle(.plain)
            .confirmationDialog(
                NSLocalizedString("tasks.delete_confirm", comment: ""),
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                    _Concurrency.Task {
                        try? await TaskService.shared.deleteTask(id: task.id, task: task)
                        dismiss()
                    }
                }
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) { }
            }
        }
    }

    /// Cut the link to the parent, leaving this task's own children nested under it. The
    /// decision is `SubtaskPromotion`'s, shared with the Mac and with web, so a task that can
    /// be promoted on one platform can be promoted on all of them.
    private func moveOutOfParent() {
        guard let promotion = SubtaskPromotion.resolvePromotion(task) else { return }
        _Concurrency.Task {
            // Optimistic in TaskService, which rolls back on failure — the same path the
            // Mac's drop uses.
            _ = try? await TaskService.shared.updateTask(
                taskId: promotion.taskId,
                task: task,
                parentTaskId: SubtaskPromotion.clearParentValue)
            await MainActor.run { dismiss() }
        }
    }
}

// MARK: - Copy Task View

struct CopyTaskView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    let task: Task
    let currentListId: String?
    @StateObject private var listService = ListService.shared

    @State private var selectedListId: String?
    @State private var includeComments = false
    @State private var isCopying = false
    @State private var errorMessage: String?

    init(task: Task, currentListId: String? = nil) {
        self.task = task
        self.currentListId = currentListId

        // Set default based on context
        if let currentListId = currentListId, currentListId != "my-tasks" {
            // Default to current list
            _selectedListId = State(initialValue: currentListId)
        } else {
            // In "my tasks" or no context - default to "My Tasks (only)" (empty)
            _selectedListId = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(Theme.Typography.caption1())
                    }
                }

                Section(header: Text(NSLocalizedString("lists.copy_to_list", comment: ""))) {
                    Picker(NSLocalizedString("lists.target_list", comment: ""), selection: $selectedListId) {
                        // "My Tasks (only)" option (no specific list)
                        Text(NSLocalizedString("lists.my_tasks_only", comment: "")).tag("" as String?)

                        // Filter out virtual lists (Saved Filters)
                        // Note: Use simple color dot instead of ListImageView because
                        // SwiftUI Pickers don't handle async images properly
                        ForEach(listService.lists.filter { $0.isVirtual != true }) { list in
                            HStack {
                                Circle()
                                    .fill(Color(hex: list.displayColor) ?? Theme.accent)
                                    .frame(width: 12, height: 12)
                                Text(list.name)
                            }
                            .tag(list.id as String?)
                        }
                    }
                }

                Section {
                    Toggle(NSLocalizedString("lists.include_comments", comment: ""), isOn: $includeComments)
                }

                Section {
                    Button {
                        _Concurrency.Task {
                            await copyTask()
                        }
                    } label: {
                        if isCopying {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text(NSLocalizedString("tasks.copy_task", comment: ""))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(isCopying)  // Only disable while copying, not when no list selected
                }
            }
            .navigationTitle(NSLocalizedString("tasks.copy_task", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Cut the link to the parent, leaving this task's own children nested under it. The
    /// decision is `SubtaskPromotion`'s, shared with the Mac and with web, so a task that can
    /// be promoted on one platform can be promoted on all of them.
    private func moveOutOfParent() {
        guard let promotion = SubtaskPromotion.resolvePromotion(task) else { return }
        _Concurrency.Task {
            do {
                _ = try await TaskService.shared.updateTask(
                    taskId: promotion.taskId,
                    task: task,
                    parentTaskId: SubtaskPromotion.clearParentValue)
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription }
            }
        }
    }

    private func copyTask() async {
        errorMessage = nil
        isCopying = true
        defer { isCopying = false }

        do {
            // Determine target list ID (nil if "Not in a list" selected)
            let targetListId: String? = (selectedListId?.isEmpty == false) ? selectedListId : nil

            // Copy task using the API endpoint
            _ = try await TaskService.shared.copyTask(
                id: task.id,
                targetListId: targetListId,
                includeComments: includeComments,
                preserveDueDate: true,  // Preserve due date by default
                preserveAssignee: true   // Preserve assignee by default
            )

            print("✅ Copied task with comments: \(includeComments)")

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Failed to copy task: \(error)")
        }
    }
}

// MARK: - Preview

#Preview {
    TaskActionsView(
        task: Task(
            id: "1",
            title: "Sample Task",
            description: "This is a sample task",
            creatorId: "user1",
            isAllDay: false,
            repeating: .never,
            priority: .high,
            isPrivate: false,
            completed: false
        )
    )
    .padding()
    .background(Theme.bgPrimary)
}
