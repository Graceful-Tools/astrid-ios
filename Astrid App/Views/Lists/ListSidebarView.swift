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

    // The badges, recomputed only when tasks, lists or the user change (AITD-455).
    @State private var badgesMemo = Memo<BadgesMemoKey, Badges>()
    /// What each saved filter keeps, answered by astrid-core (AITD-460); asked again whenever
    /// the badges' inputs change.
    @State private var virtualCounts: [String: Int] = [:]

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
        // The split is the SHARED rule (dfb037c7) — Mac shows the same two sections, and two
        // copies of "what counts as collaborative" is how they come to disagree.
        _cachedCollaborativeLists = PublicListSections.collaborative(publicLists)
        _cachedSuggestedLists = PublicListSections.browsable(publicLists)
    }


    var body: some View {
        ScrollViewReader { proxy in
            List {
                brandHeaderSection
                    .id("top")
                myTasksSection
                favoritesSection
                yourListsSection
                featuredCollaborativeSection
                featuredSuggestedSection
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(themeBackgroundColor)  // Apply theme background color directly
            .listRowBackground(Color.clear)  // Make rows transparent to show themed background
            // Fixed under the lists, as mobile web's sidebar has it (AITD-497).
            .safeAreaInset(edge: .bottom, spacing: 0) {
                accountFooter
            }
            .navigationBarHidden(true)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $showingAddList) {
                NavigationStack {
                    ListEditView()
                }
            }
            // The saved filters' badges come from the core, off the main thread (AITD-460).
            .task(id: badgesKey) {
                let counts = await ListTaskCount.virtualCounts(
                    lists: badgesKey.publicLists + badgesKey.lists, currentUserId: badgesKey.userId,
                    session: AppCore.shared.session)
                if counts != virtualCounts { virtualCounts = counts }
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

    // MARK: - Brand Header

    /// Logo and wordmark left, search far right, as web's sidebar opens (AITD-494). The icon is
    /// the one way into search: the Search row that repeated it is gone (AITD-497).
    private var brandHeaderSection: some View {
        Section {
            SidebarBrandHeader(
                primary: colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary,
                muted: colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted,
                isSearchActive: selectedListId == "search"
            ) {
                openSearch(.headerIcon)
            }
        }
    }

    // MARK: - Account Footer

    /// The user card and the gear, fixed to the bottom of the sidebar rather than scrolling
    /// away with the lists (AITD-497) — where mobile web and the Mac already keep them.
    ///
    /// A floating glass panel, so the lists scrolling under it show through (AITD-501). It was an
    /// opaque band of the theme colour, which sliced the last visible row in half.
    private var accountFooter: some View {
        HStack(spacing: Theme.spacing12) {
            // Profile tap area (avatar + name)
            Button {
                if authManager.isLocalOnlyMode {
                    // Local-only users get sign-in prompt (handled separately)
                } else {
                    openAccountEntry(.userCard)
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
                            // user nothing they did not know. It is still in Settings, which
                            // this row opens, on the profile and under Account.
                            Text(user.displayName)
                                .font(Theme.Typography.body())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .buttonStyle(.plain)  // No longer a list row, which is what kept the label untinted

            Spacer()

            // Settings gear button
            Button {
                openAccountEntry(.gear)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    .padding(Theme.spacing8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // The symbol's own name was its label, so VoiceOver read "Gear Shape" and the UI
            // suite's search for "Settings" never found it (AITD-525).
            .accessibilityLabel(NSLocalizedString("settings", comment: "Settings"))
            .accessibilityIdentifier("sidebar.settings")
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing8)
        .modifier(AccountFooterGlass())
        .padding(.horizontal, Theme.spacing12)
        .padding(.bottom, Theme.spacing8)
    }

    /// Liquid Glass where the system has it; the theme's thin glass material before iOS 26.
    private struct AccountFooterGlass: ViewModifier {
        private let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.glassEffect(.regular, in: shape)
            } else {
                content.background(Theme.LiquidGlass.secondaryGlassMaterial, in: shape)
            }
        }
    }

    // MARK: - Search

    /// The header icon asks `SidebarSearchEntry` where it leads (AITD-494).
    private func openSearch(_ entry: SidebarSearchEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch entry.destination {
        case .search:
            selectedListId = "search"
            searchText = "" // Clear previous search
            onListTap?()
        }
    }

    /// The user card and the gear both ask `SidebarAccountEntry` where they lead (AITD-493).
    private func openAccountEntry(_ entry: SidebarAccountEntry) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch entry.destination {
        case .settings: NotificationCenter.default.post(name: .openSettings, object: nil)
        case .profile: NotificationCenter.default.post(name: .openProfile, object: nil)
        }
    }

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
                        taskCount: badges.lists[list.id] ?? 0,
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
                    taskCount: badges.lists[list.id] ?? 0,
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
                        taskCount: badges.lists[list.id] ?? 0,
                        isSelected: selectedListId == list.id,
                        onTap: {
                            AppLog.debug("🎯 [Collaborative] Tapped: \(list.name)")
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
                        taskCount: badges.lists[list.id] ?? 0,
                        isSelected: selectedListId == list.id,
                        onTap: {
                            AppLog.debug("🎯 [Suggested] Tapped: \(list.name)")
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
            HStack(spacing: SidebarBrandHeader.spacing) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(Theme.accent)
                    .frame(width: SidebarBrandHeader.logoSize)
                Text(NSLocalizedString("navigation.add_list", comment: ""))
                    .foregroundColor(Theme.accent)
            }
        }
        .accessibilityIdentifier("sidebar.addList")
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
            // In the logo's column, as the list rows are (AITD-502).
            HStack(spacing: SidebarBrandHeader.spacing) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 12, height: 12)
                    .frame(width: SidebarBrandHeader.logoSize)

                Text(NSLocalizedString("navigation.my_tasks", comment: ""))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                Spacer()

                // Filter icon to indicate this is a filtered view
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(Theme.Typography.footnote())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)

                // Count of tasks assigned to current user (always show, even when 0)
                Text("\(badges.myTasks)")
                    .font(Theme.Typography.callout())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .padding(.horizontal, Theme.spacing8)
                    .padding(.vertical, Theme.spacing4)
                    .background(
                        Capsule()
                            .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Color.gray.opacity(0.1))
                    )
            }
            .padding(.vertical, Theme.spacing8)
            .padding(.trailing, Theme.spacing4)
            .contentShape(Rectangle())  // Make entire row area tappable
        }
        .buttonStyle(ListRowButtonStyle(isSelected: selectedListId == "my-tasks"))
        .accessibilityIdentifier("sidebar.myTasks")
    }

    // MARK: - Computed Properties

    private var favoriteLists: [TaskList] {
        listService.lists
            .filter { $0.isDomainList && $0.isFavorite == true }
            .sorted { ($0.favoriteOrder ?? 999) < ($1.favoriteOrder ?? 999) }
    }

    private var regularLists: [TaskList] {
        listService.lists
            .filter { $0.isDomainList && $0.isFavorite != true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private struct BadgesKey: Equatable {
        let tasks: [Task]
        let lists: [TaskList]
        let publicLists: [TaskList]
        let userId: String?
    }

    private struct BadgesMemoKey: Equatable {
        let inputs: BadgesKey
        let virtualCounts: [String: Int]
    }

    private struct Badges {
        let lists: [String: Int]
        let myTasks: Int
    }

    /// Every badge in the sidebar, through the SHARED rule (AITD-414), in ONE pass (AITD-455).
    ///
    /// Each row used to call `ListTaskCount.count` itself, which is O(lists × tasks) on every
    /// redraw — and a virtual list re-runs the whole filter pipeline. The Mac memoizes
    /// `ListTaskCount.counts`; this does the same, keyed on what the counts are made of.
    private var badgesKey: BadgesKey {
        BadgesKey(tasks: taskService.tasks, lists: listService.lists,
                  publicLists: publicLists, userId: authManager.userId)
    }

    private var badges: Badges {
        let key = badgesKey
        let userId = key.userId
        return badgesMemo.value(for: BadgesMemoKey(inputs: key, virtualCounts: virtualCounts)) {
            let tasks = key.tasks
            // Public lists badge too. Your own copy of a list goes last so it wins when a list is
            // in both — that is the copy its own row used to count.
            let counts = ListTaskCount.counts(tasks, lists: key.publicLists + key.lists,
                                              virtualCounts: virtualCounts)
            // Count only tasks assigned to current user
            let myTasks = userId.map { id in tasks.filter { !$0.completed && $0.assigneeId == id }.count } ?? 0
            return Badges(lists: counts, myTasks: myTasks)
        }
    }

    private func loadData() async {
        do {
            // Only fetch lists - tasks are fetched by SyncManager (called from TaskListView)
            // to avoid duplicate concurrent fetches
            _ = try await listService.fetchLists()
            await fetchPublicLists()
        } catch {
            AppLog.debug("❌ Failed to load data: \(error.localizedDescription)")
        }
    }

    private func syncData() async throws {
        // Only fetch lists - tasks are handled by SyncManager
        _ = try await listService.fetchLists()
        await fetchPublicLists()
    }

    private func fetchPublicLists() async {
        do {
            AppLog.debug("📡 [ListSidebarView] Fetching public lists...")
            let response = try await apiClient.getPublicLists(limit: 10, sortBy: "popular") // Fetch more to show 2 of each type

            // One shared mapper (AITD-319) — this was written out verbatim here and in
            // PublicListBrowserView, and a third, shorter time on the Mac.
            publicLists = response.lists.map { listData in
                TaskList(publicList: listData)
            }

            // Update cached filtered lists
            updateCachedPublicLists()

            #if DEBUG
            AppLog.debug("✅ [ListSidebarView] Fetched \(publicLists.count) public lists: \(_cachedCollaborativeLists.count) collaborative, \(_cachedSuggestedLists.count) suggested")
            #endif
        } catch {
            AppLog.debug("❌ [ListSidebarView] Failed to fetch public lists: \(error)")
            AppLog.debug("❌ Error details: \(error.localizedDescription)")
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
