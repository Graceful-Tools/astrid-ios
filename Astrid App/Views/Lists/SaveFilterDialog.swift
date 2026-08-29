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
                    TextField("Smart List Name", text: $listName)
                        .focused($isNameFocused)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                } footer: {
                    Text(NSLocalizedString("save_filter.description", comment: "This will save your current filter settings as a Smart List"))
                        .font(Theme.Typography.caption1())
                }

                // Show active filters
                if hasActiveFilters {
                    Section("Active Filters") {
                        if currentFilters.sortBy != "auto" {
                            HStack {
                                Text("Sort")
                                Spacer()
                                Text(sortByLabel(currentFilters.sortBy))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        if currentFilters.filterCompletion != "default" {
                            HStack {
                                Text("Completion")
                                Spacer()
                                Text(completionLabel(currentFilters.filterCompletion))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        if currentFilters.filterPriority != "all" {
                            HStack {
                                Text("Priority")
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
                                Text("Who")
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
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
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

                print("✅ Created Smart List: \(listName) (ID: \(newList.id))")

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

                print("✅ Applied filter settings to Smart List")

                // Refresh lists to show updated smart list
                _ = try await listService.fetchLists()

                await MainActor.run {
                    onSaved()
                    dismiss()
                }
            } catch {
                print("❌ Failed to create Smart List: \(error)")
                await MainActor.run {
                    errorMessage = "Failed to save: \(error.localizedDescription)"
                    isSaving = false
                }
            }
        }
    }

    // MARK: - Label Helpers

    private func sortByLabel(_ value: String) -> String {
        switch value {
        case "auto": return "Auto"
        case "priority": return "Priority"
        case "due_date": return "Due Date"
        case "assignee": return "Who"
        case "completed": return "Completed First"
        case "incomplete": return "Incomplete First"
        case "completedAt": return "Recently Completed"
        case "manual": return "Manual"
        default: return value
        }
    }

    private func completionLabel(_ value: String) -> String {
        switch value {
        case "default": return "Default"
        case "all": return "All Tasks"
        case "completed": return "Completed"
        case "incomplete": return "Incomplete"
        default: return value
        }
    }

    private func priorityLabel(_ value: String) -> String {
        switch value {
        case "all": return "All Priorities"
        case "3": return "!!! Highest"
        case "2": return "!! High"
        case "1": return "! Medium"
        case "0": return "○ Low"
        default: return value
        }
    }

    private func dueDateLabel(_ value: String) -> String {
        switch value {
        case "all": return "All Dates"
        case "overdue": return "Overdue"
        case "today": return "Today"
        case "this_week": return "This Week"
        case "this_month": return "This Month"
        case "no_date": return "No Due Date"
        default: return value
        }
    }

    private func assigneeLabel(_ value: String) -> String {
        switch value {
        case "all": return "All"
        case "current_user": return "Only Me"
        case "not_current_user": return "Others"
        case "unassigned": return "Unassigned"
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
