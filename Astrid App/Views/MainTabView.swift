import SwiftUI


struct MainTabView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var listPresenter = ListPresenter.shared
    @State private var selectedListId: String? = "my-tasks"  // Default to My Tasks
    @State private var isViewingFromFeatured: Bool = false  // Track if viewing a public list from featured
    @State private var featuredList: TaskList? = nil  // Store the featured list data
    @State private var searchText = ""  // Search text shared between sidebar and task list
    @State private var showSidebar = false
    @State private var dragOffset: CGFloat = 0
    @State private var isShowingTaskDetail = false  // Track if task detail is pushed
    @State private var shouldScrollSidebarToTop = false  // Flag to control sidebar scroll behavior
    @State private var hasScrolledDuringDrag = false  // Track if we've scrolled during current drag

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

    // Solid color version for toolbar backgrounds (toolbarBackground requires ShapeStyle)
    private var themeBackgroundColor: Color {
        switch effectiveTheme {
        case .ocean:
            return Theme.Ocean.bgPrimary  // Cyan
        case .dark:
            return Theme.Dark.bgPrimary  // Dark gray
        case .light:
            return Theme.bgPrimary  // White
        case .auto:
            // Should never reach here since effectiveTheme resolves auto
            return Theme.bgPrimary
        }
    }

    var body: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                // iPad: Use split view with list sidebar
                iPadLayout
            } else {
                // iPhone: Use overlay sidebar pattern (like mobile web)
                iPhoneLayout
            }
        }
        .withReminderPresentation()
        // NOTE: .withTaskPresentation() is now applied inside each NavigationStack
        // in TaskListView to avoid "A navigationDestination was declared outside of
        // any NavigationStack" warning
        .onReceive(NotificationCenter.default.publisher(for: .openSettings)) { _ in
            // Navigate to settings in the main content area
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                showSidebar = false
            }
            selectedListId = "settings"
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeSettings)) { _ in
            selectedListId = "my-tasks"
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProfile)) { _ in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                showSidebar = false
            }
            selectedListId = "profile"
        }
        .onReceive(NotificationCenter.default.publisher(for: .closeProfile)) { _ in
            selectedListId = "my-tasks"
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDetailDidAppear)) { _ in
            isShowingTaskDetail = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .taskDetailDidDisappear)) { _ in
            isShowingTaskDetail = false
        }
        .onChange(of: listPresenter.listIdToShow) { _, newListId in
            // Handle programmatic list navigation from ListPresenter
            if let listId = newListId {
                print("🔄 [MainTabView] ListPresenter requesting navigation to: \(listId)")

                // Close sidebar if open
                if showSidebar {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        showSidebar = false
                    }
                }

                // Update list selection
                selectedListId = listId
                isViewingFromFeatured = listPresenter.isShowingFeaturedList
                featuredList = listPresenter.featuredListToShow

                // Clear the navigation request
                listPresenter.clearNavigation()
            }
        }
    }

    // MARK: - iPhone Layout

    // Calculate animation progress based on sidebar state and drag
    private var sidebarProgress: CGFloat {
        let targetOffset = UIScreen.main.bounds.width * 0.85
        if showSidebar {
            // When open, calculate based on drag offset
            let currentOffset = targetOffset + dragOffset
            return max(0, min(1, currentOffset / targetOffset))
        } else {
            // When closed, calculate based on drag offset from 0
            return max(0, min(1, dragOffset / targetOffset))
        }
    }

    private var iPhoneLayout: some View {
        ZStack(alignment: .leading) {
            // Full-screen background using theme color
            themeBackground
                .ignoresSafeArea()

            // Sidebar - ALWAYS rendered underneath, visible when content slides right
            ZStack {
                // Background gradient layer
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
                            // Scroll sidebar to top first (instant), then close
                            shouldScrollSidebarToTop = true

                            // Close sidebar immediately and show selected list
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showSidebar = false
                            }

                            // Reset scroll flag and haptic feedback when sidebar finishes closing
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                shouldScrollSidebarToTop = false
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                    )
                    .environmentObject(authManager)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(themeBackgroundColor, for: .navigationBar)
                }
            }
            .frame(width: UIScreen.main.bounds.width * 0.85)
            // Subtle rise animation - synced with drag progress
            .scaleEffect(0.95 + (0.05 * sidebarProgress))  // 0.95 → 1.0
            .offset(y: 20 - (20 * sidebarProgress))  // 20 → 0
            .opacity(0.8 + (0.2 * sidebarProgress))  // 0.8 → 1.0

            // Main content - slides to the right to reveal sidebar underneath
            NavigationStack {
                if selectedListId == "settings" {
                    SettingsView(onMenuTap: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            showSidebar = true
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            let impact = UIImpactFeedbackGenerator(style: .light)
                            impact.impactOccurred()
                        }
                    })
                        .environmentObject(authManager)
                } else if selectedListId == "profile", let userId = authManager.userId {
                    UserProfileView(userId: userId)
                        .environmentObject(authManager)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    let isHorizontal = value.translation.width > abs(value.translation.height)
                                    let isRight = value.translation.width > 0
                                    let meetsThreshold = value.translation.width > 80
                                        || value.predictedEndTranslation.width > 200
                                    if isHorizontal && isRight && meetsThreshold {
                                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            showSidebar = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                        }
                                    }
                                }
                        )
                } else {
                    TaskListView(
                        selectedListId: $selectedListId,
                        isViewingFromFeatured: $isViewingFromFeatured,
                        featuredList: $featuredList,
                        searchText: $searchText,
                        onMenuTap: {
                            // Dismiss keyboard first (important: must happen before sidebar animation)
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

                            // Open sidebar
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showSidebar = true
                            }

                            // Haptic feedback when sidebar finishes opening (after animation completes)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                let impact = UIImpactFeedbackGenerator(style: .light)
                                impact.impactOccurred()
                            }
                        }
                    )
                }
            }
            .frame(width: UIScreen.main.bounds.width)
            .offset(x: showSidebar ? UIScreen.main.bounds.width * 0.85 + dragOffset : dragOffset)
            .shadow(color: .black.opacity(0.3 * sidebarProgress), radius: 10, x: -5, y: 0)
            // Disabled look when sidebar is visible - muted colors and reduced opacity
            .opacity(1.0 - (0.3 * sidebarProgress))  // Fade out as sidebar opens
            .saturation(1.0 - (0.5 * sidebarProgress))  // Desaturate as sidebar opens
            .allowsHitTesting(sidebarProgress < 0.95) // Disable task interactions when sidebar is nearly/fully open

            // Overlay with FIXED 85/15 split - left passes through, right captures gestures
            if showSidebar {
                HStack(spacing: 0) {
                    // Left 85% - sidebar area, taps pass through to sidebar
                    Color.clear
                        .frame(width: UIScreen.main.bounds.width * 0.85)
                        .allowsHitTesting(false)

                    // Right 15% - task list area, captures drags and taps
                    Color.clear
                        .frame(width: UIScreen.main.bounds.width * 0.15)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    // Scroll to top on first drag movement
                                    if !hasScrolledDuringDrag && value.translation.width < 0 {
                                        shouldScrollSidebarToTop = true
                                        hasScrolledDuringDrag = true
                                    }

                                    // Dragging left to close
                                    if value.translation.width < 0 {
                                        dragOffset = value.translation.width
                                    }
                                }
                                .onEnded { value in
                                    // Reset drag scroll flag
                                    hasScrolledDuringDrag = false

                                    // If dragged left more than 100 points or high velocity, dismiss
                                    if value.translation.width < -100 || value.predictedEndTranslation.width < -200 {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            showSidebar = false
                                            dragOffset = 0
                                        }

                                        // Reset scroll flag and haptic feedback when sidebar finishes closing
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            shouldScrollSidebarToTop = false
                                            let impact = UIImpactFeedbackGenerator(style: .light)
                                            impact.impactOccurred()
                                        }
                                    } else {
                                        // Snap back to open position - also reset scroll flag
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                                            dragOffset = 0
                                        }
                                        shouldScrollSidebarToTop = false
                                    }
                                }
                        )
                        .onTapGesture {
                            // Scroll sidebar to top first (instant), then close
                            shouldScrollSidebarToTop = true

                            // Tap task list to close
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                showSidebar = false
                            }

                            // Reset scroll flag and haptic feedback when sidebar finishes closing
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

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        // Use custom 3-column/2-column layout for iPad
        iPadTaskManagerView(
            selectedListId: $selectedListId,
            isViewingFromFeatured: $isViewingFromFeatured,
            featuredList: $featuredList
        )
        .environmentObject(authManager)
    }
}

#Preview {
    MainTabView()
}
