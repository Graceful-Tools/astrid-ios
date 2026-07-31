import SwiftUI

struct ListSidebarView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var listService = ListService.shared
    @StateObject private var taskService = TaskService.shared
    @StateObject private var syncManager = SyncManager.shared
    private let profileCache = ProfileCache.shared
    private let apiClient = RemoteResourceService.shared
    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool  // Track if viewing from featured section
    @Binding var featuredList: TaskList?  // Store the featured list data
    @Binding var searchText: String  // Search text for filtering tasks
    @Binding var shouldScrollToTop: Bool  // Trigger to scroll sidebar to top
    var onListTap: (() -> Void)?  // Optional callback when any list is tapped
    @State private var showingAddList = false
    @State private var publicLists: [TaskList] = []
    @State private var hasLoadedInitialData = false  // Prevent infinite .task loop

    // Cached filtered lists to avoid recomputation on every render
    @State private var _cachedCollaborativeLists: [TaskList] = []
    @State private var _cachedSuggestedLists: [TaskList] = []

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: ThemeMode {
        if themeMode == .auto {
            return colorScheme == .dark ? .dark : .light
        }
        return themeMode
    }

    // Theme-aware background color
    private var themeBackgroundColor: Color {
        switch effectiveTheme {
        case .ocean:
            return Theme.Ocean.bgPrimary  // Cyan for Ocean
        case .dark:
            return Theme.Dark.bgPrimary  // Dark gray for Dark theme
        case .light:
            return Theme.bgPrimary  // White for Light theme
        case .auto:
            // Should never reach here since effectiveTheme resolves auto
            return Theme.bgPrimary
        }
    }

    // Split public lists by type - use cached values to avoid recomputation
    private var collaborativePublicLists: [TaskList] {
        return _cachedCollaborativeLists
    }

    private var suggestedPublicLists: [TaskList] {
        return _cachedSuggestedLists
    }

    // Update cached lists when publicLists changes
    private func updateCachedPublicLists() {
        _cachedCollaborativeLists = publicLists.filter { $0.publicListType == "collaborative" }
        _cachedSuggestedLists = publicLists.filter { $0.publicListType == "copy_only" || $0.publicListType == nil }
    }


    var body: some View {
        ScrollViewReader { proxy in
            List {
                userProfileSection
                    .id("top")
                myTasksSection
                searchRow
                favoritesSection
                yourListsSection
                featuredCollaborativeSection
                featuredSuggestedSection
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(themeBackgroundColor)  // Apply theme background color directly
            .listRowBackground(Color.clear)  // Make rows transparent to show themed background
            .navigationBarHidden(true)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showingAddList) {
                NavigationStack {
                    ListEditView()
                }
            }
            .task {
                // Only load data once on initial appearance to prevent infinite loop
                guard !hasLoadedInitialData else { return }
                hasLoadedInitialData = true
                await loadData()

                // Prefetch current user's profile in background for instant loading
                if let userId = authManager.currentUser?.id {
                    await profileCache.prefetchProfile(userId: userId)
                }
            }
            .onChange(of: selectedListId) { _, _ in
                // Scroll to top when list selection changes
                withAnimation {
                    proxy.scrollTo("top", anchor: .top)
                }
            }
            .onChange(of: shouldScrollToTop) { _, shouldScroll in
                // Scroll to top when triggered (e.g., sidebar closing)
                // Quick animation (0.2s) so it's visible but completes before close animation
                if shouldScroll {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("top", anchor: .top)
                    }
                }
            }
        }
    }

    // MARK: - User Profile Section

    private var userProfileSection: some View {
        Section {
            HStack(spacing: Theme.spacing12) {
                // Profile tap area (avatar + name)
                Button {
                    if authManager.isLocalOnlyMode {
                        // Local-only users get sign-in prompt (handled separately)
                    } else {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        NotificationCenter.default.post(name: .openProfile, object: nil)
                    }
                } label: {
                    HStack(spacing: Theme.spacing12) {
                        // Avatar
                        if authManager.isLocalOnlyMode {
                            Circle()
                                .fill(Theme.accent.opacity(0.15))
                                .frame(width: 40, height: 40)
                                .overlay {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .font(.system(size: 22))
                                        .foregroundColor(Theme.accent)
                                }
                        } else if let user = authManager.currentUser,
                           let imageUrl = user.image,
                           let url = URL(string: imageUrl) {
                            CachedAsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                            } placeholder: {
                                Circle()
                                    .fill(Theme.accent)
                                    .overlay {
                                        if let user = authManager.currentUser {
                                            Text(user.initials)
                                                .foregroundColor(.white)
                                                .font(Theme.Typography.body())
                                        }
                                    }
                            }
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                        } else {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 40, height: 40)
                                .overlay {
                                    if let user = authManager.currentUser {
                                        Text(user.initials)
                                            .foregroundColor(.white)
                                            .font(Theme.Typography.body())
                                    }
                                }
                        }

                        // User info
                        VStack(alignment: .leading, spacing: 2) {
                            if authManager.isLocalOnlyMode {
                                Text(NSLocalizedString("auth.sign_in_short", comment: "Sign In"))
                                    .font(Theme.Typography.body())
                                    .foregroundColor(Theme.accent)
                                Text(NSLocalizedString("profile.sign_in_to_sync", comment: "Sign in to sync"))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            } else if let user = authManager.currentUser {
                                // Name only. The email wrapped onto a second line in the sidebar's
                                // narrow column ("jonparis@gmail.-\ncom") and told the signed-in
                                // user nothing they did not know. It is still on the profile this
                                // row opens, and in Settings › Account.
                                Text(user.displayName)
                                    .font(Theme.Typography.body())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                Spacer()

                // Settings gear button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    NotificationCenter.default.post(name: .openSettings, object: nil)
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        .padding(Theme.spacing8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Search Row

    private var searchRow: some View {
        Section {
            Button {
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
                selectedListId = "search"
                searchText = "" // Clear previous search
                onListTap?()
            } label: {
                HStack(spacing: Theme.spacing12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                        .font(Theme.Typography.body())

                    Text(NSLocalizedString("tasks.search_tasks_placeholder", comment: "Search tasks"))
                        .font(Theme.Typography.body())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                    Spacer()
                }
                .padding(.vertical, Theme.spacing8)
                .padding(.horizontal, Theme.spacing12)
            }
            .buttonStyle(ListRowButtonStyle(isSelected: selectedListId == "search"))
        }
    }

    // Settings is now in UserProfileView (accessible from the profile section above)

    // MARK: - Sections

    private var myTasksSection: some View {
        Section {
            myTasksRow
        }
    }

    @ViewBuilder
    private var favoritesSection: some View {
        if !favoriteLists.isEmpty {
            Section(NSLocalizedString("navigation.favorites", comment: "")) {
                ForEach(favoriteLists) { list in
                    ListRowView(
                        list: list,
                        taskCount: getTaskCount(for: list),
                        isSelected: selectedListId == list.id,
                        onTap: {
                            selectedListId = list.id
                            isViewingFromFeatured = false  // Regular list, not from featured
                            featuredList = nil  // Clear featured list
                            searchText = ""  // Clear search when switching lists
                            onListTap?()
                        }
                    )
                    .id("\(list.id)-\(list.imageUrl ?? "default")") // Force refresh when image changes
                }
            }
        }
    }

    private var yourListsSection: some View {
        Section {
            addListButton

            ForEach(regularLists) { list in
                ListRowView(
                    list: list,
                    taskCount: getTaskCount(for: list),
                    isSelected: selectedListId == list.id,
                    onTap: {
                        selectedListId = list.id
                        isViewingFromFeatured = false  // Regular list, not from featured
                        featuredList = nil  // Clear featured list
                        searchText = ""  // Clear search when switching lists
                        onListTap?()
                    }
                )
                .id("\(list.id)-\(list.imageUrl ?? "default")") // Force refresh when image changes
            }
        } header: {
            Text(NSLocalizedString("navigation.lists", comment: ""))
        }
    }

    @ViewBuilder
    private var featuredCollaborativeSection: some View {
        if !collaborativePublicLists.isEmpty {
            Section {
                // Header
                Text(NSLocalizedString("navigation.public_shared_lists", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .textCase(.uppercase)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.spacing12, bottom: Theme.spacing4, trailing: Theme.spacing12))

                // Show max 2 collaborative lists
                ForEach(collaborativePublicLists.prefix(2)) { list in
                    ListRowView(
                        list: list,
                        taskCount: getTaskCount(for: list),
                        isSelected: selectedListId == list.id,
                        onTap: {
                            print("🎯 [Collaborative] Tapped: \(list.name)")
                            selectedListId = list.id
                            isViewingFromFeatured = true
                            featuredList = list
                            searchText = ""  // Clear search when switching lists
                            onListTap?()
                        }
                    )
                    .id("\(list.id)-\(list.imageUrl ?? "default")") // Force refresh when image changes
                }

                // See all link if more than 2
                if collaborativePublicLists.count > 2 {
                    NavigationLink(NSLocalizedString("navigation.see_all_collaborative", comment: "")) {
                        PublicListBrowserView()
                    }
                    .font(Theme.Typography.caption1())
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    @ViewBuilder
    private var featuredSuggestedSection: some View {
        if !suggestedPublicLists.isEmpty {
            Section {
                // Header
                Text(NSLocalizedString("navigation.public_lists", comment: ""))
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .textCase(.uppercase)
                    .listRowInsets(EdgeInsets(top: 0, leading: Theme.spacing12, bottom: Theme.spacing4, trailing: Theme.spacing12))

                // Show max 2 suggested lists
                ForEach(suggestedPublicLists.prefix(2)) { list in
                    ListRowView(
                        list: list,
                        taskCount: getTaskCount(for: list),
                        isSelected: selectedListId == list.id,
                        onTap: {
                            print("🎯 [Suggested] Tapped: \(list.name)")
                            selectedListId = list.id
                            isViewingFromFeatured = true
                            featuredList = list
                            searchText = ""  // Clear search when switching lists
                            onListTap?()
                        }
                    )
                    .id("\(list.id)-\(list.imageUrl ?? "default")") // Force refresh when image changes
                }

                // See all link if more than 2
                if suggestedPublicLists.count > 2 {
                    NavigationLink(NSLocalizedString("navigation.see_all_suggested", comment: "")) {
                        PublicListBrowserView()
                    }
                    .font(Theme.Typography.caption1())
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private var addListButton: some View {
        Button {
            showingAddList = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(Theme.accent)
                Text(NSLocalizedString("navigation.add_list", comment: ""))
                    .foregroundColor(Theme.accent)
            }
        }
    }

    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: {
                _Concurrency.Task {
                    try? await syncData()
                }
            }) {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    // MARK: - My Tasks Row

    private var myTasksRow: some View {
        Button {
            // Haptic feedback on tap (matching ListRowView)
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            selectedListId = "my-tasks"
            isViewingFromFeatured = false  // Not viewing from featured
            featuredList = nil  // Clear featured list
            searchText = ""  // Clear search when switching lists
            onListTap?()
        } label: {
            HStack(spacing: Theme.spacing12) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 12, height: 12)

                Text(NSLocalizedString("navigation.my_tasks", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Spacer()

                // Filter icon to indicate this is a filtered view
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(Theme.Typography.footnote())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                // Count of tasks assigned to current user (always show, even when 0)
                Text("\(myTasksCount)")
                    .font(Theme.Typography.caption1())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .padding(.horizontal, Theme.spacing8)
                    .padding(.vertical, Theme.spacing4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Color.gray.opacity(0.1))
                    )
            }
            .padding(.vertical, Theme.spacing8)
            .padding(.horizontal, Theme.spacing12)
            .contentShape(Rectangle())  // Make entire row area tappable
        }
        .buttonStyle(ListRowButtonStyle(isSelected: selectedListId == "my-tasks"))
    }

    // MARK: - Computed Properties

    private var favoriteLists: [TaskList] {
        listService.lists
            .filter { $0.isFavorite == true }
            .sorted { ($0.favoriteOrder ?? 999) < ($1.favoriteOrder ?? 999) }
    }

    private var regularLists: [TaskList] {
        listService.lists
            .filter { $0.isFavorite != true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var myTasksCount: Int {
        // Count only tasks assigned to current user
        guard let currentUserId = authManager.userId else {
            return 0
        }
        return taskService.tasks.filter { !$0.completed && $0.assigneeId == currentUserId }.count
    }

    // MARK: - Helper Methods

    private func getTaskCount(for list: TaskList) -> Int {
        // For public lists, use the taskCount from the API
        if list.privacy == .PUBLIC && list.taskCount != nil {
            return list.taskCount ?? 0
        }

        if list.isVirtual == true {
            // Virtual list - apply filters
            return applyFilters(taskService.tasks, list: list).count
        } else {
            // Regular list - filter by membership AND incomplete only
            return taskService.tasks.filter { task in
                let isMember = task.lists?.contains(where: { $0.id == list.id }) ?? false
                return isMember && !task.completed
            }.count
        }
    }

    private func applyFilters(_ tasks: [Task], list: TaskList) -> [Task] {
        var filtered = tasks

        // Completion filter
        if let completion = list.filterCompletion {
            switch completion {
            case "completed":
                filtered = filtered.filter { $0.completed }
            case "incomplete":
                filtered = filtered.filter { !$0.completed }
            default:
                break
            }
        }

        // Priority filter
        if let priority = list.filterPriority, priority != "all" {
            if let priorityInt = Int(priority) {
                filtered = filtered.filter { $0.priority.rawValue == priorityInt }
            }
        }

        // Due date filter
        if let dueDate = list.filterDueDate, dueDate != "all" {
            filtered = applyDueDateFilter(filtered, filter: dueDate)
        }

        // Assignee filter
        if let assignee = list.filterAssignee, assignee != "all" {
            switch assignee {
            case "current_user":
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { $0.assigneeId == currentUserId }
                } else {
                    filtered = []
                }
            case "not_current_user":
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { $0.assigneeId != currentUserId && $0.assigneeId != nil }
                } else {
                    filtered = filtered.filter { $0.assigneeId != nil }
                }
            case "unassigned":
                filtered = filtered.filter { $0.assigneeId == nil }
            default:
                filtered = filtered.filter { $0.assigneeId == assignee }
            }
        }

        // Assigned By filter
        if let assignedBy = list.filterAssignedBy, assignedBy != "all" {
            switch assignedBy {
            case "current_user":
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { $0.isCreatedBy(currentUserId) }
                } else {
                    filtered = []
                }
            case "not_current_user":
                if let currentUserId = AuthManager.shared.userId {
                    filtered = filtered.filter { !$0.isCreatedBy(currentUserId) }
                }
            default:
                filtered = filtered.filter { $0.isCreatedBy(assignedBy) }
            }
        }

        // In Lists filter
        if let inLists = list.filterInLists, inLists != "dont_filter" {
            switch inLists {
            case "not_in_list":
                filtered = filtered.filter { task in
                    let hasLists = (task.lists?.count ?? 0) > 0
                    let hasListIds = (task.listIds?.count ?? 0) > 0
                    return !hasLists && !hasListIds
                }
            case "in_list":
                filtered = filtered.filter { task in
                    let hasLists = (task.lists?.count ?? 0) > 0
                    let hasListIds = (task.listIds?.count ?? 0) > 0
                    return hasLists || hasListIds
                }
            case "public_lists":
                filtered = filtered.filter { task in
                    task.lists?.contains(where: { $0.privacy == .PUBLIC }) ?? false
                }
            default:
                break
            }
        }

        return filtered
    }

    private func applyDueDateFilter(_ tasks: [Task], filter: String) -> [Task] {
        let now = Date()
        let calendar = Calendar.current

        return tasks.filter { task in
            guard let dueDate = task.dueDateTime else {
                return filter == "no_date"
            }

            switch filter {
            case "overdue":
                return dueDate < now && !task.completed
            case "today":
                return calendar.isDateInToday(dueDate)
            case "this_week":
                let weekFromNow = calendar.date(byAdding: .day, value: 7, to: now)!
                return dueDate >= now && dueDate <= weekFromNow
            case "this_month":
                let monthFromNow = calendar.date(byAdding: .day, value: 30, to: now)!
                return dueDate >= now && dueDate <= monthFromNow
            case "no_date":
                return false
            default:
                return true
            }
        }
    }

    private func loadData() async {
        do {
            // Only fetch lists - tasks are fetched by SyncManager (called from TaskListView)
            // to avoid duplicate concurrent fetches
            _ = try await listService.fetchLists()
            await fetchPublicLists()
        } catch {
            print("❌ Failed to load data: \(error.localizedDescription)")
        }
    }

    private func syncData() async throws {
        // Only fetch lists - tasks are handled by SyncManager
        _ = try await listService.fetchLists()
        await fetchPublicLists()
    }

    private func fetchPublicLists() async {
        do {
            print("📡 [ListSidebarView] Fetching public lists...")
            let response = try await apiClient.getPublicLists(limit: 10, sortBy: "popular") // Fetch more to show 2 of each type

            // Convert PublicListData to TaskList
            publicLists = response.lists.map { listData in
                TaskList(
                    id: listData.id,
                    name: listData.name,
                    color: listData.color,
                    imageUrl: listData.imageUrl,
                    privacy: listData.privacy == "PUBLIC" ? .PUBLIC : .PRIVATE,
                    publicListType: listData.publicListType,
                    ownerId: listData.owner.id,
                    owner: User(
                        id: listData.owner.id,
                        email: listData.owner.email,
                        name: listData.owner.name,
                        image: listData.owner.image
                    ),
                    createdAt: listData.createdAt,
                    updatedAt: listData.updatedAt,
                    description: listData.description
                )
            }

            // Update cached filtered lists
            updateCachedPublicLists()

            #if DEBUG
            print("✅ [ListSidebarView] Fetched \(publicLists.count) public lists: \(_cachedCollaborativeLists.count) collaborative, \(_cachedSuggestedLists.count) suggested")
            #endif
        } catch {
            print("❌ [ListSidebarView] Failed to fetch public lists: \(error)")
            print("❌ Error details: \(error.localizedDescription)")
            publicLists = []
        }
    }
}

#Preview {
    NavigationStack {
        ListSidebarView(
            selectedListId: .constant(nil),
            isViewingFromFeatured: .constant(false),
            featuredList: .constant(nil),
            searchText: .constant(""),
            shouldScrollToTop: .constant(false)
        )
    }
}
