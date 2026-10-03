import AstridCore
import Foundation
import Combine

/// My Tasks filter preferences synced across devices
// Marked `nonisolated` so its Codable conformance is usable off the main actor, where
// astrid-core's answers are decoded (AITD-320). Only value-type fields, so thread-safe.
nonisolated struct MyTasksPreferences: Codable, Equatable {
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
            AppLog.debug("✅ [MyTasksPrefs] Loaded from UserDefaults")
        } else {
            // Start with default preferences
            self.preferences = MyTasksPreferences()
            AppLog.debug("ℹ️ [MyTasksPrefs] Using default preferences")
        }

        // Load from server in background
        _Concurrency.Task {
            await fetchPreferences()
        }
    }

    /// Fetch them from the account through astrid-core, which remembers the answer in its cache
    /// too. The UserDefaults snapshot has already drawn the screen, so a failure here is not one.
    func fetchPreferences() async {
        do {
            let fetched = try await AppCore.shared.session.run(
                CoreCommand(kind: "refreshMyTasks"), as: MyTasksPreferences.self)
            remember(fetched)
        } catch {
            AppLog.debug("❌ [MyTasksPrefs] Error fetching preferences: \(error)")
        }
    }

    /// Change them: on screen and in UserDefaults at once, to the account 300 ms after the last
    /// change. Not queued when offline — a filter replayed a week later would move a screen under
    /// whoever is looking at it (astrid-core `set_my_tasks_preferences`).
    func updatePreferences(_ updates: MyTasksPreferences) async {
        updateTask?.cancel()
        remember(updates)
        updateTask = _Concurrency.Task {
            try? await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
            guard !_Concurrency.Task.isCancelled else { return }
            var command = CoreCommand(kind: "setMyTasksFilters")
            command.set("filterPriority", updates.filterPriority)
            command.set("filterAssignee", updates.filterAssignee)
            command.set("filterDueDate", updates.filterDueDate)
            command.set("filterCompletion", updates.filterCompletion)
            command.set("sortBy", updates.sortBy)
            command.set("manualSortOrder", updates.manualSortOrder)
            do {
                try await AppCore.shared.session.run(command)
            } catch {
                AppLog.debug("❌ Error updating My Tasks preferences: \(error)")
            }
        }
    }

    private func remember(_ preferences: MyTasksPreferences) {
        self.preferences = preferences
        if let encoded = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
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

        AppLog.debug("🗑️ [MyTasksPrefs] Data cleared for logout")
    }
}
