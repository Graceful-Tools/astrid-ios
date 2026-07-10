import SwiftUI

@main
struct AstridApp: App {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var notificationPromptManager = NotificationPromptManager.shared
    @StateObject private var reviewPromptManager = ReviewPromptManager.shared
    @ObservedObject private var connectionModeManager = ConnectionModeManager.shared
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @Environment(\.scenePhase) private var scenePhase

    init() {
        print("🚀 [AstridApp] App launching...")
        print("📍 [AstridApp] Init started - about to configure app...")

        // Configure localization FIRST before any UI strings are loaded
        configureLocalization()

        configureAppearance()
        configureLogs()
        print("📍 [AstridApp] About to configure OAuth...")
        configureOAuth()
        print("📍 [AstridApp] OAuth configuration complete")

        // Initialize ReminderPresenter SYNCHRONOUSLY before configuring notifications
        // This ensures it's ready to handle notification taps during cold start
        print("🔔 [AstridApp] Initializing ReminderPresenter...")
        _ = ReminderPresenter.shared
        print("✅ [AstridApp] ReminderPresenter initialized and ready")

        configureNotifications()
        configureBadgeManagement()
        validateAppGroupAccess()

        // Register background tasks (skipped in test environment)
        BackgroundSyncHandler.shared.registerBackgroundTasks()

        // Warm up services that are commonly accessed on first task add
        // This moves initialization from first-use to app startup, eliminating latency
        warmUpServices()

        print("✅ [AstridApp] Init complete")
    }

    /// Warm up commonly-used services during app startup to eliminate first-use latency
    /// This runs on a background thread to not block UI, but completes before user interaction
    private func warmUpServices() {
        print("⚡️ [AstridApp] Starting service warm-up...")
        let start = CFAbsoluteTimeGetCurrent()

        // Pre-compile SmartTaskParser regex patterns (synchronous, fast)
        SmartTaskParser.warmUp()

        // Drain any Outbox journal persisted from a previous session (no-op when
        // empty — the common case while dual-write is off).
        _Concurrency.Task { @MainActor in OutboxManager.shared.start() }

        // Start the GitHub sync worker (observers + status). No-op until the
        // user connects GitHub and links a list.
        _Concurrency.Task { @MainActor in
            await GitHubSyncService.shared.refreshStatus()
            GitHubSyncService.shared.scheduleSync()
            await GoogleTasksSyncService.shared.refreshStatus()
            GoogleTasksSyncService.shared.scheduleSync()
        }

        // Touch singletons to trigger their initialization
        // These load from UserDefaults (synchronous) and fetch from server (background)
        _Concurrency.Task.detached(priority: .userInitiated) {
            // Touch services on background thread to trigger initialization
            // UserSettingsService and MyTasksPreferencesService both:
            // 1. Load from UserDefaults (fast, synchronous) - prevents first-use blocking
            // 2. Fetch from server (async, background) - updates in background
            _ = await UserSettingsService.shared.settings
            _ = await MyTasksPreferencesService.shared.preferences

            // Warm the autocorrect/spell engine invisibly (no keyboard, runs once).
            // Replaces the old hidden-text-field pre-warm that visibly flashed the
            // keyboard open/closed on every app open. UITextChecker is MainActor-
            // isolated, so hop to the main actor for the (cheap, one-shot) warm.
            await MainActor.run { KeyboardEngineWarmer.warmOnce() }

            let elapsed = CFAbsoluteTimeGetCurrent() - start
            print("⚡️ [AstridApp] Service warm-up completed in \(String(format: "%.3f", elapsed))s")
        }
    }

    var body: some Scene {
        WindowGroup {
            contentView
                .preferredColorScheme(themeMode.colorScheme)
                .onAppear {
                    print("👁️ [AstridApp] Root view appeared")
                    print("🎨 [AstridApp] Theme mode: \(themeMode.displayName)")
                    // Set UIKit window override to match theme
                    updateWindowUserInterfaceStyle(for: themeMode)
                    _Concurrency.Task {
                        // Try to restore local user first (offline-only mode)
                        if connectionModeManager.restoreLocalUserIfNeeded() {
                            print("✅ [AstridApp] Restored local user - skipping network auth check")
                            return
                        }

                        // Check authentication (non-blocking for offline mode)
                        await authManager.checkAuthentication()

                        // Only proceed with network operations if authenticated
                        guard authManager.isAuthenticated else {
                            print("⚠️ [AstridApp] Not authenticated - skipping network operations")
                            return
                        }

                        // Skip network operations for offline-only mode
                        if connectionModeManager.currentMode == .offlineOnly {
                            print("📴 [AstridApp] Offline-only mode - skipping network operations")
                            await updateAppBadge()
                            return
                        }

                        // Process any pending shared tasks from Share Extension (requires network)
                        await processSharedTasks()

                        // Update badge when app becomes foreground
                        await updateAppBadge()
                    }
                }
                .onChange(of: themeMode) { oldValue, newValue in
                    print("🎨 [AstridApp] Theme changed: \(oldValue.displayName) -> \(newValue.displayName)")
                    // Update UIKit window override when theme changes
                    updateWindowUserInterfaceStyle(for: newValue)
                }
                .onChange(of: authManager.isAuthenticated) { oldValue, newValue in
                    print("📡 [AstridApp] Auth changed: \(oldValue) -> \(newValue)")
                    _Concurrency.Task {
                        if newValue {
                            // User just logged in - establish SSE connection with delay
                            // Wait a bit to ensure session is fully established
                            print("📡 [AstridApp] User logged in - will connect to SSE in 2s...")
                            try? await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
                            await connectSSE()

                            // Prompt new users to enable push notifications
                            // Small delay to let the main UI appear first
                            try? await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
                            await NotificationPromptManager.shared.checkAndPromptAfterDateSet()

                            // Check if we should prompt for app review
                            // Wait longer to let user engage with the app first
                            try? await _Concurrency.Task.sleep(nanoseconds: 5_000_000_000)
                            await ReviewPromptManager.shared.checkAndPromptForReview()
                        } else {
                            // User logged out - disconnect from SSE
                            print("📡 [AstridApp] User logged out - disconnecting from SSE...")
                            await SSEClient.shared.disconnect()
                        }
                    }
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    if newPhase == .active {
                        print("📱 [AstridApp] App became active - refreshing image cache")
                        // Clear memory cache so images reload fresh from server
                        // This ensures web-updated images show on iOS
                        ImageCache.shared.clearMemoryCache()

                        // Reconnect SSE if it dropped while in background
                        _Concurrency.Task {
                            await connectSSE()
                        }

                        // Check for review prompt when app becomes active (good time to ask)
                        _Concurrency.Task {
                            await ReviewPromptManager.shared.checkAndPromptForReview()
                        }
                    } else if newPhase == .background {
                        print("📱 [AstridApp] App went to background - scheduling sync")
                        // Schedule background sync to complete pending operations
                        BackgroundSyncHandler.shared.scheduleBackgroundSync()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .networkDidBecomeAvailable)) { _ in
                    // Reconnect SSE when network is restored
                    _Concurrency.Task {
                        await connectSSE()
                    }
                }
                .alert("Enable Push Notifications", isPresented: $notificationPromptManager.showPromptAlert) {
                    Button("Not Now", role: .cancel) { }
                    Button("Enable") {
                        _Concurrency.Task {
                            _ = await notificationPromptManager.requestNotificationPermission()
                        }
                    }
                } message: {
                    Text("Please enable push notifications so I can help remind you to get things done!")
                }
                .alert("Notifications Disabled", isPresented: $notificationPromptManager.showSettingsPrompt) {
                    Button("Not Now", role: .cancel) { }
                    Button("Open Settings") {
                        notificationPromptManager.openSettings()
                    }
                } message: {
                    Text("Push notifications are disabled. Please enable them in Settings so I can help remind you to get things done!")
                }
                .alert("Loving Astrid?", isPresented: $reviewPromptManager.showLovePrompt) {
                    Button("Not really") {
                        reviewPromptManager.handleNoLoveResponse()
                    }
                    Button("Yes, I love it!") {
                        _Concurrency.Task {
                            await reviewPromptManager.handleLoveResponse()
                        }
                    }
                } message: {
                    Text("Do you love using Astrid? We'd love to hear from you!")
                }
                .alert("Help Us Improve", isPresented: $reviewPromptManager.showFeedbackPrompt) {
                    Button("Maybe Later", role: .cancel) { }
                    Button("Report an Issue") {
                        reviewPromptManager.openFeedbackForm()
                    }
                    Button("Send Feedback") {
                        reviewPromptManager.openSupportEmail()
                    }
                } message: {
                    Text("We're sorry to hear that. Would you like to report an issue or send us feedback?")
                }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        ZStack {
            // Ocean theme background
            if themeMode == .ocean {
                Theme.Ocean.bgPrimary
                    .ignoresSafeArea()
            }

            if authManager.isCheckingAuth {
                // Show splash screen while checking authentication
                let _ = print("🌊 [AstridApp] Checking auth - showing SplashView")
                SplashView()
            } else if shouldShowWelcome {
                // First-run: show welcome screen with choice
                let _ = print("👋 [AstridApp] First run - showing WelcomeChoiceView")
                WelcomeChoiceView()
                    .environmentObject(authManager)
            } else if authManager.isAuthenticated {
                let _ = print("✅ [AstridApp] User authenticated - showing MainTabView")
                MainTabView()
                    .environmentObject(authManager)
            } else {
                let _ = print("🔐 [AstridApp] User not authenticated - showing LoginView")
                LoginView()
                    .environmentObject(authManager)
            }
        }
        .onOpenURL { url in
            DeepLinkManager.shared.handleURL(url)
        }
    }

    /// Whether to show the welcome screen (first-run experience)
    private var shouldShowWelcome: Bool {
        // Show welcome if:
        // 1. Not authenticated
        // 2. No local user exists
        // 3. Never shown welcome before
        !authManager.isAuthenticated &&
        !connectionModeManager.hasLocalUser &&
        !UserDefaults.standard.bool(forKey: "hasSeenWelcome")
    }

    private func configureLocalization() {
        print("🌍 [AstridApp] Configuring localization...")
        // Apply intelligent locale-based language selection
        // This checks device locale and preferred languages to select the best match
        // Example: US user with Spanish preference (es-US) will get Spanish (es) not English (en)
        LocalizationManager.shared.applyIntelligentLocale()
        print("✅ [AstridApp] Localization configured")
    }

    private func configureAppearance() {
        print("🎨 [AstridApp] Configuring appearance...")

        // Create adaptive UIColors that respond to dark mode
        // Ocean theme uses same headers as light mode
        let headerBg = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Theme.Dark.headerBg)
                : UIColor(Theme.bgSecondary)
        }

        let textColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Theme.Dark.textPrimary)
                : UIColor(Theme.textPrimary)
        }

        let borderColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Theme.Dark.border)
                : UIColor(Theme.border)
        }

        // Configure list/table view backgrounds to be transparent for ocean theme
        // This allows the cyan ocean background to show through
        let listBg = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(Theme.Dark.bgSecondary)
                : UIColor.clear  // Transparent for light/ocean themes
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = headerBg
        appearance.titleTextAttributes = [.foregroundColor: textColor]
        appearance.largeTitleTextAttributes = [.foregroundColor: textColor]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Configure list appearance with adaptive colors
        // Use transparent background for light mode to allow ocean theme to show through
        UITableView.appearance().backgroundColor = listBg
        UITableView.appearance().separatorColor = borderColor
    }

    private func configureLogs() {
        print("📋 [AstridApp] Logging configured")
        print("📋 [AstridApp] Base URL: \(Constants.API.baseURL)")
        print("📋 [AstridApp] Environment: \(Constants.API.environment)")
    }

    private func configureOAuth() {
        print("🔐 [AstridApp] Configuring OAuth...")

        // Check if OAuth secret is already configured
        if KeychainService.shared.getOAuthClientSecret() != nil {
            print("✅ [AstridApp] OAuth secret already configured")
            return
        }

        // Configure OAuth secret (generated by setup-ios-oauth script)
        // In production, this would be fetched from secure config or set during first run
        let clientSecret = "144280ddb56392af6943b12420fd39c43e7571ef9295c46e2d0e757f26afb5a9"
        OAuthManager.shared.configure(clientSecret: clientSecret)
        print("✅ [AstridApp] OAuth secret configured and stored in Keychain")
    }

    private func configureNotifications() {
        print("🔔 [AstridApp] Configuring notifications...")
        _Concurrency.Task { @MainActor in
            NotificationManager.shared.registerNotificationCategories()
            // Register timer notification category for background timer completion
            TimerBackgroundManager.shared.registerTimerNotificationCategory()
        }
    }

    private func configureBadgeManagement() {
        print("📛 [AstridApp] Initializing badge management...")
        // Initialize BadgeManager singleton
        _ = BadgeManager.shared
        print("✅ [AstridApp] Badge management configured")
    }

    private func validateAppGroupAccess() {
        print("🔐 [AstridApp] Validating App Group access...")
        if ShareDataManager.shared.validateAppGroupAccess() {
            print("✅ [AstridApp] App Group access validated")
        } else {
            print("⚠️ [AstridApp] App Group not configured - Share Extension will not work")
        }
    }

    private func processSharedTasks() async {
        guard authManager.isAuthenticated else {
            print("⚠️ [AstridApp] Not authenticated - skipping shared tasks processing")
            return
        }

        // Check network availability before attempting to process shared tasks
        guard NetworkMonitor.shared.isConnected else {
            print("⚠️ [AstridApp] No network connection - shared tasks will be processed when online")
            return
        }

        print("📥 [AstridApp] Checking for shared tasks...")

        do {
            let pendingTasks = try ShareDataManager.shared.loadPendingTasks()
            guard !pendingTasks.isEmpty else {
                print("📭 [AstridApp] No pending shared tasks")
                return
            }

            print("📋 [AstridApp] Found \(pendingTasks.count) pending shared task(s)")

            for item in pendingTasks where item.status == .pending {
                await processSingleSharedTask(item)
            }

            // Clean up completed tasks
            try ShareDataManager.shared.removeCompletedTasks()
        } catch {
            print("❌ [AstridApp] Failed to process shared tasks: \(error)")
        }
    }

    private func updateAppBadge() async {
        print("📛 [AstridApp] Updating app badge...")
        let taskService = TaskService.shared
        await BadgeManager.shared.updateBadge(with: taskService.tasks)
    }

    private func processSingleSharedTask(_ item: SharedTaskItem) async {
        let taskData = item.data
        print("🔄 [AstridApp] Processing shared task: \(taskData.title)")

        do {
            // Update status to creating
            try ShareDataManager.shared.updateTaskStatus(
                taskId: taskData.id,
                status: .creating
            )

            // Create task via MCP
            let taskService = TaskService.shared
            let createdTask = try await taskService.createTask(
                listIds: taskData.listId.map { [$0] } ?? [],
                title: taskData.title,
                description: taskData.description ?? "",
                priority: taskData.priority,
                whenDate: nil,
                whenTime: nil,
                assigneeId: AuthManager.shared.userId,
                isPrivate: nil,
                repeating: nil
            )

            print("✅ [AstridApp] Task created: \(createdTask.id)")

            // If there's a file attachment, upload it
            if let fileURL = taskData.fileURL,
               let fileName = taskData.fileName,
               let mimeType = taskData.mimeType {

                print("📤 [AstridApp] Uploading attachment: \(fileName)")

                // Update status to uploading
                try ShareDataManager.shared.updateTaskStatus(
                    taskId: taskData.id,
                    status: .uploading,
                    createdTaskId: createdTask.id
                )

                // Upload file
                let attachmentService = AttachmentService.shared
                _ = try await attachmentService.uploadSharedFile(
                    fileURL: fileURL,
                    fileName: fileName,
                    mimeType: mimeType,
                    taskId: createdTask.id
                )

                print("✅ [AstridApp] Attachment uploaded successfully")
            }

            // Mark as completed
            try ShareDataManager.shared.updateTaskStatus(
                taskId: taskData.id,
                status: .completed,
                createdTaskId: createdTask.id
            )

            print("✅ [AstridApp] Shared task processed successfully")

        } catch {
            print("❌ [AstridApp] Failed to process shared task: \(error)")

            // Mark as failed
            try? ShareDataManager.shared.updateTaskStatus(
                taskId: taskData.id,
                status: .failed,
                error: error.localizedDescription
            )
        }
    }

    private func connectSSE() async {
        guard authManager.isAuthenticated else {
            print("⚠️ [AstridApp] Not authenticated - skipping SSE connection")
            return
        }

        // Only connect SSE if we have a real server session (not local-only mode)
        let hasCookie = (try? KeychainService.shared.getSessionCookie()) != nil
        guard hasCookie else {
            print("⚠️ [AstridApp] No session cookie - skipping SSE (local-only mode)")
            return
        }

        print("📡 [AstridApp] Establishing SSE connection...")
        await SSEClient.shared.connect()
        print("✅ [AstridApp] SSE connection established")
    }

    /// Updates all UIKit windows to use the specified user interface style
    /// This ensures UIKit components (navigation bars, etc.) respect the app's theme
    private func updateWindowUserInterfaceStyle(for theme: ThemeMode) {
        let style: UIUserInterfaceStyle
        switch theme {
        case .ocean, .light:
            style = .light
        case .dark:
            style = .dark
        case .auto:
            style = .unspecified  // Follow system
        }

        // Update all connected scenes' windows
        for scene in UIApplication.shared.connectedScenes {
            if let windowScene = scene as? UIWindowScene {
                for window in windowScene.windows {
                    window.overrideUserInterfaceStyle = style
                    print("🎨 [AstridApp] Window override set to: \(style.rawValue) (\(theme.displayName))")
                }
            }
        }
    }
}
