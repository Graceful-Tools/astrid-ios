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
        print("🔌 [ConnectionModeManager] Initialized in \(currentMode.displayName) mode")
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
            print("🔄 [ConnectionModeManager] Mode changed: \(currentMode.displayName) -> \(newMode.displayName)")
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

        print("🌐 [ConnectionModeManager] Network restored - transitioning to online")
        currentMode = .online

        // Trigger sync of pending operations AND revive the live stream. Syncing alone left the
        // app fetching on a timer with no live updates, because SSE had already exhausted its
        // retries while the network was down.
        _Concurrency.Task {
            try? await SyncManager.shared.performQuickSync()
            await SSEClient.shared.reconnectNow()
        }
    }

    private func handleNetworkLost() {
        // Only transition if we're currently online
        guard currentMode == .online else { return }

        print("📵 [ConnectionModeManager] Network lost - transitioning to offline")
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

        print("✅ [ConnectionModeManager] Created local user: \(localUserId)")

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

        print("✅ [ConnectionModeManager] Restored local user: \(localUserId)")
        return true
    }

    // MARK: - Offline to Online Transition

    /// Transition from offline-only mode to online mode after user signs in.
    /// Uploads all local data to the server.
    func transitionToOnline(userId: String) async throws {
        guard currentMode == .offlineOnly else {
            print("⚠️ [ConnectionModeManager] Not in offline-only mode, skipping transition")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }

        print("🔄 [ConnectionModeManager] Transitioning from offline-only to online...")

        // 1. Get all local tasks and lists (those with local_ or temp_ prefixes)
        let localTasks = TaskService.shared.tasks.filter {
            $0.id.hasPrefix("temp_") || $0.id.hasPrefix("local_")
        }
        let localLists = ListService.shared.lists.filter {
            $0.id.hasPrefix("temp_") || $0.id.hasPrefix("local_")
        }

        print("📤 [ConnectionModeManager] Uploading \(localTasks.count) tasks and \(localLists.count) lists...")

        // 2. Upload lists first (tasks may depend on list IDs)
        var listIdMapping: [String: String] = [:]
        for list in localLists {
            do {
                let serverList = try await AstridAPIClient.shared.createList(
                    name: list.name,
                    description: list.description ?? "",
                    color: list.color,
                    privacy: list.privacy?.rawValue ?? "PRIVATE"
                )
                listIdMapping[list.id] = serverList.id
                print("  ✅ Uploaded list: \(list.name) -> \(serverList.id)")
            } catch {
                print("  ⚠️ Failed to upload list \(list.name): \(error)")
                // Continue with other lists
            }
        }

        // 3. Upload tasks with mapped list IDs
        for task in localTasks {
            do {
                // Map local list IDs to server list IDs
                let serverListIds = (task.listIds ?? []).compactMap { localId -> String? in
                    if let serverId = listIdMapping[localId] {
                        return serverId
                    }
                    // If not a local ID, keep as-is (might be a real server ID)
                    if !localId.hasPrefix("local_") && !localId.hasPrefix("temp_") {
                        return localId
                    }
                    return nil
                }

                _ = try await AstridAPIClient.shared.createTask(
                    title: task.title,
                    listIds: serverListIds.isEmpty ? nil : serverListIds,
                    description: task.description.isEmpty ? nil : task.description,
                    priority: task.priority.rawValue,
                    assigneeId: userId,  // Assign to the newly authenticated user
                    dueDateTime: task.dueDateTime,
                    isAllDay: task.isAllDay,
                    isPrivate: task.isPrivate,
                    repeating: task.repeating?.rawValue
                )
                print("  ✅ Uploaded task: \(task.title)")
            } catch {
                print("  ⚠️ Failed to upload task \(task.title): \(error)")
                // Continue with other tasks
            }
        }

        // 4. Clear offline-only mode flags
        UserDefaults.standard.set(false, forKey: Self.offlineOnlyModeKey)
        UserDefaults.standard.removeObject(forKey: Self.localUserIdKey)

        // 5. Update mode
        currentMode = networkMonitor.isConnected ? .online : .offline

        // 6. Perform full sync to get clean state from server
        try await SyncManager.shared.performFullSync()

        print("✅ [ConnectionModeManager] Transition to online complete")

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
                print("⚠️ [ConnectionModeManager] Failed to upload local data after sign-in: \(error)")
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
        print("🧹 [ConnectionModeManager] Cleared local mode data")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let localUserCreated = Notification.Name("localUserCreated")
    static let transitionedToOnline = Notification.Name("transitionedToOnline")
    static let connectionModeChanged = Notification.Name("connectionModeChanged")
}
