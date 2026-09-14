import SwiftUI

/// Dialog for saving current filter settings as a Smart List (virtual list)
struct SaveFilterDialog: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared

    let currentFilters: FilterSettings
    let onSaved: () -> Void

    @State private var listName = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isNameFocused: Bool

    struct FilterSettings {
        let sortBy: String
        let filterCompletion: String
        let filterPriority: String
        let filterDueDate: String
        let filterAssignee: String
        let filterRepeating: String
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(NSLocalizedString("mac.smart_list_name", comment: ""), text: $listName)
                        .focused($isNameFocused)
                        .autocorrectionDisabled()
                } header: {
                    Text(NSLocalizedString("filters.name", comment: ""))
                } footer: {
                    Text(NSLocalizedString("save_filter.description", comment: "This will save your current filter settings as a Smart List"))
                        .font(Theme.Typography.caption1())
                }

                // Show active filters
                if hasActiveFilters {
                    Section(NSLocalizedString("filters.active_filters", comment: "")) {
                        if currentFilters.sortBy != "auto" {
                            HStack {
                                Text(NSLocalizedString("filters.sort", comment: ""))
                                Spacer()
                                Text(sortByLabel(currentFilters.sortBy))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        if currentFilters.filterCompletion != "default" {
                            HStack {
                                Text(NSLocalizedString("filters.completion_status", comment: ""))
                                Spacer()
                                Text(completionLabel(currentFilters.filterCompletion))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        if currentFilters.filterPriority != "all" {
                            HStack {
                                Text(NSLocalizedString("tasks.priority", comment: ""))
                                Spacer()
                                Text(priorityLabel(currentFilters.filterPriority))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        if currentFilters.filterDueDate != "all" {
                            HStack {
                                Text(NSLocalizedString("save_filter.due_date", comment: "Due Date"))
                                Spacer()
                                Text(dueDateLabel(currentFilters.filterDueDate))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        if currentFilters.filterAssignee != "all" {
                            HStack {
                                Text(NSLocalizedString("filters.who", comment: ""))
                                Spacer()
                                Text(assigneeLabel(currentFilters.filterAssignee))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(Theme.Typography.caption1())
                    }
                }
            }
            .navigationTitle(NSLocalizedString("save_filter.title", comment: "Save as Smart List"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("actions.save", comment: "")) {
                        saveSmartList()
                    }
                    .disabled(listName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                isNameFocused = true
            }
        }
    }

    private var hasActiveFilters: Bool {
        return currentFilters.sortBy != "auto"
            || currentFilters.filterCompletion != "default"
            || currentFilters.filterPriority != "all"
            || currentFilters.filterDueDate != "all"
            || currentFilters.filterAssignee != "all"
            || currentFilters.filterRepeating != "all"
    }

    private func saveSmartList() {
        guard !listName.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        isSaving = true
        errorMessage = nil

        _Concurrency.Task {
            do {
                // Step 1: Create list
                let newList = try await listService.createList(
                    name: listName.trimmingCharacters(in: .whitespaces),
                    description: "Smart List",
                    privacy: "PRIVATE"
                )

                AppLog.debug("✅ Created Smart List: \(listName) (ID: \(newList.id))")

                // Step 2: Update with filter settings and isVirtual flag
                let updates: [String: Any] = [
                    "isVirtual": true,
                    "sortBy": currentFilters.sortBy,
                    "filterCompletion": currentFilters.filterCompletion,
                    "filterPriority": currentFilters.filterPriority,
                    "filterDueDate": currentFilters.filterDueDate,
                    "filterAssignee": currentFilters.filterAssignee,
                    "filterRepeating": currentFilters.filterRepeating
                ]

                _ = try await listService.updateListAdvanced(
                    listId: newList.id,
                    updates: updates
                )

                AppLog.debug("✅ Applied filter settings to Smart List")

                // Refresh lists to show updated smart list
                _ = try await listService.fetchLists()

                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                AppLog.debug("❌ Failed to create Smart List: \(error)")
                await MainActor.run {
                    errorMessage = String(format: NSLocalizedString("filters.save_failed", comment: ""), error.localizedDescription)
                    isSaving = false
                }
            }
        }
    }

    // MARK: - Label Helpers

    private func sortByLabel(_ value: String) -> String {
        switch value {
        case "auto": return NSLocalizedString("filters.auto", comment: "")
        case "priority": return NSLocalizedString("tasks.priority", comment: "")
        case "due_date": return NSLocalizedString("save_filter.due_date", comment: "")
        case "assignee": return NSLocalizedString("filters.who", comment: "")
        case "completed": return NSLocalizedString("filters.sort_completed_first", comment: "")
        case "incomplete": return NSLocalizedString("filters.sort_incomplete_first", comment: "")
        case "completedAt": return NSLocalizedString("lists.recently_completed", comment: "")
        case "manual": return NSLocalizedString("filters.manual", comment: "")
        default: return value
        }
    }

    private func completionLabel(_ value: String) -> String {
        switch value {
        case "default": return NSLocalizedString("filters.default", comment: "")
        case "all": return NSLocalizedString("filters.all_tasks", comment: "")
        case "completed": return NSLocalizedString("tasks.completed", comment: "")
        case "incomplete": return NSLocalizedString("tasks.incomplete", comment: "")
        default: return value
        }
    }

    private func priorityLabel(_ value: String) -> String {
        switch value {
        case "all": return NSLocalizedString("filters.all_priorities", comment: "")
        case "3": return "!!! Highest"
        case "2": return "!! High"
        case "1": return "! Medium"
        case "0": return "○ Low"
        default: return value
        }
    }

    private func dueDateLabel(_ value: String) -> String {
        switch value {
        case "all": return NSLocalizedString("filters.all_dates", comment: "")
        case "overdue": return NSLocalizedString("tasks.overdue", comment: "")
        case "today": return NSLocalizedString("time.today", comment: "")
        case "this_week": return NSLocalizedString("filters.this_week", comment: "")
        case "this_month": return NSLocalizedString("filters.this_month", comment: "")
        case "no_date": return NSLocalizedString("filters.no_due_date", comment: "")
        default: return value
        }
    }

    private func assigneeLabel(_ value: String) -> String {
        switch value {
        case "all": return NSLocalizedString("filters.all", comment: "")
        case "current_user": return NSLocalizedString("filters.me", comment: "")
        case "not_current_user": return NSLocalizedString("filters.not_me", comment: "")
        case "unassigned": return NSLocalizedString("filters.unassigned", comment: "")
        default: return value // Could be a member ID
        }
    }
}

#Preview {
    SaveFilterDialog(
        currentFilters: SaveFilterDialog.FilterSettings(
            sortBy: "priority",
            filterCompletion: "incomplete",
            filterPriority: "all",
            filterDueDate: "today",
            filterAssignee: "current_user",
            filterRepeating: "all"
        ),
        onSaved: {}
    )
}
