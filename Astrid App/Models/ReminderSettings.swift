//  ReminderSettings.swift
//  Moved out of Views/Settings/ReminderSettingsView.swift so the shared
//  notification/sync services can use it on macOS (it is a settings model, not a view).

import Foundation
import Combine
import UserNotifications

enum ReminderOffset: Int, CaseIterable {
    case atTime = 0
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case oneDay = 1440
    case oneWeek = 10080

    var displayName: String {
        switch self {
        case .atTime: return NSLocalizedString("time.atDueTime", comment: "")
        case .fiveMinutes: return String(format: NSLocalizedString("time.minutesBefore", comment: ""), 5)
        case .fifteenMinutes: return String(format: NSLocalizedString("time.minutesBefore", comment: ""), 15)
        case .thirtyMinutes: return String(format: NSLocalizedString("time.minutesBefore", comment: ""), 30)
        case .oneHour: return NSLocalizedString("time.hourBefore", comment: "")
        case .twoHours: return String(format: NSLocalizedString("time.hoursBefore", comment: ""), 2)
        case .oneDay: return NSLocalizedString("time.dayBefore", comment: "")
        case .oneWeek: return NSLocalizedString("time.weekBefore", comment: "")
        }
    }
}

@MainActor
class ReminderSettings: ObservableObject {
    static let shared = ReminderSettings()

    @Published var pushEnabled: Bool = false
    @Published var emailEnabled: Bool = true
    @Published var defaultReminderOffset: ReminderOffset = .fifteenMinutes
    @Published var dailyDigestEnabled: Bool = false
    @Published var dailyDigestTime: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
    @Published var timezone: String = TimeZone.current.identifier
    @Published var quietHoursEnabled: Bool = false
    @Published var quietHoursStart: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0))!
    @Published var quietHoursEnd: Date = Calendar.current.date(from: DateComponents(hour: 8, minute: 0))!

    @Published var isSyncing: Bool = false
    @Published var lastSyncError: String?
    @Published var hasPendingChanges: Bool = false // Track pending sync
    private var lastFetchTime: Date?

    private let apiClient = RemoteResourceService.shared
    private let networkMonitor = NetworkMonitor.shared
    private var networkObserver: NSObjectProtocol?

    /// Save settings (optimistic, local-first)
    /// Saves to UserDefaults immediately, syncs to server in background
    func save() async {
        // 1. Save to UserDefaults immediately (instant local persistence)
        saveToUserDefaults()

        // 2. Mark as having pending changes
        hasPendingChanges = true

        // 3. Trigger background sync (fire-and-forget)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                await self?.syncPendingChanges()
            }
        }
    }

    private func saveToUserDefaults() {
        UserDefaults.standard.set(pushEnabled, forKey: "reminderPushEnabled")
        UserDefaults.standard.set(emailEnabled, forKey: "reminderEmailEnabled")
        UserDefaults.standard.set(defaultReminderOffset.rawValue, forKey: "defaultReminderOffset")
        UserDefaults.standard.set(dailyDigestEnabled, forKey: "dailyDigestEnabled")
        UserDefaults.standard.set(dailyDigestTime, forKey: "dailyDigestTime")
        UserDefaults.standard.set(timezone, forKey: "reminderTimezone")
        UserDefaults.standard.set(quietHoursEnabled, forKey: "quietHoursEnabled")
        UserDefaults.standard.set(quietHoursStart, forKey: "quietHoursStart")
        UserDefaults.standard.set(quietHoursEnd, forKey: "quietHoursEnd")
        UserDefaults.standard.set(true, forKey: "reminderSettingsPending") // Track pending state
    }

    func fetch(force: Bool = false) async {
        // Throttle: Don't fetch if we fetched in the last 30 seconds (unless forced)
        if !force, let lastFetch = lastFetchTime, Date().timeIntervalSince(lastFetch) < 30 {
            print("⏭️ [ReminderSettings] Skipping fetch - too recent")
            return
        }

        isSyncing = true
        lastSyncError = nil

        do {
            print("📡 [ReminderSettings] Fetching settings from server...")
            let response = try await apiClient.getUserSettings()
            let settings = response.settings.reminderSettings

            // Update from server
            pushEnabled = settings.enablePushReminders
            emailEnabled = settings.enableEmailReminders
            defaultReminderOffset = ReminderOffset(rawValue: settings.defaultReminderTime) ?? .fifteenMinutes
            dailyDigestEnabled = settings.enableDailyDigest
            timezone = settings.dailyDigestTimezone

            // Parse dailyDigestTime (HH:MM format)
            if let time = parseTime(settings.dailyDigestTime) {
                dailyDigestTime = time
            }

            // Parse quiet hours
            if let startStr = settings.quietHoursStart, let start = parseTime(startStr) {
                quietHoursEnabled = true
                quietHoursStart = start
            } else {
                quietHoursEnabled = false
            }

            if let endStr = settings.quietHoursEnd, let end = parseTime(endStr) {
                quietHoursEnd = end
            }

            // Save to UserDefaults only (don't sync back to server)
            saveToUserDefaults()

            lastFetchTime = Date()
            print("✅ [ReminderSettings] Fetched settings from server")
        } catch {
            print("❌ [ReminderSettings] Failed to fetch settings: \(error)")
            lastSyncError = error.localizedDescription

            // Fallback to UserDefaults
            loadFromUserDefaults()
        }

        isSyncing = false
    }

    /// Sync pending changes to server (called by SyncManager or network observer)
    func syncPendingChanges() async {
        guard hasPendingChanges else {
            print("⏭️ [ReminderSettings] No pending changes to sync")
            return
        }

        guard networkMonitor.isConnected else {
            print("📵 [ReminderSettings] Cannot sync - no network")
            return
        }

        print("🔄 [ReminderSettings] Syncing pending settings changes...")

        do {
            let update = ReminderSettingsUpdate(
                enablePushReminders: pushEnabled,
                enableEmailReminders: emailEnabled,
                defaultReminderTime: defaultReminderOffset.rawValue,
                enableDailyDigest: dailyDigestEnabled,
                dailyDigestTime: formatTime(dailyDigestTime),
                dailyDigestTimezone: timezone,
                quietHoursStart: quietHoursEnabled ? formatTime(quietHoursStart) : nil,
                quietHoursEnd: quietHoursEnabled ? formatTime(quietHoursEnd) : nil
            )

            _ = try await apiClient.updateUserSettings(reminderSettings: update)

            // Mark as synced
            await MainActor.run {
                hasPendingChanges = false
                UserDefaults.standard.set(false, forKey: "reminderSettingsPending")
            }

            print("✅ [ReminderSettings] Settings synced successfully")
        } catch {
            print("❌ [ReminderSettings] Failed to sync settings: \(error)")
            await MainActor.run {
                lastSyncError = error.localizedDescription
            }
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func parseTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        guard let time = formatter.date(from: timeString) else { return nil }

        // Combine with today's date
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(from: components)
    }

    private init() {
        loadFromUserDefaults()

        // Setup network observer for auto-sync
        setupNetworkObserver()

        // Fetch from server in background (skip in test mode)
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            _Concurrency.Task {
                await fetch()
            }
        }
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Network Observer

    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                print("🌐 [ReminderSettings] Network restored, syncing pending changes...")
                await self?.syncPendingChanges()
            }
        }
    }

    // MARK: - Test Helpers

    /// Load settings from UserDefaults (useful for testing)
    func loadFromUserDefaults() {
        pushEnabled = UserDefaults.standard.bool(forKey: "reminderPushEnabled")
        emailEnabled = UserDefaults.standard.bool(forKey: "reminderEmailEnabled")
        defaultReminderOffset = ReminderOffset(rawValue: UserDefaults.standard.integer(forKey: "defaultReminderOffset")) ?? .fifteenMinutes
        dailyDigestEnabled = UserDefaults.standard.bool(forKey: "dailyDigestEnabled")
        if let time = UserDefaults.standard.object(forKey: "dailyDigestTime") as? Date {
            dailyDigestTime = time
        }
        timezone = UserDefaults.standard.string(forKey: "reminderTimezone") ?? TimeZone.current.identifier
        quietHoursEnabled = UserDefaults.standard.bool(forKey: "quietHoursEnabled")
        if let start = UserDefaults.standard.object(forKey: "quietHoursStart") as? Date {
            quietHoursStart = start
        }
        if let end = UserDefaults.standard.object(forKey: "quietHoursEnd") as? Date {
            quietHoursEnd = end
        }

        // Load pending state (local-first)
        hasPendingChanges = UserDefaults.standard.bool(forKey: "reminderSettingsPending")

        lastFetchTime = nil
        isSyncing = false
        lastSyncError = nil
    }
}
