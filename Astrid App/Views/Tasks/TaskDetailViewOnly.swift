import SwiftUI

/// View-only task detail for public lists (matching web's task-detail-viewonly.tsx)
/// Shows task information in a read-only format with no edit affordances
struct TaskDetailViewOnly: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @State private var task: Task
    @StateObject private var taskService = TaskService.shared
    @State private var showingCopySheet = false
    @State private var showTimer = false

    init(task: Task) {
        self._task = State(initialValue: task)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.spacing24) {
                // Title (static text, not editable - no checkbox for view-only)
                HStack(alignment: .center, spacing: Theme.spacing12) {
                    Text(task.title)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .strikethrough(task.completed)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.spacing12)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                }
                .padding(.horizontal, Theme.spacing16)
                .padding(.top, Theme.spacing16)

                Divider()
                    .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                // Created By - always show creator for public list tasks
                if let creator = task.creator {
                    ViewOnlyTwoColumnRow(label: "Created By") {
                        HStack(spacing: Theme.spacing8) {
                            // Creator avatar
                            CachedAsyncImage(url: creator.image.flatMap { URL(string: $0) }) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                ZStack {
                                    Circle()
                                        .fill(Theme.accent)
                                    Text(creator.name?.prefix(1).uppercased() ?? creator.email?.prefix(1).uppercased() ?? "?")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(Theme.accentText)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .clipShape(Circle())

                            Text(creator.displayName)
                                .font(Theme.Typography.body())
                                .foregroundColor(.blue)
                        }
                    }
                }

                // When (due date) - only show if set
                if let date = task.dueDateTime {
                    ViewOnlyTwoColumnRow(label: "Date") {
                        HStack(spacing: Theme.spacing8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14))
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                            Text(date, style: .date)
                                .font(Theme.Typography.body())
                                .foregroundColor(.blue)

                            // Show time if this is a timed task (not all-day)
                            if !task.isAllDay {
                                Image(systemName: "clock")
                                    .font(.system(size: 14))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                                Text(date, style: .time)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }

                // Repeat (only show if set)
                if let repeating = task.repeating, repeating != .never {
                    ViewOnlyTwoColumnRow(label: "Repeat") {
                        Text(repeating.rawValue.capitalized)
                            .font(Theme.Typography.body())
                            .foregroundColor(.blue)
                    }
                }

                // Priority - only show if date is set (matching web behavior)
                if task.dueDateTime != nil {
                    ViewOnlyTwoColumnRow(label: "Priority") {
                        HStack(spacing: Theme.spacing8) {
                            // Single button showing current priority
                            ZStack {
                                RoundedRectangle(cornerRadius: Theme.radiusSmall)
                                    .fill(priorityColor(task.priority))
                                    .frame(width: 40, height: 40)

                                Text(prioritySymbol(task.priority))
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                }

                // Description - only show if not empty
                if !task.description.isEmpty {
                    ViewOnlyTwoColumnRow(label: "Description") {
                        Text(task.description)
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                TaskAttachmentSectionView(task: task)

                // Comments Section (view-only)
                CommentSectionViewEnhanced(taskId: task.id)
                    .padding(.horizontal, Theme.spacing16)

                // Timer Button
                VStack(spacing: Theme.spacing8) {
                    Button(action: { showTimer = true }) {
                        HStack {
                            Image(systemName: "timer")
                            Text("Timer")
                                .font(.system(size: 17, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.spacing16)
                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                                .stroke(colorScheme == .dark ? Theme.Dark.border : Theme.border, lineWidth: 1)
                        )
                    }

                    if let lastTimerValue = task.lastTimerValue {
                        Text(String(format: NSLocalizedString("task_edit.last_timer", comment: "Last timer value"), lastTimerValue))
                            .font(.system(size: 14))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, Theme.spacing16)
                .padding(.top, Theme.spacing8)

                // Copy button at bottom
                Button(action: { showingCopySheet = true }) {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text(NSLocalizedString("task_edit.copy_to_lists", comment: "Copy to My Lists"))
                    }
                    .font(Theme.Typography.body())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Theme.accent)
                    .cornerRadius(Theme.radiusMedium)
                }
                .padding(.horizontal, Theme.spacing16)

                Spacer().frame(height: Theme.spacing24)
            }
        }
        .refreshable {
            await refreshTaskDetails()
        }
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
        .navigationTitle(NSLocalizedString("tasks.task_details", comment: "Task Details"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingCopySheet) {
            // Pass nil for currentListId since this is a public list task
            // User should choose where to copy it (defaults to "Not in a list")
            CopyTaskView(task: task, currentListId: nil)
        }
        .fullScreenCover(isPresented: $showTimer) {
            TaskTimerView(task: $task, onUpdate: { updatedTask in
                self.task = updatedTask
            })
        }
    }

    // MARK: - Helpers

    private func refreshTaskDetails() async {
        do {
            // Fetch fresh task data from the API with force refresh
            let freshTask = try await taskService.fetchTask(id: task.id, forceRefresh: true)

            // Update the task state with fresh data
            await MainActor.run {
                task = freshTask
            }

            // Reload comments using CommentService with force refresh
            _ = try? await CommentService.shared.fetchComments(taskId: task.id, useCache: false)
        } catch {
            // Silent failure - just fail gracefully if offline
            print("⚠️ [TaskDetailViewOnly] Failed to refresh task details: \(error)")
        }
    }

    private func priorityColor(_ priority: Task.Priority) -> Color {
        switch priority {
        case .none:
            return .gray
        case .low:
            return .blue
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }

    private func prioritySymbol(_ priority: Task.Priority) -> String {
        switch priority {
        case .none:
            return "○"
        case .low:
            return "!"
        case .medium:
            return "!!"
        case .high:
            return "!!!"
        }
    }
}

// MARK: - Two Column Row Helper (View-Only Version)

private struct ViewOnlyTwoColumnRow<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing16) {
            Text(label)
                .font(Theme.Typography.caption1())
                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                .frame(width: 100, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.spacing16)
    }
}

#Preview {
    NavigationStack {
        TaskDetailViewOnly(task: Task(
            id: "1",
            title: "Sample Public Task",
            description: "This is a read-only task from a public list",
            assigneeId: "user1",
            assignee: User(id: "user1", email: "john@example.com", name: "John Doe"),
            creatorId: nil,
            creator: nil,
            dueDateTime: Date(),
            isAllDay: true,
            reminderTime: nil,
            reminderSent: nil,
            reminderType: nil,
            repeating: .never,
            repeatingData: nil,
            priority: .high,
            lists: nil,
            listIds: ["list1"],
            isPrivate: false,
            completed: false,
            attachments: nil,
            comments: nil,
            createdAt: Date(),
            updatedAt: Date(),
            originalTaskId: nil,
            sourceListId: nil
        ))
    }
}
