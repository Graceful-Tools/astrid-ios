//  MacFilterSheet.swift
//  Astrid for Mac — native filter editor for a list (Task a2bf6ccb).
//
//  Previously Mac filters were READ-ONLY (the empty state told users to "adjust filters on iOS or
//  the web"). This writes the list's saved filter fields through the canonical service
//  (ListService.updateListAdvanced → optimistic + offline + server), and the SHARED
//  filterTasksForList immediately reflects them in the task list — same result as iOS/web.

#if os(macOS)
import SwiftUI

struct MacFilterSheet: View {
    let list: TaskList
    @Environment(\.dismiss) private var dismiss

    @State private var completion: String
    @State private var priority: String
    @State private var dueDate: String
    @State private var assignee: String
    @State private var assignedBy: String
    @State private var repeatingFilter: String
    @State private var sortBy: String
    @State private var showingSave = false
    @State private var smartListName = ""

    init(list: TaskList) {
        self.list = list
        _completion = State(initialValue: list.filterCompletion ?? "default")
        _priority   = State(initialValue: list.filterPriority ?? "all")
        _dueDate    = State(initialValue: list.filterDueDate ?? "all")
        _assignee   = State(initialValue: list.filterAssignee ?? "all")
        _assignedBy = State(initialValue: list.filterAssignedBy ?? "all")
        _repeatingFilter = State(initialValue: list.filterRepeating ?? "all")
        _sortBy     = State(initialValue: list.sortBy ?? "auto")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(format: NSLocalizedString("mac.filter_title", comment: ""), list.name)).font(.headline).foregroundStyle(Theme.textPrimary)

            Form {
                // Sort lives WITH the filters and is saved on the list, exactly like iOS — the old
                // Mac sort was a window-local override that never persisted or synced (2b886104).
                Section(NSLocalizedString("actions.sort", comment: "")) {
                    filterPicker(NSLocalizedString("lists.sort_order", comment: ""), selection: $sortBy, options: MacListFilter.sort)
                }
                Section(NSLocalizedString("lists.filters", comment: "")) {
                    filterPicker(NSLocalizedString("lists.task_completion", comment: ""), selection: $completion, options: MacListFilter.completion)
                    filterPicker(NSLocalizedString("tasks.priority", comment: ""), selection: $priority, options: MacListFilter.priority)
                    filterPicker(NSLocalizedString("tasks.due_date", comment: ""), selection: $dueDate, options: MacListFilter.dueDate)
                    filterPicker(NSLocalizedString("tasks.assignee", comment: ""), selection: $assignee, options: MacListFilter.assignee)
                    filterPicker(NSLocalizedString("lists.assigned_by", comment: ""), selection: $assignedBy, options: MacListFilter.assignedBy)
                    filterPicker(NSLocalizedString("lists.repeating", comment: ""), selection: $repeatingFilter, options: MacListFilter.repeating)
                }
            }
            .formStyle(.grouped).macThemedSurface()
            .frame(height: 360)

            // Save the current filters as a reusable Smart List (virtual list), like iOS/web.
            if showingSave {
                HStack {
                    TextField(NSLocalizedString("mac.smart_list_name", comment: ""), text: $smartListName).textFieldStyle(.roundedBorder)
                    Button(NSLocalizedString("actions.create", comment: "")) { saveSmartList() }
                        .buttonStyle(.borderedProminent)
                        .disabled(smartListName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    smartListName = list.name; showingSave = true
                } label: { Label(NSLocalizedString("filters.save_as_smart_list", comment: ""), systemImage: "star") }
                .buttonStyle(.link)
                .disabled(MacListFilter.activeCount(completion: completion, priority: priority,
                                                    dueDate: dueDate, assignee: assignee) == 0)
            }

            HStack {
                Button(NSLocalizedString("mac.clear_filters", comment: "")) {
                    completion = "default"; priority = "all"; dueDate = "all"; assignee = "all"
                    save()
                }
                .disabled(MacListFilter.activeCount(completion: completion, priority: priority,
                                                    dueDate: dueDate, assignee: assignee) == 0)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.bgPrimary)
    }

    /// Create a saved-filter (Smart) list from the current filters — mirrors iOS SaveFilterDialog.
    private func saveSmartList() {
        let name = smartListName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let updates = MacListFilter.smartListUpdates(completion: completion, priority: priority,
                                                     dueDate: dueDate, assignee: assignee,
                                                     sortBy: list.sortBy ?? "auto")
        dismiss()
        MacActions.perform("Save Smart List") {
            let newList = try await ListService.shared.createList(name: name, description: "Smart List", privacy: "PRIVATE")
            _ = try await ListService.shared.updateListAdvanced(listId: newList.id, updates: updates)
            _ = try? await ListService.shared.fetchLists()
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, options: [MacListFilter.Option]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { Text($0.label).tag($0.value) }
        }
        .onChange(of: selection.wrappedValue) { save() }
    }

    /// Persist sort + every filter field through the canonical service (offline-first + server),
    /// so a Mac change syncs to iOS/web exactly like an iOS change does.
    private func save() {
        let updates: [String: Any] = [
            "sortBy": sortBy,
            "filterCompletion": completion,
            "filterPriority": priority,
            "filterDueDate": dueDate,
            "filterAssignee": assignee,
            "filterAssignedBy": assignedBy,
            "filterRepeating": repeatingFilter,
        ]
        MacActions.perform("Update filters") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id, updates: updates)
        }
    }
}
#endif
