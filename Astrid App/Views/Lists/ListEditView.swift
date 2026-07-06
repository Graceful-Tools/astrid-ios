import SwiftUI

/// List Edit View with inline editing (matching TaskDetailViewNew design)
struct ListEditView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared

    let list: TaskList?

    @State private var name = ""
    @State private var description = ""
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Member invitation
    @State private var showingAddMember = false
    @State private var invitedMembers: [(email: String, role: String)] = []

    init(list: TaskList? = nil) {
        self.list = list

        if let list = list {
            _name = State(initialValue: list.name)
            _description = State(initialValue: list.description ?? "")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.spacing24) {
                    // 1. List Name
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Text(NSLocalizedString("lists.list_name", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            .padding(.horizontal, Theme.spacing16)

                        TextField(NSLocalizedString("lists.enter_name", comment: ""), text: $name)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                            .textFieldStyle(.plain)
                            .padding(Theme.spacing12)
                            .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            .padding(.horizontal, Theme.spacing16)
                    }
                    .padding(.top, Theme.spacing16)

                    Divider()
                        .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                    // 2. Description
                    InlineTextAreaEditor(
                        label: NSLocalizedString("lists.list_description", comment: ""),
                        text: $description,
                        placeholder: NSLocalizedString("lists.description_placeholder", comment: ""),
                        onSave: { /* Auto-save handled on submit */ }
                    )
                    .padding(.horizontal, Theme.spacing16)

                    Divider()
                        .background(colorScheme == .dark ? Theme.Dark.border : Theme.border)

                    // 3. Members (only for new lists)
                    if list == nil {
                        VStack(alignment: .leading, spacing: Theme.spacing12) {
                            HStack {
                                Text(NSLocalizedString("lists.members", comment: ""))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                                Spacer()

                                Button {
                                    showingAddMember = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.badge.plus")
                                            .font(.system(size: 14))
                                        Text(NSLocalizedString("actions.add", comment: ""))
                                            .font(Theme.Typography.caption1())
                                    }
                                    .foregroundColor(Theme.accent)
                                }
                            }
                            .padding(.horizontal, Theme.spacing16)

                            // Invited members list
                            if !invitedMembers.isEmpty {
                                VStack(spacing: Theme.spacing8) {
                                    ForEach(Array(invitedMembers.enumerated()), id: \.offset) { index, member in
                                        HStack(spacing: Theme.spacing12) {
                                            Circle()
                                                .fill(Theme.accent.opacity(0.2))
                                                .frame(width: 32, height: 32)
                                                .overlay {
                                                    Text(String(member.email.prefix(1)).uppercased())
                                                        .font(Theme.Typography.caption1())
                                                        .foregroundColor(Theme.accent)
                                                }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(member.email)
                                                    .font(Theme.Typography.body())
                                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                                Text(member.role.capitalized)
                                                    .font(Theme.Typography.caption2())
                                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                            }

                                            Spacer()

                                            Button {
                                                invitedMembers.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        .padding(Theme.spacing12)
                                        .background(colorScheme == .dark ? Theme.Dark.bgSecondary : Theme.bgSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                                    }
                                }
                                .padding(.horizontal, Theme.spacing16)
                            } else {
                                Text(NSLocalizedString("lists.no_members", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                                    .padding(.horizontal, Theme.spacing16)
                            }
                        }
                    }

                    // Error Message
                    if showError {
                        Text(errorMessage)
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.red)
                            .padding(Theme.spacing12)
                            .background(Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMedium))
                            .padding(.horizontal, Theme.spacing16)
                    }

                    Spacer().frame(height: Theme.spacing24)
                }
            }
            .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
            .navigationTitle(list == nil ? NSLocalizedString("lists.new_list", comment: "") : NSLocalizedString("lists.edit_list", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("actions.cancel", comment: "")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isLoading {
                        ProgressView()
                    } else {
                        Button(list == nil ? NSLocalizedString("actions.create", comment: "") : NSLocalizedString("actions.save", comment: "")) {
                            _Concurrency.Task { await saveList() }
                        }
                        .disabled(name.isEmpty)
                    }
                }
            }
            .sheet(isPresented: $showingAddMember) {
                AddMemberSheet(
                    onAdd: { email, role in
                        // Check if already added
                        if !invitedMembers.contains(where: { $0.email == email }) {
                            invitedMembers.append((email: email, role: role))
                        }
                        showingAddMember = false
                    },
                    excludeListId: nil, // New list, no existing members to exclude
                    excludeEmails: Set(invitedMembers.map { $0.email.lowercased() }), // Exclude locally invited members
                    showRolePicker: true,
                    autoDismiss: false // We handle dismiss in onAdd
                )
                .presentationDetents([.large])
            }
        }
    }

    // MARK: - Helper Functions

    private func saveList() async {
        isLoading = true
        showError = false

        do {
            if let list = list {
                // Update existing list
                let updates: [String: Any] = [
                    "name": name,
                    "description": description.isEmpty ? "" : description
                ]
                _ = try await listService.updateListAdvanced(listId: list.id, updates: updates)
            } else {
                // Create new list
                let newList = try await listService.createList(
                    name: name,
                    description: description.isEmpty ? nil : description,
                    privacy: "PRIVATE",
                    color: nil
                )

                // Add invited members to the new list. Route through the
                // canonical ListMemberService (offline queue via CDMember) —
                // NOT AstridAPIClient directly, or invites are silently lost
                // when offline.
                if !invitedMembers.isEmpty {
                    var failedMembers: [String] = []

                    for member in invitedMembers {
                        do {
                            _ = try await ListMemberService.shared.addMember(
                                listId: newList.id,
                                email: member.email,
                                role: member.role
                            )
                            print("✅ Added member \(member.email)")
                        } catch {
                            print("⚠️ Failed to add member \(member.email): \(error)")
                            failedMembers.append(member.email)
                        }
                    }

                    // Refresh list data to get updated member list
                    _ = try? await listService.fetchLists()

                    // Show error if some members failed to be added
                    if !failedMembers.isEmpty {
                        errorMessage = "List created, but failed to add: \(failedMembers.joined(separator: ", "))"
                        showError = true
                        isLoading = false
                        // Don't dismiss - let user see the error
                        return
                    }
                }
            }

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
}

#Preview {
    ListEditView()
}
