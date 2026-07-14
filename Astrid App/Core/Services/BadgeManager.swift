import Foundation
import UserNotifications

/// BadgeManager handles app icon badge updates for tasks due on or before today
/// Badge count reflects tasks matching these criteria:
/// 1. Assigned to current user (assigneeId must match, NOT unassigned)
/// 2. Incomplete
/// 3. Due on or before today (overdue OR due today)
@MainActor
class BadgeManager {
    static let shared = BadgeManager()

    private let center = UNUserNotificationCenter.current()

    private init() {
        print("📛 [BadgeManager] Initialized")
    }

    // MARK: - Badge Update

    /// Update app badge count for tasks due on or before today
    /// Criteria: (1) Assigned to current user (2) Incomplete (3) Due on or before today
    /// - Parameter tasks: Array of tasks to analyze
    func updateBadge(with tasks: [Task]) async {
        // Get current user ID
        guard let currentUserId = AuthManager.shared.userId else {
            print("⚠️ [BadgeManager] No current user ID, clearing badge")
            await setBadgeCount(0)
            return
        }

        // Filter for tasks matching all 3 criteria:
        // 1. Assigned to current user (assigneeId must match exactly, NOT unassigned)
        // 2. Incomplete
        // 3. Due on or before today (isDueToday OR isOverdue)
        let tasksToCount = tasks.filter { task in
            let isMyTask = task.assigneeId == currentUserId
            return isMyTask && !task.completed && (task.isDueToday || task.isOverdue)
        }

        let count = tasksToCount.count
        await setBadgeCount(count)
    }

    /// Set badge count directly
    /// - Parameter count: Badge count (0 will clear the badge)
    func setBadgeCount(_ count: Int) async {
        do {
            // iOS 16+ uses setBadgeCount
            if #available(iOS 16.0, *) {
                try await center.setBadgeCount(count)
            } else {
                // iOS 15 and below - use UIApplication (requires main thread)
                await MainActor.run {
                    PlatformApplication.setBadgeCount(count)
                }
            }

            // Badge updated silently - logging only on errors
        } catch {
            print("❌ [BadgeManager] Failed to set badge count: \(error)")
        }
    }

    /// Clear the app badge (set to 0)
    func clearBadge() async {
        await setBadgeCount(0)
    }

    // MARK: - Permission Check

    /// Check if badge permission is granted
    func hasBadgePermission() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.badgeSetting == .enabled
    }
}

// MARK: - Task Extensions for Due/Overdue Logic

extension Task {
    /// Check if task is due today (same calendar day as now).
    ///
    /// Matches web's `isTaskDueToday` in `astrid-web/lib/date-filter-utils.ts`:
    /// - All-day: compare UTC date components (date-only, timezone-independent).
    /// - Timed: same LOCAL calendar day (regardless of whether the time has
    ///   already passed today — a 9am task is still "due today" at 10am).
    ///
    /// For "due today AND not yet passed" callers, combine with `!isOverdue`.
    var isDueToday: Bool {
        guard let dueDate = dueDateTime else { return false }

        let calendar = Calendar.current
        let now = Date()

        if isAllDay {
            var utcCalendar = Calendar.current
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!
            let dueDateComponents = utcCalendar.dateComponents([.year, .month, .day], from: dueDate)
            let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)
            return dueDateComponents.year == todayComponents.year &&
                   dueDateComponents.month == todayComponents.month &&
                   dueDateComponents.day == todayComponents.day
        } else {
            return calendar.isDateInToday(dueDate)
        }
    }

    /// Check if task is overdue (due date passed and not completed)
    var isOverdue: Bool {
        guard let dueDate = dueDateTime else { return false }

        let calendar = Calendar.current
        let now = Date()

        // For all-day tasks: Extract date components from UTC and compare to today
        // For timed tasks: overdue if due time has passed
        if isAllDay {
            // All-day tasks are stored at UTC midnight representing the date
            // Extract the date components and check if before today
            var utcCalendar = Calendar.current
            utcCalendar.timeZone = TimeZone(identifier: "UTC")!

            let dueDateComponents = utcCalendar.dateComponents([.year, .month, .day], from: dueDate)
            let todayComponents = calendar.dateComponents([.year, .month, .day], from: now)

            // Create dates from components for comparison
            guard let dueDay = calendar.date(from: dueDateComponents),
                  let today = calendar.date(from: todayComponents) else {
                return false
            }

            return dueDay < today
        } else {
            return dueDate < now
        }
    }
}
