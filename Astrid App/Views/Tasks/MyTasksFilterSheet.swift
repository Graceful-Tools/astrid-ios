import SwiftUI

/// Filter & Sort settings for "My Tasks" view
/// Syncs preferences across devices via server
struct MyTasksFilterSheet: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    @StateObject private var preferencesService = MyTasksPreferencesService.shared

    // Local state for UI bindings
    @State private var sortBy: String = "auto"
    @State private var filterCompletion: String = "default"
    @State private var filterDueDate: String = "all"
    @State private var filterPriority: String = "all"

    var body: some View {
        NavigationStack {
            Form {
                // Sort By
                Section(NSLocalizedString("lists.sort_by", comment: "")) {
                    Picker(NSLocalizedString("lists.sort_order", comment: ""), selection: $sortBy) {
                        Text(NSLocalizedString("lists.auto", comment: "")).tag("auto")
                        Text(NSLocalizedString("tasks.priority", comment: "")).tag("priority")
                        Text(NSLocalizedString("lists.due_date", comment: "")).tag("when")
                        Text(NSLocalizedString("tasks.who", comment: "")).tag("assignee")
                        Text(NSLocalizedString("tasks.completed", comment: "")).tag("completed")
                        Text(NSLocalizedString("tasks.incomplete", comment: "")).tag("incomplete")
                        Text(NSLocalizedString("lists.manual", comment: "")).tag("manual")
                    }
                    .onChange(of: sortBy) { _, newValue in
                        updatePreferences()
                    }
                }

                // Filters (consolidated section)
                Section(NSLocalizedString("lists.filters", comment: "")) {
                    // Task Completion
                    Picker(NSLocalizedString("lists.task_completion", comment: ""), selection: $filterCompletion) {
                        Text(NSLocalizedString("lists.incomplete_completed_recently", comment: "")).tag("default")
                        Text(NSLocalizedString("lists.all", comment: "")).tag("all")
                        Text(NSLocalizedString("tasks.completed", comment: "")).tag("completed")
                        Text(NSLocalizedString("tasks.incomplete", comment: "")).tag("incomplete")
                    }
                    .onChange(of: filterCompletion) { _, newValue in
                        AppLog.debug("🔧 [MyTasksFilterSheet] filterCompletion changed to: \(newValue)")
                        updatePreferences()
                    }

                    // Due Date
                    Picker(NSLocalizedString("tasks.due_date", comment: ""), selection: $filterDueDate) {
                        Text(NSLocalizedString("lists.all", comment: "")).tag("all")
                        Text(NSLocalizedString("lists.overdue", comment: "")).tag("overdue")
                        Text(NSLocalizedString("time.today", comment: "")).tag("today")
                        Text(NSLocalizedString("lists.this_week", comment: "")).tag("this_week")
                        Text(NSLocalizedString("lists.this_month", comment: "")).tag("this_month")
                        Text(NSLocalizedString("lists.no_date", comment: "")).tag("no_date")
                    }
                    .onChange(of: filterDueDate) { _, newValue in
                        updatePreferences()
                    }

                    // Priority
                    Picker(NSLocalizedString("tasks.priority", comment: ""), selection: $filterPriority) {
                        Text(NSLocalizedString("lists.all_priorities", comment: "")).tag("all")
                        Text(NSLocalizedString("lists.highest_priority", comment: "")).tag("3")
                        Text(NSLocalizedString("lists.high_priority", comment: "")).tag("2")
                        Text(NSLocalizedString("lists.medium_priority", comment: "")).tag("1")
                        Text(NSLocalizedString("lists.low_priority", comment: "")).tag("0")
                    }
                    .onChange(of: filterPriority) { _, newValue in
                        updatePreferences()
                    }
                }

                // Clear Filters
                Section {
                    Button(NSLocalizedString("lists.clear_all_filters", comment: "")) {
                        sortBy = "auto"
                        filterPriority = "all"
                        filterDueDate = "all"
                        filterCompletion = "default"
                        updatePreferences()
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            .scrollContentBackground(.hidden)
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .navigationTitle(NSLocalizedString("lists.sort_and_filters", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadPreferences()
            }
        }
    }

    // MARK: - Helper Methods

    private func loadPreferences() {
        sortBy = preferencesService.preferences.sortBy ?? "auto"
        filterCompletion = preferencesService.preferences.filterCompletion ?? "default"
        filterDueDate = preferencesService.preferences.filterDueDate ?? "all"

        // Convert [Int] to String for UI
        if let priorities = preferencesService.preferences.filterPriority, !priorities.isEmpty {
            // Use the first priority if multiple (for backwards compatibility)
            filterPriority = String(priorities[0])
        } else {
            filterPriority = "all"
        }

        AppLog.debug("📥 [MyTasksFilterSheet] Loaded preferences:")
        AppLog.debug("  - sortBy: \(sortBy)")
        AppLog.debug("  - filterCompletion: \(filterCompletion)")
        AppLog.debug("  - filterDueDate: \(filterDueDate)")
        AppLog.debug("  - filterPriority: \(filterPriority)")
    }

    private func updatePreferences() {
        // Convert String to [Int] for storage
        let priorityArray: [Int] = {
            if filterPriority == "all" {
                return []
            } else if let priority = Int(filterPriority) {
                return [priority]
            } else {
                return []
            }
        }()

        let updated = MyTasksPreferences(
            filterPriority: priorityArray,
            filterAssignee: preferencesService.preferences.filterAssignee,
            filterDueDate: filterDueDate,
            filterCompletion: filterCompletion,
            sortBy: sortBy
        )

        AppLog.debug("📤 [MyTasksFilterSheet] Updating preferences:")
        AppLog.debug("  - sortBy: \(sortBy)")
        AppLog.debug("  - filterCompletion: \(filterCompletion)")
        AppLog.debug("  - filterDueDate: \(filterDueDate)")
        AppLog.debug("  - filterPriority: \(filterPriority) -> \(priorityArray)")

        _Concurrency.Task {
            await preferencesService.updatePreferences(updated)
        }
    }

}

#Preview {
    MyTasksFilterSheet()
}
