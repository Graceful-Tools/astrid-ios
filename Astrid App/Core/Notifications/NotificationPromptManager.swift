import Foundation
import UserNotifications
import Combine

/// Manages prompting users to enable push notifications
/// Tracks prompt attempts: 3 times initially, then once per month
@MainActor
class NotificationPromptManager: ObservableObject {
    static let shared = NotificationPromptManager()

    private let userDefaults = UserDefaults.standard

    // UserDefaults keys
    private let promptCountKey = "notificationPromptCount"
    private let lastPromptDateKey = "lastNotificationPromptDate"

    // Configuration
    private let maxInitialPrompts = 3
    private let monthlyPromptIntervalDays = 30

    /// Published state for UI binding - shows native permission request
    @Published var showPromptAlert = false

    /// Published state for "go to Settings" prompt when permission was denied
    @Published var showSettingsPrompt = false

    private init() {}

    // MARK: - Public API

    /// Check if we should prompt the user to enable notifications
    /// Returns a tuple: (shouldPrompt, needsSettings)
    /// - shouldPrompt: true if we should show any prompt
    /// - needsSettings: true if permission was denied and user needs to go to Settings
    func shouldPromptForNotifications() async -> (shouldPrompt: Bool, needsSettings: Bool) {
        await shouldPromptForNotifications(isUITesting: UITestSession.suppressesInterruptingPrompts)
    }

    /// The same question with the run's nature passed in, so a test can ask it without
    /// relaunching the process under a flag.
    ///
    /// A UI-test run never prompts (task b86c97c5). The alert is modal: everything beneath it
    /// reports not-hittable and every tap is swallowed, so a prompt that opens over a test run
    /// does not merely add a step — it stops the suite from being able to touch the app at all.
    func shouldPromptForNotifications(isUITesting: Bool) async -> (shouldPrompt: Bool, needsSettings: Bool) {
        if isUITesting { return (false, false) }

        // First, check if notifications are already authorized
        let status = await NotificationManager.shared.checkPermissionStatus()

        // If already authorized, no need to prompt
        if status == .authorized {
            return (false, false)
        }

        // Check prompt count and timing
        let promptCount = userDefaults.integer(forKey: promptCountKey)
        let lastPromptDate = userDefaults.object(forKey: lastPromptDateKey) as? Date

        var shouldPrompt = false

        // If we haven't reached max initial prompts, allow prompting
        if promptCount < maxInitialPrompts {
            shouldPrompt = true
        } else if let lastDate = lastPromptDate {
            // After max prompts, only prompt once per month
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            shouldPrompt = daysSinceLastPrompt >= monthlyPromptIntervalDays
        } else {
            // No last prompt date recorded but count >= max, allow one more
            shouldPrompt = true
        }

        if !shouldPrompt {
            return (false, false)
        }

        // If denied, user needs to go to Settings
        if status == .denied {
            return (true, true)
        }

        // Not determined - can show native dialog
        return (true, false)
    }

    /// Call this when user signs in or sets a due date on a task
    /// Will show the appropriate notification prompt if needed
    func checkAndPromptAfterDateSet() async {
        let (shouldPrompt, needsSettings) = await shouldPromptForNotifications()

        guard shouldPrompt else {
            return
        }

        // Record this prompt attempt
        recordPromptAttempt()

        // Show the appropriate alert
        await MainActor.run {
            if needsSettings {
                showSettingsPrompt = true
            } else {
                showPromptAlert = true
            }
        }
    }

    /// Request notification permission (called when user taps "Enable" in the alert)
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await NotificationManager.shared.requestPermission()

            if granted {
                // Also update ReminderSettings to reflect push is enabled
                ReminderSettings.shared.pushEnabled = true
                await ReminderSettings.shared.save()
            }

            return granted
        } catch {
            print("❌ Failed to request notification permission: \(error)")
            return false
        }
    }

    /// Open the app's Settings page where user can enable notifications
    func openSettings() {
        PlatformApplication.openAppSettings()
    }

    // MARK: - Private Helpers

    private func recordPromptAttempt() {
        let currentCount = userDefaults.integer(forKey: promptCountKey)
        userDefaults.set(currentCount + 1, forKey: promptCountKey)
        userDefaults.set(Date(), forKey: lastPromptDateKey)
    }

    /// Reset prompt tracking (useful for testing)
    func resetPromptTracking() {
        userDefaults.removeObject(forKey: promptCountKey)
        userDefaults.removeObject(forKey: lastPromptDateKey)
    }
}
