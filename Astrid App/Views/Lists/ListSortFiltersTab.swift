import SwiftUI

/// Sort & Filters tab for list settings
struct ListSortFiltersTab: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared
    @ObservedObject private var memberService = ListMemberService.shared

    let list: TaskList
    let onUpdate: (TaskList) -> Void

    @State private var sortBy: String
    @State private var filterPriority: String
    @State private var filterAssignee: String
    @State private var filterDueDate: String
    @State private var filterCompletion: String
    @State private var filterAssignedBy: String
    @State private var filterRepeating: String
    @State private var filterInLists: String
    @State private var isFavorite: Bool
    /// Per-list inline subtasks (ba1deb9d). Lives here rather than in Admin because it is a
    /// question about what this list RENDERS, same as every other control on this tab.
    @State private var showSubtasks: Bool
    @State private var isVirtual: Bool
    @State private var isSaving: Bool = false

    init(list: TaskList, onUpdate: @escaping (TaskList) -> Void) {
        self.list = list
        self.onUpdate = onUpdate
        _sortBy = State(initialValue: list.sortBy ?? "manual")
        _filterPriority = State(initialValue: list.filterPriority ?? "all")
        _filterAssignee = State(initialValue: list.filterAssignee ?? "all")
        _filterDueDate = State(initialValue: list.filterDueDate ?? "all")
        _filterCompletion = State(initialValue: list.filterCompletion ?? "default")
        _filterAssignedBy = State(initialValue: list.filterAssignedBy ?? "all")
        _filterRepeating = State(initialValue: list.filterRepeating ?? "all")
        _filterInLists = State(initialValue: list.filterInLists ?? "dont_filter")
        _isFavorite = State(initialValue: list.isFavorite ?? false)
        // Seeded through the shared rule, so "absent means SHOW" is stated in one place.
        _showSubtasks = State(initialValue: ListSubtaskVisibility.listShowsSubtasks(list.showSubtasks))
        _isVirtual = State(initialValue: list.isVirtual ?? false)
    }

    var body: some View {
        Form {
            // Sort By
            Section(NSLocalizedString("lists.sort_by", comment: "")) {
                Picker(NSLocalizedString("lists.sort_order", comment: ""), selection: $sortBy) {
                    Text(NSLocalizedString("lists.auto", comment: "")).tag("auto")
                    Text(NSLocalizedString("lists.manual", comment: "")).tag("manual")
                    Text(NSLocalizedString("lists.due_date", comment: "")).tag("when")
                    Text(NSLocalizedString("tasks.priority", comment: "")).tag("priority")
                    Text(NSLocalizedString("lists.created_date", comment: "")).tag("createdAt")
                    // Web's sortBy value verbatim — the field round-trips through
                    // PUT /api/v1/lists/:id and both platforms read the same key.
                    Text(NSLocalizedString("lists.recently_completed", comment: "")).tag("completedAt")
                }
                .onChange(of: sortBy) { oldValue, newValue in
                    print("🔄 [ListSortFiltersTab] sortBy changed: \(oldValue) → \(newValue)")
                    saveSettings()
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
                .onChange(of: filterCompletion) { oldValue, newValue in
                    print("🔄 [ListSortFiltersTab] filterCompletion changed: \(oldValue) → \(newValue)")
                    saveSettings()
                }

                // Assignee
                Picker(NSLocalizedString("tasks.assignee", comment: ""), selection: $filterAssignee) {
                    Text(NSLocalizedString("lists.all", comment: "")).tag("all")
                    Text(NSLocalizedString("lists.me", comment: "")).tag("current_user")
                    Text(NSLocalizedString("lists.not_me", comment: "")).tag("not_current_user")
                    Text(NSLocalizedString("assignee.unassigned", comment: "")).tag("unassigned")

                    if !memberService.members.isEmpty {
                        Divider()
                        ForEach(memberService.members) { member in
                            Text(member.displayName).tag(member.id)
                        }
                    }
                }
                .onChange(of: filterAssignee) { saveSettings() }

                // Due Date
                Picker(NSLocalizedString("tasks.due_date", comment: ""), selection: $filterDueDate) {
                    Text(NSLocalizedString("lists.all", comment: "")).tag("all")
                    Text(NSLocalizedString("lists.overdue", comment: "")).tag("overdue")
                    Text(NSLocalizedString("time.today", comment: "")).tag("today")
                    Text(NSLocalizedString("lists.this_week", comment: "")).tag("this_week")
                    Text(NSLocalizedString("lists.this_month", comment: "")).tag("this_month")
                    Text(NSLocalizedString("lists.no_date", comment: "")).tag("no_date")
                }
                .onChange(of: filterDueDate) { saveSettings() }

                // Priority
                Picker(NSLocalizedString("tasks.priority", comment: ""), selection: $filterPriority) {
                    Text(NSLocalizedString("lists.all_priorities", comment: "")).tag("all")
                    Text(NSLocalizedString("lists.highest_priority", comment: "")).tag("3")
                    Text(NSLocalizedString("lists.high_priority", comment: "")).tag("2")
                    Text(NSLocalizedString("lists.medium_priority", comment: "")).tag("1")
                    Text(NSLocalizedString("lists.low_priority", comment: "")).tag("0")
                }
                .onChange(of: filterPriority) { saveSettings() }

                // Assigned By (Task Creator)
                Picker(NSLocalizedString("lists.assigned_by", comment: ""), selection: $filterAssignedBy) {
                    Text(NSLocalizedString("lists.all", comment: "")).tag("all")
                    Text(NSLocalizedString("lists.me", comment: "")).tag("current_user")
                    Text(NSLocalizedString("lists.not_me", comment: "")).tag("not_current_user")

                    if !memberService.members.isEmpty {
                        Divider()
                        ForEach(memberService.members) { member in
                            Text(member.displayName).tag(member.id)
                        }
                    }
                }
                .onChange(of: filterAssignedBy) { saveSettings() }

                // Repeating Status
                Picker(NSLocalizedString("lists.repeating", comment: ""), selection: $filterRepeating) {
                    Text(NSLocalizedString("lists.all", comment: "")).tag("all")
                    Text(NSLocalizedString("lists.not_repeating", comment: "")).tag("not_repeating")
                    Text(NSLocalizedString("lists.daily", comment: "")).tag("daily")
                    Text(NSLocalizedString("lists.weekly", comment: "")).tag("weekly")
                    Text(NSLocalizedString("lists.monthly", comment: "")).tag("monthly")
                    Text(NSLocalizedString("lists.yearly", comment: "")).tag("yearly")
                    Text(NSLocalizedString("lists.custom", comment: "")).tag("custom")
                }
                .onChange(of: filterRepeating) { saveSettings() }

                // List Membership
                Picker(NSLocalizedString("lists.list_membership", comment: ""), selection: $filterInLists) {
                    Text(NSLocalizedString("lists.all_tasks", comment: "")).tag("dont_filter")
                    Text(NSLocalizedString("lists.in_any_list", comment: "")).tag("in_list")
                    Text(NSLocalizedString("lists.not_in_any_list", comment: "")).tag("not_in_list")
                }
                .onChange(of: filterInLists) { saveSettings() }
            }

            // Clear Filters
            Section {
                Button(NSLocalizedString("lists.clear_all_filters", comment: "")) {
                    sortBy = "manual"
                    filterPriority = "all"
                    filterAssignee = "all"
                    filterDueDate = "all"
                    filterCompletion = "default"
                    filterAssignedBy = "all"
                    filterRepeating = "all"
                    filterInLists = "dont_filter"
                    // Keep favorite status (user intent to favorite should persist)
                    saveSettings()
                }
                .foregroundColor(Theme.accent)
            }

            // Per-list inline subtasks (ba1deb9d). Separate from the account-wide Sub-tasks
            // display setting: that one decides whether subtasks appear inline ANYWHERE, this one
            // is for the case where one list is a deep project and another is a flat inbox.
            Section {
                Toggle(isOn: $showSubtasks) {
                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: "list.bullet.indent")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        Text(NSLocalizedString("lists.show_subtasks", comment: ""))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                }
                .onChange(of: showSubtasks) { _, newValue in
                    saveShowSubtasks(newValue)
                }

                Text(NSLocalizedString("lists.show_subtasks_footer", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
            }

            // Favorite Toggle
            Section {
                Toggle(isOn: $isFavorite) {
                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundColor(isFavorite ? .yellow : (colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted))
                        Text(NSLocalizedString("lists.favorite", comment: ""))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                }
                .onChange(of: isFavorite) { _, newValue in
                    // Save favorite status directly to backend
                    _Concurrency.Task {
                        do {
                            try await listService.toggleFavorite(listId: list.id, isFavorite: newValue)
                            print("✅ [ListSortFiltersTab] Toggled favorite for list: \(list.name) to \(newValue)")
                        } catch {
                            print("❌ [ListSortFiltersTab] Failed to toggle favorite: \(error)")
                            // Revert on error
                            isFavorite = !newValue
                        }
                    }
                }

                if isFavorite {
                    Text(NSLocalizedString("lists.favorite_description", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
            }

            // Saved Filter Toggle
            Section {
                Toggle(isOn: $isVirtual) {
                    HStack(spacing: Theme.spacing8) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        Text(NSLocalizedString("lists.saved_filter", comment: ""))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    }
                }
                .onChange(of: isVirtual) { _, newValue in
                    // Save virtual status directly to backend
                    _Concurrency.Task {
                        do {
                            _ = try await listService.updateListAdvanced(
                                listId: list.id,
                                updates: ["isVirtual": newValue]
                            )
                            print("✅ [ListSortFiltersTab] Toggled saved filter for list: \(list.name) to \(newValue)")
                        } catch {
                            print("❌ [ListSortFiltersTab] Failed to toggle saved filter: \(error)")
                            // Revert on error
                            isVirtual = !newValue
                        }
                    }
                }

                if isVirtual {
                    Text(NSLocalizedString("lists.saved_filter_description", comment: ""))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
        .task {
            await loadMembers()
        }
    }

    private var hasActiveFilters: Bool {
        return sortBy != "manual"
            || filterCompletion != "default"
            || filterPriority != "all"
            || filterDueDate != "all"
            || filterAssignee != "all"
            || filterAssignedBy != "all"
            || filterRepeating != "all"
            || filterInLists != "dont_filter"
    }

    private func loadMembers() async {
        do {
            try await memberService.fetchMembers(listId: list.id)
        } catch {
            print("❌ Failed to load members: \(error)")
        }
    }

    /// Written on its own, NOT through saveSettings(): that builds a payload of every filter
    /// field each time, so folding this in would send showSubtasks on every unrelated change —
    /// exactly what ListSubtaskVisibility.payloadValue exists to prevent. Same shape as the
    /// Favorite toggle, which also writes directly.
    private func saveShowSubtasks(_ newValue: Bool) {
        guard let value = ListSubtaskVisibility.payloadValue(original: list.showSubtasks,
                                                             edited: newValue) else { return }
        _Concurrency.Task {
            do {
                let updated = try await listService.updateListAdvanced(listId: list.id,
                                                                       updates: ["showSubtasks": value])
                onUpdate(updated)
            } catch {
                print("❌ [ListSortFiltersTab] Failed to save showSubtasks: \(error)")
                showSubtasks = !newValue   // revert, as the favorite toggle does
            }
        }
    }

    private func saveSettings() {
        print("🔧🔧🔧 [ListSortFiltersTab] saveSettings() CALLED")
        print("  - list.id: \(list.id)")
        print("  - list.name: \(list.name)")
        print("  - filterCompletion: \(filterCompletion)")
        print("  - sortBy: \(sortBy)")
        print("  - isSaving: \(isSaving)")

        // Debounce: Skip if already saving
        guard !isSaving else {
            print("  ⚠️ SKIPPED - already saving")
            return
        }

        isSaving = true

        // Save filter settings directly to backend (like isFavorite and isVirtual do)
        let updates: [String: Any] = [
            "sortBy": sortBy,
            "filterPriority": filterPriority,
            "filterAssignee": filterAssignee,
            "filterDueDate": filterDueDate,
            "filterCompletion": filterCompletion,
            "filterAssignedBy": filterAssignedBy,
            "filterRepeating": filterRepeating,
            "filterInLists": filterInLists
        ]

        print("📤 [ListSortFiltersTab] Calling listService.updateListAdvanced...")

        _Concurrency.Task {
            defer {
                isSaving = false
                print("🔓 [ListSortFiltersTab] isSaving reset to false")
            }

            do {
                let result = try await listService.updateListAdvanced(
                    listId: list.id,
                    updates: updates
                )
                print("✅✅✅ [ListSortFiltersTab] API SAVE SUCCEEDED")
                print("  - Returned filterCompletion: \(result.filterCompletion ?? "nil")")
                print("  - Returned sortBy: \(result.sortBy ?? "nil")")

                // Also verify local listService state
                if let localList = listService.lists.first(where: { $0.id == list.id }) {
                    print("  - Local list filterCompletion: \(localList.filterCompletion ?? "nil")")
                }

                // Notify parent of the update for UI refresh
                var updated = list
                updated.sortBy = sortBy
                updated.filterPriority = filterPriority
                updated.filterAssignee = filterAssignee
                updated.filterDueDate = filterDueDate
                updated.filterCompletion = filterCompletion
                updated.filterAssignedBy = filterAssignedBy
                updated.filterRepeating = filterRepeating
                updated.filterInLists = filterInLists
                updated.isFavorite = isFavorite
                updated.isVirtual = isVirtual
                onUpdate(updated)
            } catch {
                print("❌❌❌ [ListSortFiltersTab] API SAVE FAILED: \(error)")
                print("  - Error type: \(type(of: error))")
            }
        }
    }
}
