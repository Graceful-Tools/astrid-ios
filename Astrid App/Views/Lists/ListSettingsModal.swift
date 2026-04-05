import SwiftUI

/// List Settings Modal with 3 tabs (matching mobile web app)
struct ListSettingsModal: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    let list: TaskList
    let onUpdate: (TaskList) -> Void
    let onDelete: () -> Void
    var onLeave: (() -> Void)?

    // Mutable local copy — lives at the sheet root so @State is stable
    // (page-style TabView can destroy/recreate child views, wiping their @State)
    @State private var currentList: TaskList
    @State private var selectedTab = 0
    // Track removed member emails so we can re-apply removals if parent sends stale data
    @State private var removedMemberEmails = Set<String>()
    @State private var showingLeaveConfirmation = false
    @State private var isLeaving = false

    init(list: TaskList, onUpdate: @escaping (TaskList) -> Void, onDelete: @escaping () -> Void, onLeave: (() -> Void)? = nil) {
        self.list = list
        self.onUpdate = onUpdate
        self.onDelete = onDelete
        self.onLeave = onLeave
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

    /// Check if current user is the list owner
    private var isOwner: Bool {
        guard let currentUserId = AuthManager.shared.userId else { return false }
        return currentList.ownerId == currentUserId || currentList.owner?.id == currentUserId
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

    /// Leave the current list
    private func leaveList() {
        isLeaving = true
        _Concurrency.Task {
            do {
                try await AstridAPIClient.shared.leaveList(id: currentList.id)
                dismiss()
                onLeave?()
            } catch {
                isLeaving = false
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker: admins get 3 tabs, non-admins get 2 (Filters + Members)
                Picker("", selection: $selectedTab) {
                    Label(NSLocalizedString("lists.filters", comment: ""), systemImage: "line.3.horizontal.decrease.circle")
                        .tag(0)
                    Label(NSLocalizedString("lists.members", comment: ""), systemImage: "person.2")
                        .tag(1)
                    if canEditSettings {
                        Label(NSLocalizedString("lists.admin", comment: ""), systemImage: "gearshape")
                            .tag(2)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Theme.spacing16)

                Divider()

                TabView(selection: $selectedTab) {
                    ListSortFiltersTab(list: currentList, onUpdate: handleUpdate)
                        .tag(0)

                    ListMembershipTab(list: currentList, onUpdate: handleLocalUpdate, removedMemberEmails: $removedMemberEmails, onLeave: !isOwner ? {
                        showingLeaveConfirmation = true
                    } : nil)
                        .tag(1)

                    if canEditSettings {
                        ListAdminTab(list: currentList, onUpdate: handleUpdate, onDelete: onDelete)
                            .tag(2)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
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
            .alert(NSLocalizedString("lists.leave_list", comment: ""), isPresented: $showingLeaveConfirmation) {
                Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) {}
                Button(NSLocalizedString("lists.leave_list", comment: ""), role: .destructive) {
                    leaveList()
                }
            } message: {
                Text(NSLocalizedString("lists.leave_confirm", comment: "Are you sure you want to leave this list?"))
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
