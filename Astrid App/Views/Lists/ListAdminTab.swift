import SwiftUI

/// Admin settings tab for list settings
struct ListAdminTab: View {
    @Environment(\.colorScheme) var colorScheme

    let list: TaskList
    let onUpdate: (TaskList) -> Void
    let onDelete: () -> Void

    @State private var listName: String
    @State private var listDescription: String
    @State private var showingDeleteConfirmation = false
    @State private var showingImagePicker = false
    @State private var currentImageUrl: String?

    // Project status board state
    @State private var showingDisableBoardConfirmation = false
    @State private var boardOperationInFlight = false
    @State private var boardError: String?

    // Recently completed window state
    @State private var recentlyCompletedPresetId: RecentlyCompletedPresetId
    @State private var recentlyCompletedSpecificDate: Date

    // Default task settings
    @State private var defaultAssigneeId: String?
    @State private var defaultPriority: Task.Priority
    @State private var defaultDueDate: String
    @State private var defaultDueTime: String?
    @State private var defaultRepeating: String

    // GitHub integration
    @State private var githubRepositoryId: String?
    @State private var availableRepositories: [GitHubRepository] = []
    @State private var loadingRepositories = false
    @State private var repositoriesError: String?

    // AI provider status (determines if GitHub integration should be shown)
    @State private var hasAIProviders = false
    @State private var loadingAIStatus = false

    @ObservedObject private var memberService = ListMemberService.shared

    init(list: TaskList, onUpdate: @escaping (TaskList) -> Void, onDelete: @escaping () -> Void) {
        self.list = list
        self.onUpdate = onUpdate
        self.onDelete = onDelete

        _listName = State(initialValue: list.name)
        _listDescription = State(initialValue: list.description ?? "")
        _currentImageUrl = State(initialValue: list.imageUrl)
        _defaultAssigneeId = State(initialValue: list.defaultAssigneeId)
        _defaultPriority = State(initialValue: Task.Priority(rawValue: list.defaultPriority ?? 0) ?? .none)
        _defaultDueDate = State(initialValue: list.defaultDueDate ?? "none")
        _defaultDueTime = State(initialValue: list.defaultDueTime)
        _defaultRepeating = State(initialValue: list.defaultRepeating ?? "never")
        _githubRepositoryId = State(initialValue: list.githubRepositoryId)

        // Initialize Recently-completed picker from the list's stored window.
        let presetId = findPresetForWindow(list.recentlyCompletedWindow)?.id ?? .default24h
        _recentlyCompletedPresetId = State(initialValue: presetId)

        var initialDate = Date()
        if case let .sinceDate(dateString) = list.recentlyCompletedWindow {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            initialDate = formatter.date(from: dateString) ?? Date()
        }
        _recentlyCompletedSpecificDate = State(initialValue: initialDate)
    }

    // Computed property to create a list with the current image URL for live preview
    private var listWithCurrentImage: TaskList {
        var updated = list
        updated.imageUrl = currentImageUrl
        return updated
    }

    var body: some View {
        Form(content: {
            // List Info
            Section(NSLocalizedString("lists.list_information", comment: "")) {
                TextField(NSLocalizedString("lists.list_name", comment: ""), text: $listName)
                    .onChange(of: listName) { _, _ in
                        saveBasicInfo()
                    }

                TextField(NSLocalizedString("tasks.description", comment: ""), text: $listDescription, axis: .vertical)
                    .onChange(of: listDescription) { _, _ in
                        saveBasicInfo()
                    }
            }

            // List Appearance
            Section(NSLocalizedString("lists.list_appearance", comment: "")) {
                HStack(spacing: Theme.spacing16) {
                    // Current list image preview (with live update)
                    ListImageViewLarge(list: listWithCurrentImage, size: 64)
                        .id(currentImageUrl ?? "default") // Force view refresh when image changes

                    VStack(alignment: .leading, spacing: Theme.spacing4) {
                        Text(NSLocalizedString("lists.list_image", comment: ""))
                            .font(Theme.Typography.body())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                        Text(NSLocalizedString("lists.list_image_description", comment: ""))
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    }

                    Spacer()

                    Button {
                        showingImagePicker = true
                    } label: {
                        Text(NSLocalizedString("actions.change", comment: ""))
                            .font(Theme.Typography.body())
                            .foregroundColor(Theme.accent)
                    }
                }
                .padding(.vertical, Theme.spacing8)
            }

            // Default Task Settings
            Section(NSLocalizedString("lists.default_task_settings", comment: "")) {
                // Priority
                HStack {
                    Text(NSLocalizedString("tasks.priority", comment: ""))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                    Spacer()

                    PriorityButtonPicker(priority: $defaultPriority) { newPriority in
                        self.defaultPriority = newPriority
                        saveDefaults()
                    }
                }
                .padding(.vertical, Theme.spacing4)

                // Assignee - Hidden for local users
                if !AuthManager.shared.isLocalOnlyMode {
                    Picker(NSLocalizedString("tasks.assignee", comment: ""), selection: $defaultAssigneeId) {
                        Text(NSLocalizedString("lists.task_creator", comment: "")).tag(nil as String?)
                        Text(NSLocalizedString("assignee.unassigned", comment: "")).tag("unassigned" as String?)

                        if !memberService.members.isEmpty {
                            Divider()
                            ForEach(memberService.members) { member in
                                Text(member.displayName).tag(member.id as String?)
                            }
                        }
                    }
                    .onChange(of: defaultAssigneeId) { _, _ in
                        saveDefaults()
                    }
                }

                // Due Date
                Picker(NSLocalizedString("tasks.due_date", comment: ""), selection: $defaultDueDate) {
                    Text(NSLocalizedString("lists.none", comment: "")).tag("none")
                    Text(NSLocalizedString("time.today", comment: "")).tag("today")
                    Text(NSLocalizedString("lists.tomorrow", comment: "")).tag("tomorrow")
                    Text(NSLocalizedString("lists.next_week", comment: "")).tag("next_week")
                    Text(NSLocalizedString("lists.next_month", comment: "")).tag("next_month")
                }
                .onChange(of: defaultDueDate) { _, _ in
                    saveDefaults()
                }

                // Due Time
                Picker(NSLocalizedString("tasks.due_time", comment: ""), selection: $defaultDueTime) {
                    Text(NSLocalizedString("lists.all_day", comment: "")).tag(nil as String?)
                    Text("9:00 AM").tag("09:00" as String?)
                    Text("12:00 PM").tag("12:00" as String?)
                    Text("2:00 PM").tag("14:00" as String?)
                    Text("5:00 PM").tag("17:00" as String?)
                    Text("6:00 PM").tag("18:00" as String?)
                    Text("8:00 PM").tag("20:00" as String?)
                }
                .onChange(of: defaultDueTime) { _, _ in
                    saveDefaults()
                }

                // Repeating
                Picker(NSLocalizedString("lists.repeating", comment: ""), selection: $defaultRepeating) {
                    Text(NSLocalizedString("lists.never", comment: "")).tag("never")
                    Text(NSLocalizedString("lists.daily", comment: "")).tag("daily")
                    Text(NSLocalizedString("lists.weekly", comment: "")).tag("weekly")
                    Text(NSLocalizedString("lists.monthly", comment: "")).tag("monthly")
                }
                .onChange(of: defaultRepeating) { _, _ in
                    saveDefaults()
                }
            }

            // GitHub Integration - Only show if user has AI providers configured
            if hasAIProviders {
                Section {
                    VStack(alignment: .leading, spacing: Theme.spacing8) {
                        Text(NSLocalizedString("lists.link_repo_description", comment: ""))
                            .font(Theme.Typography.caption1())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

                        if loadingRepositories {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text(NSLocalizedString("lists.loading_repositories", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }
                        } else if let error = repositoriesError {
                            VStack(alignment: .leading, spacing: Theme.spacing4) {
                                Text(error)
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(Theme.error)
                                Button(NSLocalizedString("actions.retry", comment: "")) {
                                    _Concurrency.Task {
                                        await loadRepositories()
                                    }
                                }
                                .font(Theme.Typography.caption1())
                            }
                        } else {
                            Picker(NSLocalizedString("lists.github_repository", comment: ""), selection: $githubRepositoryId) {
                                Text(NSLocalizedString("lists.none", comment: "")).tag(nil as String?)

                                if !availableRepositories.isEmpty {
                                    Divider()
                                    ForEach(availableRepositories) { repo in
                                        Text(repo.name).tag(repo.fullName as String?)
                                    }
                                }
                            }
                            .onChange(of: githubRepositoryId) { _, newValue in
                                saveGitHubSettings()
                            }

                            if availableRepositories.isEmpty {
                                Text(NSLocalizedString("lists.no_repositories_found", comment: ""))
                                    .font(Theme.Typography.caption2())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                            }

                            Button {
                                _Concurrency.Task {
                                    await loadRepositories(refresh: true)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text(NSLocalizedString("userMenu.refreshData", comment: ""))
                                }
                                .font(Theme.Typography.caption1())
                            }
                            .disabled(loadingRepositories)
                        }
                    }
                    .padding(.vertical, Theme.spacing8)
                } header: {
                    Text(NSLocalizedString("lists.github_integration", comment: ""))
                }
            }

            // Project status board
            Section {
                if list.projectId != nil {
                    Button(action: { showingDisableBoardConfirmation = true }) {
                        HStack {
                            Image(systemName: "rectangle.split.3x1")
                            Text("Disable Board")
                        }
                        .foregroundColor(Theme.error)
                    }
                    .disabled(boardOperationInFlight)
                } else {
                    Button(action: createBoard) {
                        HStack {
                            Image(systemName: "rectangle.split.3x1")
                            Text("Create Board")
                            if boardOperationInFlight {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(boardOperationInFlight)
                }
                if let boardError {
                    Text(boardError)
                        .font(.footnote)
                        .foregroundStyle(Theme.error)
                }
            } header: {
                Text("Project board")
            } footer: {
                Text(list.projectId == nil
                     ? "Creates a project and seeds Ready / Doing / Waiting status columns. Inbox and Done are virtual."
                     : "Removes the project + its status columns. This list will detach but keep its tasks.")
                    .font(.footnote)
            }

            // Recently completed window — picker + inline DatePicker for
            // since-specific-date. Mirrors the web's Advanced — Recently
            // completed window dropdown.
            Section {
                Picker("Recently completed", selection: $recentlyCompletedPresetId) {
                    ForEach(RECENTLY_COMPLETED_PRESETS, id: \.id) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                }
                .onChange(of: recentlyCompletedPresetId) { _, _ in
                    saveRecentlyCompletedWindow()
                }
                if recentlyCompletedPresetId == .sinceSpecificDate {
                    DatePicker(
                        "Since",
                        selection: $recentlyCompletedSpecificDate,
                        displayedComponents: .date
                    )
                    .onChange(of: recentlyCompletedSpecificDate) { _, _ in
                        saveRecentlyCompletedWindow()
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Controls which completed tasks stay visible in the default filter and in the board's Done column.")
                    .font(.footnote)
            }

            // Danger Zone
            Section(NSLocalizedString("messages.danger_zone", comment: "")) {
                Button(action: { showingDeleteConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text(NSLocalizedString("lists.delete_list", comment: ""))
                    }
                    .foregroundColor(Theme.error)
                }
            }
        })
        .scrollContentBackground(.hidden)
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
        .task {
            await loadMembers()
            await loadAIProviderStatus()
            // Only load repositories if user has AI providers configured
            if hasAIProviders {
                await loadRepositories()
            }
        }
        .fullScreenCover(isPresented: $showingImagePicker) {
            ImagePickerView(list: list) { imageUrl in
                saveListImage(imageUrl)
            }
        }
        .alert(NSLocalizedString("lists.delete_list", comment: ""), isPresented: $showingDeleteConfirmation) {
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) { }
            Button(NSLocalizedString("actions.delete", comment: ""), role: .destructive) {
                onDelete()
            }
        } message: {
            Text(NSLocalizedString("lists.delete_confirm", comment: ""))
        }
        .alert("Disable board?", isPresented: $showingDisableBoardConfirmation) {
            Button(NSLocalizedString("actions.cancel", comment: ""), role: .cancel) { }
            Button("Disable", role: .destructive) {
                disableBoard()
            }
        } message: {
            Text("This removes the project and its status columns. The list keeps its tasks, but completed tasks stay completed and active tasks lose any status.")
        }
    }

    private func saveBasicInfo() {
        var updated = list
        updated.name = listName
        updated.description = listDescription
        onUpdate(updated)
    }

    private func saveDefaults() {
        var updated = list
        updated.defaultAssigneeId = defaultAssigneeId
        updated.defaultPriority = defaultPriority.rawValue
        updated.defaultDueDate = defaultDueDate
        updated.defaultDueTime = defaultDueTime
        updated.defaultRepeating = defaultRepeating

        print("💾 [ListAdminTab] saveDefaults called:")
        print("  - list.defaultAssigneeId (original): \(list.defaultAssigneeId ?? "nil")")
        print("  - defaultAssigneeId (@State): \(defaultAssigneeId ?? "nil")")
        print("  - updated.defaultAssigneeId: \(updated.defaultAssigneeId ?? "nil")")

        onUpdate(updated)
    }

    private func loadMembers() async {
        do {
            try await memberService.fetchMembers(listId: list.id)
        } catch {
            print("❌ Failed to load members: \(error)")
        }
    }

    private func loadAIProviderStatus() async {
        loadingAIStatus = true

        do {
            print("🤖 [ListAdminTab] Loading AI provider status")
            let status = try await AstridAPIClient.shared.getGitHubStatus()
            hasAIProviders = !status.aiProviders.isEmpty || status.hasAIKeys
            print("✅ [ListAdminTab] AI providers configured: \(hasAIProviders)")
            print("  - AI providers: \(status.aiProviders)")
            print("  - Has AI keys: \(status.hasAIKeys)")
        } catch {
            print("❌ [ListAdminTab] Failed to load AI provider status: \(error)")
            hasAIProviders = false
        }

        loadingAIStatus = false
    }

    private func loadRepositories(refresh: Bool = false) async {
        loadingRepositories = true
        repositoriesError = nil

        do {
            print("📦 [ListAdminTab] Loading GitHub repositories (refresh: \(refresh))")
            let response = try await AstridAPIClient.shared.getGitHubRepositories(refresh: refresh)
            availableRepositories = response.repositories
            print("✅ [ListAdminTab] Loaded \(availableRepositories.count) repositories")
        } catch {
            print("❌ [ListAdminTab] Failed to load repositories: \(error)")
            repositoriesError = "Failed to load repositories. Please check your GitHub connection."
        }

        loadingRepositories = false
    }

    private func saveGitHubSettings() {
        var updated = list
        updated.githubRepositoryId = githubRepositoryId

        print("📋 [ListAdminTab] Saving GitHub settings:")
        print("  - Repository ID: \(githubRepositoryId ?? "nil (none)")")

        onUpdate(updated)
    }

    private func saveListImage(_ imageUrl: String) {
        // Clear cached images so new image loads fresh
        ImageCache.shared.clearSecureFilesCache()

        // Update local state immediately for instant preview update
        currentImageUrl = imageUrl

        // OPTIMISTIC UPDATE: Update sidebar immediately (before server roundtrip)
        // Must replace entire array to trigger @Published notification (structs are value types)
        var updatedLists = ListService.shared.lists
        if let index = updatedLists.firstIndex(where: { $0.id == list.id }) {
            updatedLists[index].imageUrl = imageUrl
            ListService.shared.lists = updatedLists  // This triggers @Published
            print("✅ [ListAdminTab] Optimistically updated sidebar image")
        }

        // Update list via onUpdate callback (persists to server in background)
        var updated = list
        updated.imageUrl = imageUrl

        print("📋 [ListAdminTab] Saving list image:")
        print("  - Image URL: \(imageUrl)")

        onUpdate(updated)
    }

    // MARK: - Project board

    private func createBoard() {
        boardOperationInFlight = true
        boardError = nil
        _Concurrency.Task {
            do {
                let project = try await ProjectService.shared.createProject(
                    name: list.name,
                    description: list.description,
                    color: list.color,
                    imageUrl: list.imageUrl
                )
                // Server-side: attaching the existing list to the new project
                // is a follow-on. For now the project is created standalone
                // with its three seeded status lists. Mirror what the web
                // does today (web also creates a fresh project per board).
                _ = project
                await MainActor.run {
                    boardOperationInFlight = false
                }
            } catch {
                await MainActor.run {
                    boardOperationInFlight = false
                    boardError = "Couldn't create board: \(error.localizedDescription)"
                }
            }
        }
    }

    private func disableBoard() {
        guard let projectId = list.projectId else { return }
        boardOperationInFlight = true
        boardError = nil
        _Concurrency.Task {
            do {
                _ = try await ProjectService.shared.deleteProject(id: projectId)
                await MainActor.run {
                    boardOperationInFlight = false
                }
            } catch {
                await MainActor.run {
                    boardOperationInFlight = false
                    boardError = "Couldn't disable board: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Recently completed window

    private func saveRecentlyCompletedWindow() {
        let window: RecentlyCompletedWindow?
        if recentlyCompletedPresetId == .sinceSpecificDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            window = .sinceDate(date: formatter.string(from: recentlyCompletedSpecificDate))
        } else {
            window = presetForValue(recentlyCompletedPresetId)
        }
        var updated = list
        updated.recentlyCompletedWindow = window
        onUpdate(updated)
    }
}
