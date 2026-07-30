import SwiftUI
import Contacts

/// Reusable sheet for adding members to a list with contacts autocomplete
/// Used by both ListMembershipTab (existing lists) and ListEditView (new lists)
struct AddMemberSheet: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss

    /// Called when a member is added with their email and role
    let onAdd: (String, String) -> Void

    /// Optional list ID to exclude existing members from suggestions
    let excludeListId: String?

    /// Optional set of emails to exclude from recommendations (for locally invited members)
    let excludeEmails: Set<String>?

    /// Whether to show role picker (false for simplified new list creation)
    let showRolePicker: Bool

    /// Whether to auto-dismiss after adding (true for existing lists, false for new list creation)
    let autoDismiss: Bool

    @State private var email = ""
    @State private var role = "member"
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    // Contacts autocomplete state
    @State private var searchResults: [ContactSearchResult] = []
    @State private var recommendedCollaborators: [RecommendedCollaborator] = []
    @State private var isSearching = false
    @State private var loadingRecommendations = false
    @State private var searchTask: _Concurrency.Task<Void, Never>?

    @StateObject private var contactsService = ContactsService.shared

    init(
        onAdd: @escaping (String, String) -> Void,
        excludeListId: String? = nil,
        excludeEmails: Set<String>? = nil,
        showRolePicker: Bool = true,
        autoDismiss: Bool = true
    ) {
        self.onAdd = onAdd
        self.excludeListId = excludeListId
        self.excludeEmails = excludeEmails
        self.showRolePicker = showRolePicker
        self.autoDismiss = autoDismiss
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(Theme.Typography.caption1())
                    }
                }

                if let success = successMessage {
                    Section {
                        Text(success)
                            .foregroundColor(.green)
                            .font(Theme.Typography.caption1())
                    }
                }

                // Email Address with autocomplete
                Section("Email Address") {
                    TextField("", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                        .tint(Theme.accent)
                        .onChange(of: email) { _, newValue in
                            searchContacts(query: newValue)
                        }

                    // Autocomplete results
                    if !searchResults.isEmpty && email.count >= 2 {
                        ForEach(searchResults) { contact in
                            Button {
                                selectContact(contact)
                            } label: {
                                contactRow(contact)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if isSearching {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("members.searching", comment: "Searching contacts..."))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }
                }

                if showRolePicker {
                    Section("Role") {
                        Picker("Role", selection: $role) {
                            Text("Member").tag("member")
                            Text("Admin").tag("admin")
                        }
                        .pickerStyle(.segmented)
                    }
                }

                // Recommended Collaborators section
                if !recommendedCollaborators.isEmpty {
                    Section {
                        ForEach(recommendedCollaborators) { collaborator in
                            Button {
                                selectRecommendedCollaborator(collaborator)
                            } label: {
                                collaboratorRow(collaborator)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(Theme.accent)
                            Text("Suggested")
                        }
                    } footer: {
                        Text(Brand.localized("members.astrid_users"))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }
                } else if loadingRecommendations {
                    Section("Suggested") {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(NSLocalizedString("members.loading_suggestions", comment: "Loading suggestions..."))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        }
                    }
                }

                // Contacts permission section
                if contactsService.authorizationStatus != .authorized {
                    Section {
                        Button {
                            requestContactsAccess()
                        } label: {
                            HStack {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .foregroundColor(Theme.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(NSLocalizedString("members.add_collaborators", comment: "Add Collaborators"))
                                        .font(Theme.Typography.body())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    Text(NSLocalizedString("members.upload_contacts", comment: "Upload your contacts for better collaboration"))
                                        .font(Theme.Typography.caption2())
                                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("members.add_member", comment: "Add Member"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isProcessing ? "Adding..." : "Add") {
                        addMember()
                    }
                    .disabled(email.isEmpty || isProcessing)
                }
            }
            .task {
                await loadRecommendedCollaborators()
            }
        }
    }

    // MARK: - Row Views

    @ViewBuilder
    private func contactRow(_ contact: ContactSearchResult) -> some View {
        HStack(spacing: 12) {
            // Avatar
            if contact.isAstridUser, let imageUrl = contact.astridUserImage {
                CachedAsyncImage(url: URL(string: imageUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Theme.accent)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(contact.isAstridUser ? Theme.accent : Color.gray.opacity(0.3))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(initials(for: contact.displayName))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                Text(contact.email)
                    .font(Theme.Typography.caption2())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            Spacer()

            if contact.isAstridUser {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.system(size: 14))
            }
        }
    }

    @ViewBuilder
    private func collaboratorRow(_ collaborator: RecommendedCollaborator) -> some View {
        HStack(spacing: 12) {
            // Avatar
            if let imageUrl = collaborator.image {
                CachedAsyncImage(url: URL(string: imageUrl)) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle().fill(Theme.accent)
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 32, height: 32)
                    .overlay {
                        Text(initials(for: collaborator.displayName))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(collaborator.displayName)
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    if collaborator.isMutual {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    }
                }
                Text(collaborator.email)
                    .font(Theme.Typography.caption2())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "plus.circle")
                .foregroundColor(Theme.accent)
        }
    }

    // MARK: - Helper Functions

    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return String(components[0].prefix(1) + components[1].prefix(1)).uppercased()
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }

    // MARK: - Contacts Functions

    private func searchContacts(query: String) {
        // Cancel previous search
        searchTask?.cancel()

        // Clear results if query is too short
        guard query.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        // Debounce search
        searchTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

            guard !_Concurrency.Task.isCancelled else { return }

            do {
                let results = try await contactsService.searchContacts(
                    query: query,
                    excludeListId: excludeListId
                )
                await MainActor.run {
                    searchResults = results
                    isSearching = false
                }
            } catch {
                print("AddMemberSheet Contact search failed: \(error)")
                await MainActor.run {
                    searchResults = []
                    isSearching = false
                }
            }
        }
    }

    private func selectContact(_ contact: ContactSearchResult) {
        email = contact.email
        searchResults = [] // Clear results after selection
    }

    private func selectRecommendedCollaborator(_ collaborator: RecommendedCollaborator) {
        email = collaborator.email
        // Trigger add immediately for recommendations
        addMember()
    }

    private func requestContactsAccess() {
        _Concurrency.Task {
            let granted = await contactsService.requestAccess()
            if granted {
                // Sync contacts to server
                do {
                    try await contactsService.syncContacts()
                    // Reload recommendations
                    await loadRecommendedCollaborators()
                } catch {
                    print("AddMemberSheet Contact sync failed: \(error)")
                }
            }
        }
    }

    private func loadRecommendedCollaborators() async {
        // Only load if contacts permission granted
        guard contactsService.hasPermission else {
            recommendedCollaborators = []
            return
        }

        loadingRecommendations = true

        do {
            let collaborators = try await contactsService.getRecommendedCollaborators(
                excludeListId: excludeListId
            )

            // Filter out locally invited members if excludeEmails is provided
            let filteredCollaborators: [RecommendedCollaborator]
            if let excludeEmails = excludeEmails {
                filteredCollaborators = collaborators.filter { collaborator in
                    !excludeEmails.contains(collaborator.email.lowercased())
                }
            } else {
                filteredCollaborators = collaborators
            }

            await MainActor.run {
                recommendedCollaborators = filteredCollaborators
                loadingRecommendations = false
            }
        } catch {
            print("AddMemberSheet Failed to load recommendations: \(error)")
            await MainActor.run {
                recommendedCollaborators = []
                loadingRecommendations = false
            }
        }
    }

    private func addMember() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        guard !trimmedEmail.isEmpty else { return }

        // Call the onAdd callback
        onAdd(trimmedEmail, role)

        // Reset form
        email = ""
        searchResults = []

        if autoDismiss {
            dismiss()
        }
    }
}

#Preview {
    AddMemberSheet(
        onAdd: { email, role in
            print("Adding \(email) as \(role)")
        },
        excludeListId: nil,
        showRolePicker: true,
        autoDismiss: true
    )
}
