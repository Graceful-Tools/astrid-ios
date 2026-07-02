import Foundation
import Combine

/// User settings synced across devices
struct UserSettings: Codable {
    var smartTaskCreationEnabled: Bool?
    var emailToTaskEnabled: Bool?
    var defaultTaskDueOffset: String?
    var defaultDueTime: String?
    /// How subtasks display: "indented" (in lists, indented under their parent —
    /// default) | "under_parent" (only inside the parent task's detail).
    var subtaskDisplay: String?

    init(
        smartTaskCreationEnabled: Bool? = true,
        emailToTaskEnabled: Bool? = true,
        defaultTaskDueOffset: String? = "1_week",
        defaultDueTime: String? = "17:00",
        subtaskDisplay: String? = "indented"
    ) {
        self.smartTaskCreationEnabled = smartTaskCreationEnabled
        self.emailToTaskEnabled = emailToTaskEnabled
        self.defaultTaskDueOffset = defaultTaskDueOffset
        self.defaultDueTime = defaultDueTime
        self.subtaskDisplay = subtaskDisplay
    }
}

/// Service for managing user settings with server sync
@MainActor
class UserSettingsService: ObservableObject {
    static let shared = UserSettingsService()

    @Published var settings: UserSettings
    private var updateTask: _Concurrency.Task<Void, Never>?

    private let userDefaultsKey = "user_settings"

    private init() {
        // Load from UserDefaults first (offline support)
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedSettings = try? JSONDecoder().decode(UserSettings.self, from: savedData) {
            self.settings = savedSettings
            print("✅ [UserSettings] Loaded from UserDefaults")
        } else {
            // Start with default settings
            self.settings = UserSettings()
            print("ℹ️ [UserSettings] Using default settings")
        }

        // Load from server in background
        _Concurrency.Task {
            await fetchSettings()
        }

        // Register for SSE updates from other devices
        _Concurrency.Task { [weak self] in
            guard let self = self else { return }
            await SSEClient.shared.onUserSettingsUpdated { settings in
                _Concurrency.Task { @MainActor [weak self] in
                    self?.handleSSEUpdate(settings)
                }
            }
        }
    }

    /// Convenience accessor for smart task creation
    var smartTaskCreationEnabled: Bool {
        get { settings.smartTaskCreationEnabled ?? true }
        set { updateSettings(UserSettings(smartTaskCreationEnabled: newValue)) }
    }

    /// Fetch settings from the server via AstridAPIClient (the canonical
    /// network entry point). UI already has the UserDefaults snapshot, so
    /// failure here is non-fatal.
    func fetchSettings() async {
        do {
            let fetchedSettings = try await AstridAPIClient.shared.getSmartTaskSettings()
            self.settings = fetchedSettings

            if let encoded = try? JSONEncoder().encode(fetchedSettings) {
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                print("✅ [UserSettings] Loaded from server and saved to UserDefaults")
            }
        } catch {
            print("❌ [UserSettings] Error fetching settings: \(error)")
        }
    }

    /// Update settings on server
    func updateSettings(_ updates: UserSettings) {
        // Cancel any pending update
        updateTask?.cancel()

        // Merge updates into current settings
        var merged = self.settings
        if let smartTaskCreation = updates.smartTaskCreationEnabled {
            merged.smartTaskCreationEnabled = smartTaskCreation
        }
        if let emailToTask = updates.emailToTaskEnabled {
            merged.emailToTaskEnabled = emailToTask
        }
        if let dueOffset = updates.defaultTaskDueOffset {
            merged.defaultTaskDueOffset = dueOffset
        }
        if let dueTime = updates.defaultDueTime {
            merged.defaultDueTime = dueTime
        }

        // Optimistically update local state
        self.settings = merged

        // Save to UserDefaults immediately for offline support
        if let encoded = try? JSONEncoder().encode(merged) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [UserSettings] Saved to UserDefaults")
        }

        // Debounced server push via AstridAPIClient so cookies/auth/retry
        // flow through the same code path as every other network call.
        updateTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            guard !_Concurrency.Task.isCancelled else { return }

            do {
                try await AstridAPIClient.shared.updateSmartTaskSettings(merged)
                print("✅ Updated user settings on server")
            } catch {
                print("❌ Error updating user settings: \(error)")
            }
        }
    }

    /// Handle SSE update from another device
    func handleSSEUpdate(_ newSettings: UserSettings) {
        print("🔔 [SSE] User settings updated from another device")
        self.settings = newSettings

        // Save to UserDefaults for offline support
        if let encoded = try? JSONEncoder().encode(newSettings) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [UserSettings] Saved SSE update to UserDefaults")
        }
    }

    /// Clear all settings data on logout
    /// This prevents data leakage between users
    func clearData() {
        // Cancel any pending updates
        updateTask?.cancel()
        updateTask = nil

        // Reset to default settings
        settings = UserSettings()

        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        print("🗑️ [UserSettings] Data cleared for logout")
    }
}
