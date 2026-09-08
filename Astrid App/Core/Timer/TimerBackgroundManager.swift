import Foundation
@preconcurrency import UserNotifications

/// Manages timer state persistence for background operation
/// When app goes to background, stores timer state and schedules completion notification
/// When app returns to foreground, calculates elapsed time and resumes timer
@MainActor
class TimerBackgroundManager {
    static let shared = TimerBackgroundManager()

    private let defaults = UserDefaults.standard
    private let notificationCenter = UNUserNotificationCenter.current()

    // UserDefaults keys for timer state
    private let kActiveTimerTaskId = "activeTimer.taskId"
    private let kActiveTimerTaskTitle = "activeTimer.taskTitle"
    private let kActiveTimerStartTime = "activeTimer.startTime"
    private let kActiveTimerDuration = "activeTimer.duration"
    private let kActiveTimerRemainingAtPause = "activeTimer.remainingAtPause"
    private let kActiveTimerIsPaused = "activeTimer.isPaused"

    private init() {}

    // MARK: - Timer State Model

    struct ActiveTimerState {
        let taskId: String
        let taskTitle: String
        let startTime: Date
        let durationSeconds: Int
        let remainingAtPause: Int?  // Only set if timer was paused
        let isPaused: Bool

        /// Calculate remaining time based on current time
        var remainingSeconds: Int {
            if isPaused, let remaining = remainingAtPause {
                return remaining
            }
            let elapsed = Int(Date().timeIntervalSince(startTime))
            return max(0, durationSeconds - elapsed)
        }

        /// Check if timer has completed
        var isCompleted: Bool {
            return remainingSeconds <= 0
        }

        /// When timer should complete
        var completionTime: Date {
            if isPaused {
                // If paused, completion is unknown - return far future
                return Date.distantFuture
            }
            return startTime.addingTimeInterval(TimeInterval(durationSeconds))
        }
    }

    // MARK: - Save/Load Timer State

    /// Save timer state when starting or updating
    func saveTimerState(taskId: String, taskTitle: String, durationSeconds: Int, remainingSeconds: Int, isPaused: Bool) {
        // Calculate start time from remaining seconds
        let startTime: Date
        if isPaused {
            // When paused, startTime doesn't matter, we use remainingAtPause
            startTime = Date()
        } else {
            // Running timer: startTime = now - (duration - remaining)
            let elapsedSeconds = durationSeconds - remainingSeconds
            startTime = Date().addingTimeInterval(TimeInterval(-elapsedSeconds))
        }

        defaults.set(taskId, forKey: kActiveTimerTaskId)
        defaults.set(taskTitle, forKey: kActiveTimerTaskTitle)
        defaults.set(startTime, forKey: kActiveTimerStartTime)
        defaults.set(durationSeconds, forKey: kActiveTimerDuration)
        defaults.set(isPaused, forKey: kActiveTimerIsPaused)

        if isPaused {
            defaults.set(remainingSeconds, forKey: kActiveTimerRemainingAtPause)
        } else {
            defaults.removeObject(forKey: kActiveTimerRemainingAtPause)
        }

        AppLog.debug("⏱️ [TimerBackgroundManager] Saved timer state: taskId=\(taskId), duration=\(durationSeconds)s, remaining=\(remainingSeconds)s, isPaused=\(isPaused)")
    }

    /// Load timer state if exists
    func loadTimerState() -> ActiveTimerState? {
        guard let taskId = defaults.string(forKey: kActiveTimerTaskId),
              let taskTitle = defaults.string(forKey: kActiveTimerTaskTitle),
              let startTime = defaults.object(forKey: kActiveTimerStartTime) as? Date else {
            return nil
        }

        let durationSeconds = defaults.integer(forKey: kActiveTimerDuration)
        let isPaused = defaults.bool(forKey: kActiveTimerIsPaused)
        let remainingAtPause = isPaused ? defaults.integer(forKey: kActiveTimerRemainingAtPause) : nil

        return ActiveTimerState(
            taskId: taskId,
            taskTitle: taskTitle,
            startTime: startTime,
            durationSeconds: durationSeconds,
            remainingAtPause: remainingAtPause,
            isPaused: isPaused
        )
    }

    /// Clear timer state (when timer completes or is cancelled)
    func clearTimerState() {
        defaults.removeObject(forKey: kActiveTimerTaskId)
        defaults.removeObject(forKey: kActiveTimerTaskTitle)
        defaults.removeObject(forKey: kActiveTimerStartTime)
        defaults.removeObject(forKey: kActiveTimerDuration)
        defaults.removeObject(forKey: kActiveTimerRemainingAtPause)
        defaults.removeObject(forKey: kActiveTimerIsPaused)

        AppLog.debug("⏱️ [TimerBackgroundManager] Cleared timer state")
    }

    // MARK: - Timer Notification

    /// Schedule a local notification for timer completion
    func scheduleTimerNotification(taskId: String, taskTitle: String, remainingSeconds: Int) async {
        guard remainingSeconds > 0 else {
            AppLog.debug("⚠️ [TimerBackgroundManager] Cannot schedule notification for completed timer")
            return
        }

        // Check notification permission
        let settings = await notificationCenter.notificationSettings()
        guard settings.authorizationStatus == .authorized else {
            AppLog.debug("⚠️ [TimerBackgroundManager] Notification permission not granted")
            return
        }

        // Cancel any existing timer notification first
        await cancelTimerNotification()

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Timer Complete!"
        content.body = taskTitle
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = "TIMER_COMPLETE"
        content.userInfo = [
            "taskId": taskId,
            "type": "timer_complete"
        ]

        // Create trigger for when timer completes
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(remainingSeconds),
            repeats: false
        )

        // Create and schedule request
        let request = UNNotificationRequest(
            identifier: "timer_\(taskId)",
            content: content,
            trigger: trigger
        )

        do {
            try await notificationCenter.add(request)
            AppLog.debug("✅ [TimerBackgroundManager] Scheduled timer notification for '\(taskTitle)' in \(remainingSeconds)s")
        } catch {
            AppLog.debug("❌ [TimerBackgroundManager] Failed to schedule timer notification: \(error)")
        }
    }

    /// Cancel timer notification
    func cancelTimerNotification() async {
        // Remove any timer notifications (they all start with "timer_")
        let pending = await notificationCenter.pendingNotificationRequests()
        let timerIds = pending.filter { $0.identifier.hasPrefix("timer_") }.map { $0.identifier }

        if !timerIds.isEmpty {
            notificationCenter.removePendingNotificationRequests(withIdentifiers: timerIds)
            AppLog.debug("🗑️ [TimerBackgroundManager] Cancelled \(timerIds.count) timer notification(s)")
        }
    }

    // MARK: - App Lifecycle Handlers

    /// Called when app goes to background - schedules notification if timer is running
    func handleAppDidEnterBackground() async {
        guard let state = loadTimerState(), !state.isPaused else {
            AppLog.debug("ℹ️ [TimerBackgroundManager] No running timer to track in background")
            return
        }

        let remaining = state.remainingSeconds
        if remaining > 0 {
            await scheduleTimerNotification(
                taskId: state.taskId,
                taskTitle: state.taskTitle,
                remainingSeconds: remaining
            )
            AppLog.debug("📱 [TimerBackgroundManager] App backgrounded with \(remaining)s remaining on timer")
        } else {
            AppLog.debug("⏰ [TimerBackgroundManager] Timer already completed while calculating background state")
        }
    }

    /// Called when app returns to foreground - returns updated state
    func handleAppWillEnterForeground() async -> ActiveTimerState? {
        // Cancel any pending timer notification (we're back in foreground)
        await cancelTimerNotification()

        guard let state = loadTimerState() else {
            return nil
        }

        AppLog.debug("📱 [TimerBackgroundManager] App foregrounded, timer remaining: \(state.remainingSeconds)s, completed: \(state.isCompleted)")
        return state
    }

    // MARK: - Timer Categories

    /// Register timer-specific notification category
    func registerTimerNotificationCategory() {
        let dismissAction = UNNotificationAction(
            identifier: "TIMER_DISMISS",
            title: "Dismiss",
            options: []
        )

        let completeAction = UNNotificationAction(
            identifier: "TIMER_COMPLETE_TASK",
            title: NSLocalizedString("notification.complete_task", comment: "Complete Task"),
            options: .foreground
        )

        let category = UNNotificationCategory(
            identifier: "TIMER_COMPLETE",
            actions: [completeAction, dismissAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        // Get existing categories and add timer category
        // Use async Task to properly handle MainActor isolation
        let center = notificationCenter
        _Concurrency.Task { @MainActor in
            let existingCategories = await center.notificationCategories()
            var categories = existingCategories
            // Remove old timer category if exists
            categories = categories.filter { $0.identifier != "TIMER_COMPLETE" }
            categories.insert(category)
            center.setNotificationCategories(categories)
            AppLog.debug("✅ [TimerBackgroundManager] Registered TIMER_COMPLETE notification category")
        }
    }
}
