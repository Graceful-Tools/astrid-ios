import Foundation
import Combine

/// My Tasks filter preferences synced across devices
struct MyTasksPreferences: Codable {
    var filterPriority: [Int]?
    var filterAssignee: [String]?
    var filterDueDate: String?
    var filterCompletion: String?
    var sortBy: String?
    var manualSortOrder: [String]?

    init(
        filterPriority: [Int]? = [],
        filterAssignee: [String]? = [],
        filterDueDate: String? = "all",
        filterCompletion: String? = "default",
        sortBy: String? = "auto",
        manualSortOrder: [String]? = nil
    ) {
        self.filterPriority = filterPriority
        self.filterAssignee = filterAssignee
        self.filterDueDate = filterDueDate
        self.filterCompletion = filterCompletion
        self.sortBy = sortBy
        self.manualSortOrder = manualSortOrder
    }
}

/// Service for managing My Tasks preferences with server sync
@MainActor
class MyTasksPreferencesService: ObservableObject {
    static let shared = MyTasksPreferencesService()

    @Published var preferences: MyTasksPreferences
    private var updateTask: _Concurrency.Task<Void, Never>?

    private let userDefaultsKey = "my_tasks_preferences"

    private init() {
        // Load from UserDefaults first (offline support)
        if let savedData = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedPrefs = try? JSONDecoder().decode(MyTasksPreferences.self, from: savedData) {
            self.preferences = savedPrefs
            print("✅ [MyTasksPrefs] Loaded from UserDefaults")
        } else {
            // Start with default preferences
            self.preferences = MyTasksPreferences()
            print("ℹ️ [MyTasksPrefs] Using default preferences")
        }

        // Load from server in background
        _Concurrency.Task {
            await fetchPreferences()
        }
    }

    /// Fetch preferences from the server via AstridAPIClient (the canonical
    /// network entry point — handles cookies/auth/retry centrally). UI has
    /// already loaded the UserDefaults snapshot synchronously, so this call
    /// only refreshes; a failure here is non-fatal.
    func fetchPreferences() async {
        do {
            let fetchedPrefs = try await AstridAPIClient.shared.getMyTasksPreferences()
            self.preferences = fetchedPrefs

            if let encoded = try? JSONEncoder().encode(fetchedPrefs) {
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
                print("✅ [MyTasksPrefs] Loaded from server and saved to UserDefaults")
            }
        } catch {
            print("❌ [MyTasksPrefs] Error fetching preferences: \(error)")
        }
    }

    /// Update preferences.
    /// Optimistic: writes to local state + UserDefaults synchronously so the
    /// UI reflects the change instantly and survives app restart. The server
    /// update is debounced 300ms and routed through AstridAPIClient.
    func updatePreferences(_ updates: MyTasksPreferences) async {
        updateTask?.cancel()

        // Optimistic local state + durable UserDefaults snapshot.
        self.preferences = updates
        if let encoded = try? JSONEncoder().encode(updates) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [MyTasksPrefs] Saved to UserDefaults")
        }

        // Debounced network push.
        updateTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            guard !_Concurrency.Task.isCancelled else { return }

            do {
                try await AstridAPIClient.shared.updateMyTasksPreferences(updates)
                print("✅ Updated My Tasks preferences on server")
            } catch {
                print("❌ Error updating My Tasks preferences: \(error)")
            }
        }
    }

    /// Handle SSE update from another device
    func handleSSEUpdate(_ newPreferences: MyTasksPreferences) {
        print("🔔 [SSE] My Tasks preferences updated from another device")
        self.preferences = newPreferences

        // Save to UserDefaults for offline support
        if let encoded = try? JSONEncoder().encode(newPreferences) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            print("💾 [MyTasksPrefs] Saved SSE update to UserDefaults")
        }
    }

    /// Clear all preferences data on logout
    /// This prevents data leakage between users
    func clearData() {
        // Cancel any pending updates
        updateTask?.cancel()
        updateTask = nil

        // Reset to default preferences
        preferences = MyTasksPreferences()

        // Clear persisted data
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)

        print("🗑️ [MyTasksPrefs] Data cleared for logout")
    }
}
