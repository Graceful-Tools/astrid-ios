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
    /// Whether this list decides membership by filter rather than by what is in it.
    @State private var isVirtual: Bool

    init(list: TaskList) {
        self.list = list
        _completion = State(initialValue: list.filterCompletion ?? "default")
        _priority   = State(initialValue: list.filterPriority ?? "all")
        _dueDate    = State(initialValue: list.filterDueDate ?? "all")
        _assignee   = State(initialValue: list.filterAssignee ?? "all")
        _assignedBy = State(initialValue: list.filterAssignedBy ?? "all")
        _repeatingFilter = State(initialValue: list.filterRepeating ?? "all")
        _sortBy     = State(initialValue: list.sortBy ?? "auto")
        _isVirtual  = State(initialValue: list.isVirtual ?? false)
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

            // Saved filter: converts THIS list, exactly as web's checkbox and iOS's toggle do.
            // It used to create a NEW list and copy the filters over, pre-filled with this list's
            // name — so you got two lists with the same name, one real, one virtual (0e09b224).
            Toggle(isOn: $isVirtual) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("lists.saved_filter", comment: ""))
                    Text(NSLocalizedString("list.smart_list_description", comment: ""))
                        .font(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .onChange(of: isVirtual) { _, on in setSavedFilter(on) }

            HStack {
                Button(NSLocalizedString("mac.clear_filters", comment: "")) {
                    // Clears every dimension the sheet offers — leaving repeating and assigned-by
                    // behind made "Clear filters" a half-truth (task 70d849f8).
                    completion = "default"; priority = "all"; dueDate = "all"; assignee = "all"
                    repeatingFilter = "all"; assignedBy = "all"
                    save()
                }
                .disabled(activeFilters == 0)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.bgPrimary)
    }

    /// How many of the SIX controls this sheet offers are set. Gates the save link and Clear,
    /// so all three agree about what "has a filter" means (task 70d849f8).
    private var activeFilters: Int {
        MacListFilter.activeCount(completion: completion, priority: priority, dueDate: dueDate,
                                  assignee: assignee, repeating: repeatingFilter,
                                  assignedBy: assignedBy)
    }

    /// Convert this list to a saved filter, or back (task 0e09b224).
    ///
    /// Reversible on purpose: no task moves either way, because `isVirtual` changes how
    /// membership is DECIDED, not what belongs to the list. Reverting leaves the filters in
    /// place rather than wiping a setup the user might be about to switch straight back on.
    private func setSavedFilter(_ on: Bool) {
        let updates = on
            ? MacListFilter.smartListUpdates(completion: completion, priority: priority,
                                             dueDate: dueDate, assignee: assignee, sortBy: sortBy,
                                             repeating: repeatingFilter, assignedBy: assignedBy)
            : MacListFilter.revertToNormalListUpdates()
        MacActions.perform(on ? "Save as Smart List" : "Convert to normal list") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id, updates: updates)
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
