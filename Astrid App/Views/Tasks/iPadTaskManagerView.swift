import SwiftUI

/// Wrapper view that adapts TaskListView for iPad side panel presentation
/// Instead of opening tasks in a sheet, it sets the selectedTask binding
/// which the parent iPadTaskManagerView uses to show the detail panel
private struct iPadTaskListView: View {
    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool
    @Binding var featuredList: TaskList?
    @Binding var searchText: String
    @Binding var selectedTask: Task?
    var onMenuTap: (() -> Void)?

    var body: some View {
        TaskListView(
            selectedListId: $selectedListId,
            isViewingFromFeatured: $isViewingFromFeatured,
            featuredList: $featuredList,
            searchText: $searchText,
            selectedTaskForPanel: $selectedTask,
            onMenuTap: onMenuTap
        )
    }
}

/// iPad-specific task manager view with adaptive column layout
/// Landscape: sidebar | task list | task details (always 3-column, details ~50% width)
/// Portrait: task list | task details (sidebar hidden, accessible via hamburger menu)
struct iPadTaskManagerView: View {
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @AppStorage("iPadLandscapeColumns") private var landscapeColumns: Int = 3
    @AppStorage("iPadPortraitMode") private var portraitMode: String = "twoColumn"
    @EnvironmentObject var authManager: AuthManager

    @Binding var selectedListId: String?
    @Binding var isViewingFromFeatured: Bool
    @Binding var featuredList: TaskList?

    // Search state (managed at this level, passed to sidebar and task list)
    @State private var searchText = ""
    @State private var shouldScrollSidebarToTop = false

    // Selected task for detail panel
    @State private var selectedTask: Task?
    @State private var showChatPanel = false  // Toggle chat in right panel

    // Portrait mode: sidebar shown via sliding overlay (like iPhone)
    @State private var showingSidebar = false
    @State private var dragOffset: CGFloat = 0
    @State private var hasScrolledDuringDrag = false

    // Detect orientation
    private var isLandscape: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .compact
    }

    // Calculate animation progress for sidebar slide (portrait mode)
    private var sidebarProgress: CGFloat {
        let targetOffset = UIScreen.main.bounds.width * 0.40  // 40% width for iPad sidebar
        if showingSidebar {
            let currentOffset = targetOffset + dragOffset
            return max(0, min(1, currentOffset / targetOffset))
        } else {
            return max(0, min(1, dragOffset / targetOffset))
        }
    }

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: ThemeMode {
        if themeMode == .auto {
            return colorScheme == .dark ? .dark : .light
        }
        return themeMode
    }

    // Theme-aware background
    @ViewBuilder
    private var themeBackground: some View {
        switch effectiveTheme {
        case .ocean:
            Theme.Ocean.bgPrimary  // Cyan for Ocean
        case .dark:
            Theme.Dark.bgPrimary  // Dark gray for Dark theme
        case .light:
            Theme.bgPrimary  // White for Light theme
        case .auto:
            // Should never reach here since effectiveTheme resolves auto
            Theme.bgPrimary
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Use geometry to detect landscape (width > height) since iPad has .regular size class in both orientations
            let isLandscapeOrientation = geometry.size.width > geometry.size.height

            if isLandscapeOrientation {
                if landscapeColumns == 2 {
                    // Landscape 2-column: sliding sidebar (like portrait)
                    threeColumnPortraitLayout(width: geometry.size.width, isLandscape: true)
                } else {
                    // Landscape 3-column: sidebar permanently visible | tasks | details
                    threeColumnLandscapeLayout(width: geometry.size.width)
                }
            } else {
                if portraitMode == "iPhone" {
                    // Portrait single-column is now handled by MainTabView using iPhoneLayout.
                    // This branch is a fallback — use portrait 2-column layout.
                    threeColumnPortraitLayout(width: geometry.size.width, isLandscape: false)
                } else {
                    // Portrait 2-column: sliding sidebar
                    threeColumnPortraitLayout(width: geometry.size.width, isLandscape: false)
                }
            }
        }
        .withReminderPresentation()
        // Close task details when list changes
        .onChange(of: selectedListId) { _, _ in
            withAnimation(.easeInOut(duration: 0.25)) {
                selectedTask = nil
                showChatPanel = false
            }
        }
    }

    // MARK: - 3-Column Landscape Layout (Sidebar permanently visible)

    @ViewBuilder
    private func threeColumnLandscapeLayout(width: CGFloat) -> some View {
        ZStack {
            // Full-screen background (fills safe areas — fixes black in dark mode)
            themeBackground
                .ignoresSafeArea()

        HStack(spacing: 0) {
            // Left: Sidebar (28% - permanently visible)
            NavigationStack {
                ListSidebarView(
                    selectedListId: $selectedListId,
                    isViewingFromFeatured: $isViewingFromFeatured,
                    featuredList: $featuredList,
                    searchText: $searchText,
                    shouldScrollToTop: $shouldScrollSidebarToTop
                )
                .environmentObject(authManager)
            }
            .frame(width: width * 0.28)
            .background(themeBackground)

            Divider()

            // Middle: Task List, Settings, or Profile (22% when detail/chat shown, 72% when neither)
            if selectedListId == "settings" {
                NavigationStack {
                    SettingsView()
                        .environmentObject(authManager)
                }
                .frame(width: (selectedTask != nil || showChatPanel) ? width * 0.32 : width * 0.72)
            } else if selectedListId == "profile", let userId = authManager.userId {
                NavigationStack {
                    UserProfileView(userId: userId, isRootDestination: true)
                        .environmentObject(authManager)
                }
                .frame(width: (selectedTask != nil || showChatPanel) ? width * 0.32 : width * 0.72)
            } else {
                // No onMenuTap - hamburger button does nothing in landscape since sidebar is always visible
                iPadTaskListView(
                    selectedListId: $selectedListId,
                    isViewingFromFeatured: $isViewingFromFeatured,
                    featuredList: $featuredList,
                    searchText: $searchText,
                    selectedTask: $selectedTask,
                    onMenuTap: nil  // Sidebar always visible in landscape
                )
                .frame(width: (selectedTask != nil || showChatPanel) ? width * 0.32 : width * 0.72)
            }

            // Right panel: Task Detail or Chat (35%)
            if selectedTask != nil {
                Divider()

                VStack(spacing: 0) {
                    if showChatPanel, let listId = selectedListId {
                        ChatPanelView(listId: listId, onSignedIn: { showChatPanel = false })
                    } else {
                        taskDetailPanel
                    }
                }
                .frame(width: width * 0.40)
            } else if showChatPanel, let listId = selectedListId {
                // Show chat panel even with no task selected
                Divider()

                ChatPanelView(listId: listId, onSignedIn: { showChatPanel = false })
                    .frame(width: width * 0.40)
            }
        }
        } // ZStack
    }

    // MARK: - Portrait Layout (Sliding sidebar like iPhone)
    // Portrait mode: sidebar slides in from left when hamburger button is tapped
    // Task list and details slide right to reveal sidebar underneath

    @ViewBuilder
    private func threeColumnPortraitLayout(width: CGFloat, isLandscape: Bool) -> some View {
        let sidebarWidth = width * 0.40  // 40% sidebar width for iPad

        ZStack(alignment: .leading) {
            // Full-screen background
            themeBackground
                .ignoresSafeArea()

            // Sidebar - always rendered underneath, visible when content slides right
            ZStack {
                themeBackground
                    .ignoresSafeArea()

                NavigationStack {
                    ListSidebarView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList,
                        searchText: $searchText,
                        shouldScrollToTop: $shouldScrollSidebarToTop,
                        onListTap: {
                            // Scroll sidebar to top first, then close
                            shouldScrollSidebarToTop = true
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                    )
                    .environmentObject(authManager)
                }
            }
            .frame(width: sidebarWidth)
            // Subtle rise animation synced with drag progress
            .scaleEffect(0.95 + (0.05 * sidebarProgress))
            .offset(y: 20 - (20 * sidebarProgress))
            .opacity(0.8 + (0.2 * sidebarProgress))

            // Main content - slides right to reveal sidebar
            HStack(spacing: 0) {
                // Task List, Settings, or Profile
                if selectedListId == "settings" {
                    NavigationStack {
                        SettingsView(onMenuTap: {
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        })
                            .environmentObject(authManager)
                    }
                    .frame(width: selectedTask != nil ? width * 0.50 : width)
                } else if selectedListId == "profile", let userId = authManager.userId {
                    NavigationStack {
                        UserProfileView(userId: userId, isRootDestination: true)
                            .environmentObject(authManager)
                            .simultaneousGesture(
                                DragGesture(minimumDistance: 20)
                                    .onEnded { value in
                                        let isHorizontal = value.translation.width > abs(value.translation.height)
                                        let isRight = value.translation.width > 0
                                        let meetsThreshold = value.translation.width > 80
                                            || value.predictedEndTranslation.width > 200
                                        if isHorizontal && isRight && meetsThreshold {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                                showingSidebar = true
                                            }
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                                let impact = UIImpactFeedbackGenerator(style: .light)
                                                impact.impactOccurred()
                                            }
                                        }
                                    }
                            )
                    }
                    .frame(width: selectedTask != nil ? width * 0.50 : width)
                } else {
                    iPadTaskListView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList,
                        searchText: $searchText,
                        selectedTask: $selectedTask,
                        onMenuTap: {
                            // Dismiss keyboard first
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            // Open sidebar
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                    )
                    .frame(width: selectedTask != nil ? width * 0.50 : width)
                }

                // Task Detail Panel - animates with task list
                if selectedTask != nil {
                    Divider()
                    taskDetailPanel
                        .frame(width: width * 0.50)
                }
            }
            .frame(width: width)
            .offset(x: showingSidebar ? sidebarWidth + dragOffset : dragOffset)
            .shadow(color: .black.opacity(0.3 * sidebarProgress), radius: 10, x: -5, y: 0)
            .opacity(1.0 - (0.3 * sidebarProgress))
            .saturation(1.0 - (0.5 * sidebarProgress))
            .allowsHitTesting(sidebarProgress < 0.95)
            // Swipe left-to-right on the LIST. In PORTRAIT it reveals the sliding
            // sidebar (matches iPhone), closing any open task on the way. In
            // LANDSCAPE there's room for everything, so it only closes the open
            // task to reveal the list — it must NOT pull in the sidebar. A swipe
            // that starts over the open task's panel is handled by the panel's own
            // gesture, so it's excluded here.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        guard !showingSidebar else { return }
                        guard isRightwardSwipeGesture(
                            translationWidth: value.translation.width,
                            translationHeight: value.translation.height,
                            predictedEndTranslationWidth: value.predictedEndTranslation.width
                        ) else { return }
                        // Only act for swipes that begin in the list area; the task
                        // detail panel (right half when open) handles its own.
                        let listWidth = selectedTask != nil ? width * 0.5 : width
                        guard value.startLocation.x < listWidth else { return }
                        if isLandscape && selectedTask != nil {
                            // Landscape WITH a task open: just close it to reveal the
                            // list — there's room for everything, so don't also pull
                            // in the sidebar.
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedTask = nil
                            }
                        } else {
                            // Otherwise — portrait, or a landscape list/board with no
                            // task open — reveal the sliding sidebar (the "open list
                            // menu" gesture), closing any open task on the way.
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedTask = nil
                                showingSidebar = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    }
            )

            // Overlay to capture taps/drags when sidebar is open
            if showingSidebar {
                HStack(spacing: 0) {
                    // Left side - sidebar area, taps pass through
                    Color.clear
                        .frame(width: sidebarWidth)
                        .allowsHitTesting(false)

                    // Right side - main content area, captures drags and taps to close
                    Color.clear
                        .frame(width: width - sidebarWidth)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    if !hasScrolledDuringDrag && value.translation.width < 0 {
                                        shouldScrollSidebarToTop = true
                                        hasScrolledDuringDrag = true
                                    }
                                    if value.translation.width < 0 {
                                        dragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    hasScrolledDuringDrag = false
                                    if value.translation.width < -100 || value.predictedEndTranslation.width < -200 {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            showingSidebar = false
                                            dragOffset = 0
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            shouldScrollSidebarToTop = false
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                                            dragOffset = 0
                                        }
                                        shouldScrollSidebarToTop = false
                                    }
                                }
                        )
                        .onTapGesture {
                            shouldScrollSidebarToTop = true
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - Task Detail Panel

    @ViewBuilder
    private var taskDetailPanel: some View {
        if let task = selectedTask {
            // Wrap with theme background and padding to align with task list
            NavigationStack {
                TaskDetailViewNew(task: task, isReadOnly: shouldShowTaskAsReadOnly(task: task), onClose: { selectedTask = nil })
            }
            .background(themeBackground)  // Match theme inside NavigationStack (fixes black in dark mode)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.top, 8)      // Top margin (aligns with floating header)
            .padding(.bottom, 4)   // Bottom margin (aligns with quick add input)
            .padding(.trailing, 8) // Right margin (matches left side of screen)
            .background(themeBackground)
            // Swipe left-to-right on the open task closes it (matches iPhone
            // swipe-back). The detail panel is a side panel on iPad, not a pushed
            // view, so this gesture is what dismisses it.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if isRightwardSwipeGesture(
                            translationWidth: value.translation.width,
                            translationHeight: value.translation.height,
                            predictedEndTranslationWidth: value.predictedEndTranslation.width
                        ) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selectedTask = nil
                            }
                        }
                    }
            )
            .id(task.id) // Force view refresh when task changes
        }
    }


    // MARK: - iPhone-Style Single Column Layout (for iPad portrait)

    @ViewBuilder
    private func iPhoneStyleLayout(width: CGFloat) -> some View {
        let sidebarWidth = width * 0.40

        ZStack(alignment: .leading) {
            themeBackground
                .ignoresSafeArea()

            // Sidebar underneath
            ZStack {
                themeBackground
                    .ignoresSafeArea()
                NavigationStack {
                    ListSidebarView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList,
                        searchText: $searchText,
                        shouldScrollToTop: $shouldScrollSidebarToTop,
                        onListTap: {
                            shouldScrollSidebarToTop = true
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                    )
                    .environmentObject(authManager)
                }
            }
            .frame(width: sidebarWidth)
            .scaleEffect(0.95 + (0.05 * sidebarProgress))
            .offset(y: 20 - (20 * sidebarProgress))
            .opacity(0.8 + (0.2 * sidebarProgress))

            // Main content — full width, slides right
            iPhoneStyleMainContent(width: width, sidebarWidth: sidebarWidth)
            .offset(x: showingSidebar ? sidebarWidth + dragOffset : dragOffset)
            .shadow(color: .black.opacity(0.3 * sidebarProgress), radius: 10, x: -5, y: 0)
            .opacity(1.0 - (0.3 * sidebarProgress))
            .saturation(1.0 - (0.5 * sidebarProgress))
            .allowsHitTesting(sidebarProgress < 0.95)

            // Sidebar close overlay
            if showingSidebar {
                HStack(spacing: 0) {
                    Color.clear
                        .frame(width: sidebarWidth)
                        .allowsHitTesting(false)
                    Color.clear
                        .frame(width: width - sidebarWidth)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            shouldScrollSidebarToTop = true
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showingSidebar = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: - iPhone-Style Main Content (extracted for type-checker)

    @ViewBuilder
    private func iPhoneStyleMainContent(width: CGFloat, sidebarWidth: CGFloat) -> some View {
        NavigationStack {
            if selectedListId == "settings" {
                SettingsView(onMenuTap: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showingSidebar = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                })
                    .environmentObject(authManager)
            } else if selectedListId == "profile", let userId = authManager.userId {
                UserProfileView(userId: userId, isRootDestination: true)
                    .environmentObject(authManager)
            } else {
                TaskListView(
                    selectedListId: $selectedListId,
                    isViewingFromFeatured: $isViewingFromFeatured,
                    featuredList: $featuredList,
                    searchText: $searchText,
                    forcePushNavigation: true,
                    onMenuTap: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            showingSidebar = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
                )
            }
        }
        .frame(width: width)
    }

    // MARK: - Helper Methods

    /// Determine if a task should be shown as read-only
    private func shouldShowTaskAsReadOnly(task: Task) -> Bool {
        guard let currentUserId = AuthManager.shared.userId else {
            return true
        }

        // Featured public lists are read-only unless you created the task
        if isViewingFromFeatured && !task.isCreatedBy(currentUserId) {
            return true
        }

        return false
    }
}
