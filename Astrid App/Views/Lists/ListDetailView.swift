import SwiftUI

struct ListDetailView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @StateObject private var listService = ListService.shared

    let list: TaskList

    @State private var isFavorite: Bool
    @State private var isVirtual: Bool
    @State private var showingDefaults = false
    @State private var showingFilters = false
    @State private var showingDelete = false
    @State private var showingSettings = false

    init(list: TaskList) {
        self.list = list
        _isFavorite = State(initialValue: list.isFavorite ?? false)
        _isVirtual = State(initialValue: list.isVirtual ?? false)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Form {
                    // Anchor for scroll-to-top
                    Color.clear
                        .frame(height: 0)
                        .id("top")

                    // List Info Section
                    Section("List Information") {
                        HStack {
                            Text("Name")
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            Spacer()
                            Text(list.name)
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        }

                        if let description = list.description, !description.isEmpty {
                            HStack(alignment: .top) {
                                Text("Description")
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                Spacer()
                                Text(description)
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    .multilineTextAlignment(.trailing)
                            }
                        }

                        HStack {
                            Text("Color")
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            Spacer()
                            ListImageView(list: list, size: 24)
                        }
                    }

                    // Favorites Section
                    Section {
                        Toggle("Add to Favorites", isOn: $isFavorite)
                            .onChange(of: isFavorite) { _, newValue in
                                _Concurrency.Task {
                                    do {
                                        try await listService.toggleFavorite(listId: list.id, isFavorite: newValue)
                                    } catch {
                                        AppLog.debug("❌ Failed to toggle favorite: \(error)")
                                        isFavorite = !newValue // Revert on error
                                    }
                                }
                            }

                        if isFavorite {
                            Text(NSLocalizedString("list.favorite_description", comment: "This list appears in your Favorites section"))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    } header: {
                        Text("Organization")
                    }

                    // Virtual List Section
                    Section {
                        Toggle("Saved Filter", isOn: $isVirtual)
                            .onChange(of: isVirtual) { _, newValue in
                                _Concurrency.Task {
                                    do {
                                        _ = try await listService.updateListAdvanced(
                                            listId: list.id,
                                            updates: ["isVirtual": newValue]
                                        )
                                    } catch {
                                        AppLog.debug("❌ Failed to toggle virtual: \(error)")
                                        isVirtual = !newValue // Revert on error
                                    }
                                }
                            }

                        if isVirtual {
                            Text(NSLocalizedString("list.smart_list_description", comment: "This list shows tasks based on filters, not list membership"))
                                .font(Theme.Typography.caption1())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    } header: {
                        Text(NSLocalizedString("list.type", comment: "List Type"))
                    }

                    // Configuration Section
                    Section("Configuration") {
                        NavigationLink {
                            ListDefaultsView(list: list)
                        } label: {
                            Label(NSLocalizedString("list.task_defaults", comment: "Task Defaults"), systemImage: "gearshape")
                        }

                        NavigationLink {
                            ListFiltersView(list: list)
                        } label: {
                            Label(NSLocalizedString("lists.sort_and_filters", comment: "Sort & Filters"), systemImage: "line.3.horizontal.decrease.circle")
                            if hasActiveFilters {
                                Image(systemName: "circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(Theme.accent)
                            }
                        }
                    }

                    // Danger Zone
                    Section {
                        Button(role: .destructive) {
                            showingDelete = true
                        } label: {
                            Label(NSLocalizedString("list.delete_list", comment: "Delete List"), systemImage: "trash")
                        }
                    } header: {
                        Text(NSLocalizedString("list.danger_zone", comment: "Danger Zone"))
                    }
                }
                .scrollToTopButton(proxy: proxy, topId: "top")
            }
            .coordinateSpace(name: "scroll")
        }
        .navigationTitle(NSLocalizedString("list.list_settings", comment: "List Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ListSettingsModal(
                list: listWithCurrentState(),
                onUpdate: { updatedList in
                    _Concurrency.Task {
                        // Build updates dictionary with all changed fields
                        var updates: [String: Any] = [:]

                        if updatedList.name != list.name {
                            updates["name"] = updatedList.name
                        }
                        if updatedList.description != list.description {
                            updates["description"] = updatedList.description ?? ""
                        }
                        // Compare against current @State values, not stale list prop
                        if updatedList.isFavorite ?? false != isFavorite {
                            updates["isFavorite"] = updatedList.isFavorite ?? false
                        }
                        if updatedList.isVirtual ?? false != isVirtual {
                            updates["isVirtual"] = updatedList.isVirtual ?? false
                        }
                        if updatedList.sortBy != list.sortBy {
                            updates["sortBy"] = updatedList.sortBy ?? "manual"
                        }
                        if updatedList.filterPriority != list.filterPriority {
                            updates["filterPriority"] = updatedList.filterPriority ?? "all"
                        }
                        if updatedList.filterAssignee != list.filterAssignee {
                            updates["filterAssignee"] = updatedList.filterAssignee ?? "all"
                        }
                        if updatedList.filterDueDate != list.filterDueDate {
                            updates["filterDueDate"] = updatedList.filterDueDate ?? "all"
                        }
                        if updatedList.filterCompletion != list.filterCompletion {
                            updates["filterCompletion"] = updatedList.filterCompletion ?? "default"
                        }
                        if updatedList.filterAssignedBy != list.filterAssignedBy {
                            updates["filterAssignedBy"] = updatedList.filterAssignedBy ?? "all"
                        }
                        if updatedList.filterRepeating != list.filterRepeating {
                            updates["filterRepeating"] = updatedList.filterRepeating ?? "all"
                        }
                        if updatedList.filterInLists != list.filterInLists {
                            updates["filterInLists"] = updatedList.filterInLists ?? "dont_filter"
                        }
                        if updatedList.defaultAssigneeId != list.defaultAssigneeId {
                            // Use NSNull() for nil to ensure key is sent to backend (nil removes key in Swift)
                            updates["defaultAssigneeId"] = updatedList.defaultAssigneeId != nil ? updatedList.defaultAssigneeId! : NSNull()
                        }
                        if updatedList.defaultPriority != list.defaultPriority {
                            updates["defaultPriority"] = updatedList.defaultPriority ?? 0
                        }
                        if updatedList.defaultIsPrivate != list.defaultIsPrivate {
                            updates["defaultIsPrivate"] = updatedList.defaultIsPrivate ?? true
                        }
                        if updatedList.defaultDueDate != list.defaultDueDate {
                            updates["defaultDueDate"] = updatedList.defaultDueDate ?? "none"
                        }
                        if updatedList.defaultDueTime != list.defaultDueTime {
                            // Use NSNull() for nil to ensure key is sent to backend (nil removes key in Swift)
                            updates["defaultDueTime"] = updatedList.defaultDueTime != nil ? updatedList.defaultDueTime! : NSNull()
                        }
                        if updatedList.defaultRepeating != list.defaultRepeating {
                            updates["defaultRepeating"] = updatedList.defaultRepeating ?? "never"
                        }
                        if updatedList.privacy != list.privacy {
                            updates["privacy"] = updatedList.privacy?.rawValue ?? "PRIVATE"
                        }
                        if updatedList.imageUrl != list.imageUrl {
                            updates["imageUrl"] = updatedList.imageUrl ?? NSNull()
                        }
                        if updatedList.githubRepositoryId != list.githubRepositoryId {
                            updates["githubRepositoryId"] = updatedList.githubRepositoryId ?? NSNull()
                        }

                        if !updates.isEmpty {
                            do {
                                let updated = try await listService.updateListAdvanced(
                                    listId: updatedList.id,
                                    updates: updates
                                )
                                // Update local state to reflect server response
                                if let updatedFavorite = updated.isFavorite {
                                    isFavorite = updatedFavorite
                                }
                                if let updatedVirtual = updated.isVirtual {
                                    isVirtual = updatedVirtual
                                }
                            } catch {
                                AppLog.debug("❌ Failed to update list: \(error)")
                            }
                        }
                    }
                },
                onDelete: {
                    showingDelete = true
                    showingSettings = false
                }
            )
        }
        .alert(NSLocalizedString("list.delete_list", comment: "Delete List"), isPresented: $showingDelete) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                _Concurrency.Task {
                    do {
                        try await listService.deleteList(listId: list.id)
                        dismiss()
                    } catch {
                        AppLog.debug("❌ Failed to delete list: \(error)")
                    }
                }
            }
        } message: {
            Text("Are you sure you want to delete \"\(list.name)\"? This cannot be undone.")
        }
    }

    private func listWithCurrentState() -> TaskList {
        var currentList = list
        currentList.isFavorite = isFavorite
        currentList.isVirtual = isVirtual
        return currentList
    }

    private var hasActiveFilters: Bool {
        let filters = ListFilters(
            filterCompletion: list.filterCompletion,
            filterDueDate: list.filterDueDate,
            filterAssignee: list.filterAssignee,
            filterAssignedBy: list.filterAssignedBy,
            filterRepeating: list.filterRepeating,
            filterPriority: list.filterPriority,
            filterInLists: list.filterInLists
        )
        return filters.hasActiveFilters
    }
}
