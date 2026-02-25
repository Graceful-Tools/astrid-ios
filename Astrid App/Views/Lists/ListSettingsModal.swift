import SwiftUI

/// List Settings Modal with 3 tabs (matching mobile web app)
struct ListSettingsModal: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let list: TaskList
    let onUpdate: (TaskList) -> Void
    let onDelete: () -> Void

    // Mutable local copy — lives at the sheet root so @State is stable
    // (page-style TabView can destroy/recreate child views, wiping their @State)
    @State private var currentList: TaskList
    @State private var selectedTab = 0
    // Track removed member emails so we can re-apply removals if parent sends stale data
    @State private var removedMemberEmails = Set<String>()

    init(list: TaskList, onUpdate: @escaping (TaskList) -> Void, onDelete: @escaping () -> Void) {
        self.list = list
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self._currentList = State(initialValue: list)
    }

    /// Check if current user can edit settings (is owner or admin)
    private var canEditSettings: Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return false
        }

        if currentList.ownerId == currentUserId || currentList.owner?.id == currentUserId {
            return true
        }

        if let admins = currentList.admins, admins.contains(where: { $0.id == currentUserId }) {
            return true
        }

        if let listMembers = currentList.listMembers {
            if listMembers.contains(where: { $0.user?.id == currentUserId && $0.role == "admin" }) {
                return true
            }
        }

        return false
    }

    /// Update local state AND forward to parent (for sort/filter/admin changes)
    private func handleUpdate(_ updatedList: TaskList) {
        currentList = updatedList
        onUpdate(updatedList)
    }

    /// Update local state only — no parent notification (for membership changes
    /// that make their own API calls and don't need the parent to re-render)
    private func handleLocalUpdate(_ updatedList: TaskList) {
        currentList = updatedList
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if canEditSettings {
                    Picker("", selection: $selectedTab) {
                        Label(NSLocalizedString("lists.filters", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
                            .tag(0)
                        Label(NSLocalizedString("lists.members", comment: ""), systemImage: "person.2")
                            .tag(1)
                        Label(NSLocalizedString("lists.admin", comment: ""), systemImage: "gearshape")
                            .tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(Theme.spacing16)

                    Divider()
                }

                if canEditSettings {
                    TabView(selection: $selectedTab) {
                        ListSortFiltersTab(list: currentList, onUpdate: handleUpdate)
                            .tag(0)

                        ListMembershipTab(list: currentList, onUpdate: handleLocalUpdate, removedMemberEmails: $removedMemberEmails)
                            .tag(1)

                        ListAdminTab(list: currentList, onUpdate: handleUpdate, onDelete: onDelete)
                            .tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                } else {
                    ListSortFiltersTab(list: currentList, onUpdate: handleUpdate)
                }
            }
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .navigationTitle(NSLocalizedString("lists.list_settings", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.done", comment: "")) {
                        dismiss()
                    }
                }
            }
            .onChange(of: list) {
                // Sync external updates into local state, but re-apply any
                // pending member removals so stale parent data can't revert them
                var incoming = list
                if !removedMemberEmails.isEmpty {
                    incoming.admins?.removeAll { removedMemberEmails.contains($0.email ?? "") }
                    incoming.members?.removeAll { removedMemberEmails.contains($0.email ?? "") }
                    incoming.listMembers?.removeAll { removedMemberEmails.contains($0.user?.email ?? "") }
                }
                currentList = incoming
            }
        }
    }
}
