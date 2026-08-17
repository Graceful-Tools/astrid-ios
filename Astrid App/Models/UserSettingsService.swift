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
    /// Which task-detail design to draw: "list" | "project". Nullable, and null is not a third
    /// mode — resolve it through `TaskDisplayMode(stored:)` rather than comparing the string
    /// (task 8ef7d89d).
    var taskDisplayMode: String?

    init(
        smartTaskCreationEnabled: Bool? = true,
        emailToTaskEnabled: Bool? = true,
        defaultTaskDueOffset: String? = "1_week",
        defaultDueTime: String? = "17:00",
        subtaskDisplay: String? = "indented",
        taskDisplayMode: String? = nil
    ) {
        self.smartTaskCreationEnabled = smartTaskCreationEnabled
        self.emailToTaskEnabled = emailToTaskEnabled
        self.defaultTaskDueOffset = defaultTaskDueOffset
        self.defaultDueTime = defaultDueTime
        self.subtaskDisplay = subtaskDisplay
        self.taskDisplayMode = taskDisplayMode
    }

    /// Field-by-field merge of an update onto current settings.
    ///
    /// Lifted out of `updateSettings` so it can be tested without the network, and because the
    /// pattern has already lost a write: `subtaskDisplay` had no merge line, so updating it
    /// looked saved and was silently dropped. A field added without a line here fails exactly
    /// the same way, which is invisible until someone notices their setting reverting.
    static func merging(_ updates: UserSettings, into current: UserSettings) -> UserSettings {
        var merged = current
        if let value = updates.smartTaskCreationEnabled { merged.smartTaskCreationEnabled = value }
        if let value = updates.emailToTaskEnabled { merged.emailToTaskEnabled = value }
        if let value = updates.defaultTaskDueOffset { merged.defaultTaskDueOffset = value }
        if let value = updates.defaultDueTime { merged.defaultDueTime = value }
        if let value = updates.subtaskDisplay { merged.subtaskDisplay = value }
        if let value = updates.taskDisplayMode { merged.taskDisplayMode = value }
        return merged
    }
}

/// Service for managing user settings with server sync
@MainActor
class UserSettingsService: ObservableObject {
    static let shared = UserSettingsService()

    @Published var settings: UserSettings

    /// Whether settings have come back from the server yet.
    ///
    /// A control that can write must consult this first. The failure it prevents hides well: a
    /// picker that saves correctly but initialises to the default looks right until the screen
    /// is revisited, and then re-saving from the stale control writes the default over the
    /// user's choice (task 8ef7d89d). The UserDefaults snapshot is a cache, not a load — it can
    /// predate a change made on another device.
    @Published private(set) var hasLoadedFromServer = false
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
            self.hasLoadedFromServer = true

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

        // Merge updates into current settings. One definition, so a new field cannot be
        // added to the model and forgotten here — which is how subtaskDisplay was being lost.
        let merged = UserSettings.merging(updates, into: self.settings)

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
