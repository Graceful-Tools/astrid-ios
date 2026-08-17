//  MacMyTasksFilterSheet.swift
//  Astrid for Mac — filters for the virtual "My Tasks" view (task ebdf94a1).
//
//  Jon: "add filters to My Tasks just like they are in iOS."
//
//  iOS has offered these three for a while (MyTasksFilterSheet) and they are SYNCED, so a filter
//  set on the phone was already stored and simply did nothing on the desktop — which reads as the
//  Mac being broken rather than as a missing feature.
//
//  WHY THIS IS A SEPARATE SHEET FROM `MacFilterSheet`. That one edits a LIST: it writes six
//  filter fields plus sort onto the TaskList record, and offers "saved filter" and per-list
//  subtasks. My Tasks is virtual — it has no record to write to, its preferences live in the
//  account-wide `MyTasksPreferences`, and four of those six dimensions are meaningless here
//  (assignee is the definition of the view, not a filter on it). Sharing the sheet would mean a
//  form where half the controls are disabled and the save path forks on a boolean.
//
//  The three offered are exactly the three iOS offers, in the same order, reading and writing the
//  same synced preferences.

#if os(macOS)
import SwiftUI

struct MacMyTasksFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var preferences = MyTasksPreferencesService.shared

    @State private var completion: String = "default"
    @State private var priority: String = "all"
    @State private var dueDate: String = "all"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("navigation.my_tasks", comment: ""))
                .font(.headline).foregroundStyle(Theme.textPrimary)

            Form {
                Section(NSLocalizedString("lists.filters", comment: "")) {
                    picker(NSLocalizedString("lists.task_completion", comment: ""),
                           selection: $completion, options: MacListFilter.completion)
                    picker(NSLocalizedString("tasks.priority", comment: ""),
                           selection: $priority, options: MacListFilter.priority)
                    picker(NSLocalizedString("tasks.due_date", comment: ""),
                           selection: $dueDate, options: MacListFilter.dueDate)
                }
            }
            .formStyle(.grouped).macThemedSurface()
            .frame(height: 180)

            HStack {
                Button(NSLocalizedString("mac.clear_filters", comment: "")) {
                    completion = "default"; priority = "all"; dueDate = "all"
                    save()
                }
                .disabled(activeFilters == 0)
                Spacer()
                Button(NSLocalizedString("actions.done", comment: "")) { dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.return)
            }
        }
        .padding(20)
        .frame(width: 340)
        .background(Theme.bgPrimary)
        .accessibilityIdentifier("myTasks.filterSheet")
        // Load BEFORE the controls can write. A picker that starts on the default and is then
        // touched would save the default over a filter set on another device — the same trap
        // called out on task 8ef7d89d, and the reason each `onChange` saves rather than a
        // binding that fires while the sheet is still populating.
        .onAppear(perform: load)
        .onChange(of: completion) { _, _ in save() }
        .onChange(of: priority) { _, _ in save() }
        .onChange(of: dueDate) { _, _ in save() }
    }

    /// How many of the three are set. Gates Clear, so it cannot claim there is something to
    /// clear when there is not.
    private var activeFilters: Int {
        MacListFilter.activeCount(completion: completion, priority: priority, dueDate: dueDate,
                                  assignee: "all", repeating: "all", assignedBy: "all")
    }

    private func picker(_ title: String, selection: Binding<String>,
                        options: [MacListFilter.Option]) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { Text($0.label).tag($0.value) }
        }
    }

    private func load() {
        let current = preferences.preferences
        completion = current.filterCompletion ?? "default"
        dueDate = current.filterDueDate ?? "all"
        // My Tasks stores a LIST of priorities where a list stores one string. The sheet offers
        // one, matching iOS, so take the first and treat empty as "all".
        if let priorities = current.filterPriority, let first = priorities.first {
            priority = String(first)
        } else {
            priority = "all"
        }
    }

    private func save() {
        var updated = preferences.preferences
        updated.filterCompletion = completion
        updated.filterDueDate = dueDate
        // Empty means "all" — the default, and what the shared filter treats as no constraint.
        updated.filterPriority = Int(priority).map { [$0] } ?? []
        _Concurrency.Task { await preferences.updatePreferences(updated) }
    }
}
#endif
