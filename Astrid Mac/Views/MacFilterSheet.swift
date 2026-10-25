//  MacFilterSheet.swift
//  Astrid for Mac — native filter editor for a list (Task a2bf6ccb). Its own sheet went in
//  AITD-553; the editor is List Settings ▸ Filters, and these are its controls.
//
//  Previously Mac filters were READ-ONLY (the empty state told users to "adjust filters on iOS or
//  the web"). This writes the saved sort/filter fields through the canonical service
//  (ListService.updateListAdvanced → optimistic + offline + server), and the SHARED
//  astrid-core's rowsForList immediately reflects them in the task list — same result as iOS.
//
//  Those fields are the VIEWER's since AITD-394: the server keys them (userId, listId) and
//  overlays them onto the list payload on read. The wire contract is unchanged, so nothing here
//  had to move — but this sheet writes only view fields, and that is now load-bearing rather
//  than tidy. Adding a list-level field to its payload would make every filter change also
//  write that field for everybody.

#if os(macOS)
import SwiftUI

/// The sort and filter controls for one list.
///
/// THESE ARE NOT PERSONAL SETTINGS, however much they read like them: sort, the six filters,
/// "saved filter" and "show subtasks" are all columns on the shared list row, so changing one
/// changes it for every member — on Mac, iOS and Web alike. The tab that hosts this says so out
/// loud rather than implying a private view that does not exist (AITD-388).
struct MacListSortFiltersContent: View {
    let list: TaskList
    /// Whether the form has its Sort section. The List Settings window keeps it (the header's
    /// sort menu is the quick way, AITD-522).
    private let showsSort: Bool

    @State private var completion: String
    @State private var priority: String
    @State private var dueDate: String
    @State private var assignee: String
    @State private var assignedBy: String
    @State private var repeatingFilter: String
    @State private var sortBy: String
    /// Whether this list decides membership by filter rather than by what is in it.
    @State private var isVirtual: Bool
    /// Per-list inline subtasks (ba1deb9d). HERE, not in the edit sheet: it decides what the
    /// list RENDERS, which is the question every other control on this sheet answers. Web says
    /// the same thing in list-sort-and-filters.tsx, and iOS keeps it in Sort & Filters.
    @State private var showSubtasks: Bool

    init(list: TaskList, showsSort: Bool = true) {
        self.list = list
        self.showsSort = showsSort
        _completion = State(initialValue: list.filterCompletion ?? "default")
        _priority   = State(initialValue: list.filterPriority ?? "all")
        _dueDate    = State(initialValue: list.filterDueDate ?? "all")
        _assignee   = State(initialValue: list.filterAssignee ?? "all")
        _assignedBy = State(initialValue: list.filterAssignedBy ?? "all")
        _repeatingFilter = State(initialValue: list.filterRepeating ?? "all")
        _sortBy     = State(initialValue: list.sortBy ?? "auto")
        _isVirtual  = State(initialValue: list.isVirtual ?? false)
        _showSubtasks = State(initialValue: ListSubtaskVisibility.listShowsSubtasks(list.showSubtasks))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // A grid, not a scrolling Form (AITD-553: "make it so that the filter list doesn't
            // need to scroll"). It takes the height its rows need; the host decides what happens
            // on a screen too short for that.
            MacFilterGrid {
                // Sort lives WITH the filters and persists, exactly like iOS — the old Mac sort
                // was a window-local override that never persisted or synced (2b886104). It is
                // saved per-user against the list, not as a column of it (AITD-394).
                if showsSort {
                    MacFilterRows.header(NSLocalizedString("actions.sort", comment: ""))
                    filterPicker(NSLocalizedString("lists.sort_order", comment: ""), selection: $sortBy, options: MacListFilter.sort)
                }
                MacFilterRows.header(NSLocalizedString("lists.filters", comment: ""))
                filterPicker(NSLocalizedString("lists.task_completion", comment: ""), selection: $completion, options: MacListFilter.completion)
                filterPicker(NSLocalizedString("tasks.priority", comment: ""), selection: $priority, options: MacListFilter.priority)
                filterPicker(NSLocalizedString("tasks.due_date", comment: ""), selection: $dueDate, options: MacListFilter.dueDate)
                filterPicker(NSLocalizedString("tasks.assignee", comment: ""), selection: $assignee, options: MacListFilter.assignee)
                filterPicker(NSLocalizedString("lists.assigned_by", comment: ""), selection: $assignedBy, options: MacListFilter.assignedBy)
                filterPicker(NSLocalizedString("lists.repeating", comment: ""), selection: $repeatingFilter, options: MacListFilter.repeating)
            }

            // Saved filter: converts THIS list, exactly as web's checkbox and iOS's toggle do.
            // It used to create a NEW list and copy the filters over, pre-filled with this list's
            // name — so you got two lists with the same name, one real, one virtual (0e09b224).
            Toggle(isOn: $isVirtual) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("lists.saved_filter", comment: ""))
                    Text(NSLocalizedString("list.smart_list_description", comment: ""))
                        .macFont(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .onChange(of: isVirtual) { _, on in setSavedFilter(on) }

            Toggle(isOn: $showSubtasks) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("lists.show_subtasks", comment: ""))
                    Text(NSLocalizedString("lists.show_subtasks_footer", comment: ""))
                        .macFont(.caption).foregroundStyle(Theme.textMuted)
                }
            }
            .onChange(of: showSubtasks) { _, on in saveShowSubtasks(on) }

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
            }
        }
    }

    /// How many of the SIX controls this sheet offers are set. Gates the save link and Clear,
    /// so all three agree about what "has a filter" means (task 70d849f8).
    private var activeFilters: Int {
        MacListFilter.activeCount(completion: completion, priority: priority, dueDate: dueDate,
                                  assignee: assignee, repeating: repeatingFilter,
                                  assignedBy: assignedBy)
    }

    /// Only an actual change is sent — an unrelated edit must never carry a value that resets
    /// someone's toggle. Same guard iOS uses.
    private func saveShowSubtasks(_ on: Bool) {
        guard let value = ListSubtaskVisibility.payloadValue(original: list.showSubtasks,
                                                             edited: on) else { return }
        AppActions.perform("Update show subtasks") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id,
                                                                updates: ["showSubtasks": value])
        }
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
        AppActions.perform(on ? "Save as Smart List" : "Convert to normal list") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id, updates: updates)
        }
    }

    private func filterPicker(_ title: String, selection: Binding<String>, options: [MacListFilter.Option]) -> some View {
        MacFilterRows.row(title, selection: selection, options: options)
            .onChange(of: selection.wrappedValue) { save() }
    }

    /// Persist sort + every filter field through the canonical service (offline-first + server),
    /// so a Mac change syncs to iOS/web exactly like an iOS change does.
    private func save() {
        var updates: [String: Any] = [
            "filterCompletion": completion,
            "filterPriority": priority,
            "filterDueDate": dueDate,
            "filterAssignee": assignee,
            "filterAssignedBy": assignedBy,
            "filterRepeating": repeatingFilter,
        ]
        // Without its Sort section this form's `sortBy` is only the value it opened with, and the
        // header menu may have changed it since — so it must not write it back (AITD-522).
        if showsSort { updates["sortBy"] = sortBy }
        AppActions.perform("Update filters") {
            _ = try await ListService.shared.updateListAdvanced(listId: list.id, updates: updates)
        }
    }
}

/// The filter rows as a two-column grid that sizes to its content — label, then a menu picker —
/// on a themed card. Shared by List Settings' Filters tab and My Tasks' filter popover, so the
/// two cannot drift (AITD-553). It replaced a `Form`, which is a scroll view with a fixed frame:
/// six filters in 300pt scrolled.
struct MacFilterGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bgSecondary))
    }
}

/// The rows a `MacFilterGrid` holds.
enum MacFilterRows {
    /// A section label spanning both columns.
    static func header(_ title: String) -> some View {
        GridRow {
            Text(title).macFont(.caption).foregroundStyle(Theme.textMuted)
                .gridCellColumns(2)
        }
    }

    static func row(_ title: String, selection: Binding<String>,
                    options: [MacListFilter.Option]) -> some View {
        GridRow {
            Text(title).foregroundStyle(Theme.textPrimary)
                .gridColumnAlignment(.leading)
            Picker(title, selection: selection) {
                ForEach(options) { Text($0.label).tag($0.value) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
#endif
