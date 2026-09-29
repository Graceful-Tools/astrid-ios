import Foundation
import Combine

/// Manages the app's connection mode for seamless offline/online transitions.
/// Supports three modes: online (normal sync), offline (temporary, will sync when restored),
/// and offlineOnly (permanent local-only mode without account).
@MainActor
class ConnectionModeManager: ObservableObject {
    static let shared = ConnectionModeManager()

    /// The three connection modes
    enum ConnectionMode: String, Equatable {
        case online       // Normal operation with server sync
        case offline      // Temporary offline (network lost, will sync when restored)
        case offlineOnly  // Permanent local-only mode (no account required)

        var displayName: String {
            switch self {
            case .online: return "Online"
            case .offline: return "Offline"
            case .offlineOnly: return "Local Only"
            }
        }
    }

    @Published var currentMode: ConnectionMode = .online
    @Published var isTransitioning = false

    private let networkMonitor = NetworkMonitor.shared
    private var networkObserver: NSObjectProtocol?

    // UserDefaults keys for offline-only mode
    private static let offlineOnlyModeKey = "offlineOnlyModeEnabled"
    private static let localUserIdKey = "localOnlyUserId"

    // MARK: - Computed Properties

    // In-memory local-mode state for -uiTesting runs (never persisted — UI tests share the real
    // app container, and persisted flags left the user's app permanently offline after a test).
    private var inMemoryOfflineOnly = false
    private var inMemoryLocalUserId: String?

    /// Whether the app is in explicit offline-only mode
    var isOfflineOnly: Bool {
        inMemoryOfflineOnly || UserDefaults.standard.bool(forKey: Self.offlineOnlyModeKey)
    }

    /// Whether a local-only user exists
    var hasLocalUser: Bool {
        inMemoryLocalUserId != nil || UserDefaults.standard.string(forKey: Self.localUserIdKey) != nil
    }

    /// The local user ID if in offline-only mode
    var localUserId: String? {
        inMemoryLocalUserId ?? UserDefaults.standard.string(forKey: Self.localUserIdKey)
    }

    // MARK: - Initialization

    private init() {
        // Determine initial mode
        currentMode = determineMode()
        setupNetworkObserver()
        AppLog.debug("🔌 [ConnectionModeManager] Initialized in \(currentMode.displayName) mode")
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Mode Determination

    /// Determine the current connection mode based on auth state and network
    func determineMode() -> ConnectionMode {
        // 1. Check if user explicitly enabled offline-only mode
        if isOfflineOnly {
            return .offlineOnly
        }

        // 2. Check if has local-only user (without explicit mode flag)
        if hasLocalUser && !AuthManager.shared.isAuthenticated {
            return .offlineOnly
        }

        // 3. Check if authenticated with server account
        if AuthManager.shared.isAuthenticated {
            // Check network availability
            return networkMonitor.isConnected ? .online : .offline
        }

        // 4. Default to online (will show login)
        return .online
    }

    /// Refresh the current mode (call after auth changes)
    func refreshMode() {
        let newMode = determineMode()
        if newMode != currentMode {
            AppLog.debug("🔄 [ConnectionModeManager] Mode changed: \(currentMode.displayName) -> \(newMode.displayName)")
            currentMode = newMode
        }
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        // Listen for network availability changes
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            _Concurrency.Task { @MainActor in
                self.handleNetworkRestored()
            }
        }

        NotificationCenter.default.addObserver(
            forName: .networkDidBecomeUnavailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            _Concurrency.Task { @MainActor in
                self.handleNetworkLost()
            }
        }
    }

    private func handleNetworkRestored() {
        // Only transition if we're in temporary offline mode
        guard currentMode == .offline else { return }

        AppLog.debug("🌐 [ConnectionModeManager] Network restored - transitioning to online")
        currentMode = .online
        // Sending what waited and reviving the stream is AppCore's, on the same notification.
    }

    private func handleNetworkLost() {
        // Only transition if we're currently online
        guard currentMode == .online else { return }

        AppLog.debug("📵 [ConnectionModeManager] Network lost - transitioning to offline")
        currentMode = .offline
    }

    // MARK: - Local User Mode

    /// Create a local-only user for offline-only mode
    /// This allows using the app without signing in
    func createLocalUser() async {
        let localUserId = "local_\(UUID().uuidString)"

        // UI tests share the real app container (same bundle id). Persisting local-only mode from
        // a -uiTesting run left the USER'S app permanently offline (no SSE/sync) after the test
        // suite ran — the flags survive the test. Under -uiTesting, keep local mode IN-MEMORY only.
        let persist = !UITestSession.isUITesting

        // Store local user info in UserDefaults
        if persist {
            UserDefaults.standard.set(localUserId, forKey: Self.localUserIdKey)
            UserDefaults.standard.set(localUserId, forKey: Constants.UserDefaults.userId)
            UserDefaults.standard.set(true, forKey: Self.offlineOnlyModeKey)
            UserDefaults.standard.set(NSLocalizedString("local_user", comment: "Local User"), forKey: Constants.UserDefaults.userName)
        } else {
            // -uiTesting: same behavior, in-memory only (isOfflineOnly/localUserId consult these).
            inMemoryOfflineOnly = true
            inMemoryLocalUserId = localUserId
        }

        // Create a local-only user in AuthManager
        let localUser = User(
            id: localUserId,
            email: nil,
            name: NSLocalizedString("local_user", comment: "Local User"),
            image: nil
        )

        AuthManager.shared.currentUser = localUser
        AuthManager.shared.isAuthenticated = true
        AuthManager.shared.isCheckingAuth = false
        currentMode = .offlineOnly

        AppLog.debug("✅ [ConnectionModeManager] Created local user: \(localUserId)")

        // Post notification so UI can update
        NotificationCenter.default.post(name: .localUserCreated, object: nil)
    }

    /// Restore local user from UserDefaults (called during app launch)
    func restoreLocalUserIfNeeded() -> Bool {
        guard isOfflineOnly, let localUserId = localUserId else {
            return false
        }

        let userName = UserDefaults.standard.string(forKey: Constants.UserDefaults.userName)
            ?? NSLocalizedString("local_user", comment: "Local User")

        let localUser = User(
            id: localUserId,
            email: nil,
            name: userName,
            image: nil
        )

        AuthManager.shared.currentUser = localUser
        AuthManager.shared.isAuthenticated = true
        AuthManager.shared.isCheckingAuth = false
        currentMode = .offlineOnly

        AppLog.debug("✅ [ConnectionModeManager] Restored local user: \(localUserId)")
        return true
    }

    // MARK: - Offline to Online Transition

    /// Transition from offline-only mode to online mode after user signs in.
    /// Uploads all local data to the server.
    func transitionToOnline(userId: String) async throws {
        guard currentMode == .offlineOnly else {
            AppLog.debug("⚠️ [ConnectionModeManager] Not in offline-only mode, skipping transition")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }

        AppLog.debug("🔄 [ConnectionModeManager] Transitioning from offline-only to online...")

        // What was made without an account is already queued in astrid-core's journal, waiting for
        // a session; it goes now, with this account's. Creating it again here made every task and
        // list twice. Each was assigned to the placeholder user, which the server has never heard
        // of (the core leaves that assignee off the create); it becomes this account's, as the
        // re-creation used to make it — an edit queued behind the create.
        let unowned = TaskService.shared.tasks.filter {
            $0.assigneeId?.hasPrefix(AuthManager.localUserIdPrefix) == true
                || ($0.assigneeId == nil && ($0.listIds ?? []).isEmpty)
        }
        for task in unowned {
            _ = try? await TaskService.shared.updateTask(taskId: task.id, assigneeId: userId)
        }
        AppCore.shared.networkRestored()

        // 4. Clear offline-only mode flags
        UserDefaults.standard.set(false, forKey: Self.offlineOnlyModeKey)
        UserDefaults.standard.removeObject(forKey: Self.localUserIdKey)

        // 5. Update mode
        currentMode = networkMonitor.isConnected ? .online : .offline

        // 6. Perform full sync to get clean state from server
        try await SyncManager.shared.performFullSync()

        AppLog.debug("✅ [ConnectionModeManager] Transition to online complete")

        // Post notification
        NotificationCenter.default.post(name: .transitionedToOnline, object: nil)
    }

    /// Check if we need to transition after a successful sign-in
    /// Call this from AuthManager after OAuth sign-in succeeds
    func handleSuccessfulSignIn(userId: String) {
        guard currentMode == .offlineOnly else { return }

        _Concurrency.Task {
            do {
                try await transitionToOnline(userId: userId)
            } catch {
                AppLog.debug("⚠️ [ConnectionModeManager] Failed to upload local data after sign-in: \(error)")
                // User is still signed in, just local data wasn't uploaded
            }
        }
    }

    // MARK: - Sign Out

    /// Clear offline-only mode data on sign out
    func clearLocalModeData() {
        UserDefaults.standard.set(false, forKey: Self.offlineOnlyModeKey)
        UserDefaults.standard.removeObject(forKey: Self.localUserIdKey)
        currentMode = .online
        AppLog.debug("🧹 [ConnectionModeManager] Cleared local mode data")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let localUserCreated = Notification.Name("localUserCreated")
    static let transitionedToOnline = Notification.Name("transitionedToOnline")
    static let connectionModeChanged = Notification.Name("connectionModeChanged")
}
