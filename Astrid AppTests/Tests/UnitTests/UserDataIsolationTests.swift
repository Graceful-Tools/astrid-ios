import XCTest
@testable import Astrid_App

/// Unit tests for user data isolation between accounts
/// Verifies that sign-out properly clears all user data to prevent data leakage
/// Bug fix: Users were seeing previous user's data after signing out and creating new account
final class UserDataIsolationTests: XCTestCase {

    // MARK: - Test Keys (matching production keys)

    private let userIdKey = Constants.UserDefaults.userId
    private let userEmailKey = Constants.UserDefaults.userEmail
    private let userNameKey = Constants.UserDefaults.userName
    private let userImageKey = Constants.UserDefaults.userImage

    // Reminder settings keys
    private let reminderKeys = [
        "reminderPushEnabled",
        "reminderEmailEnabled",
        "defaultReminderOffset",
        "dailyDigestEnabled",
        "dailyDigestTime",
        "reminderTimezone",
        "quietHoursEnabled",
        "quietHoursStart",
        "quietHoursEnd",
        "reminderSettingsPending"
    ]

    // MARK: - Setup & Teardown

    override func setUp() {
        super.setUp()
        // Clean up any test data before each test
        clearAllTestData()
    }

    override func tearDown() {
        // Clean up after each test
        clearAllTestData()
        super.tearDown()
    }

    private func clearAllTestData() {
        // Clear user data keys
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userImageKey)

        // Clear reminder settings
        for key in reminderKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Clear other user data keys
        UserDefaults.standard.removeObject(forKey: "my_tasks_preferences")
        UserDefaults.standard.removeObject(forKey: "user_settings")
        UserDefaults.standard.removeObject(forKey: "GoogleOAuthCodeVerifier")
        UserDefaults.standard.removeObject(forKey: "pendingAttachments")
        UserDefaults.standard.removeObject(forKey: "oauth_token_cache")
        UserDefaults.standard.removeObject(forKey: "last_sync_timestamp")
        UserDefaults.standard.removeObject(forKey: "last_task_sync_timestamp")
        UserDefaults.standard.removeObject(forKey: "last_list_sync_timestamp")
        UserDefaults.standard.removeObject(forKey: "last_comment_sync_timestamp")
        UserDefaults.standard.removeObject(forKey: "AppleReminders.linkedLists")
        UserDefaults.standard.removeObject(forKey: "AppleReminders.lastSyncDate")
    }

    // MARK: - SyncManager Reset Tests

    @MainActor
    func testSyncManagerResetClearsAllTimestamps() {
        // Given: All sync timestamps are set
        let testDate = Date()
        UserDefaults.standard.set(testDate, forKey: "last_sync_timestamp")
        UserDefaults.standard.set(testDate, forKey: "last_task_sync_timestamp")
        UserDefaults.standard.set(testDate, forKey: "last_list_sync_timestamp")
        UserDefaults.standard.set(testDate, forKey: "last_comment_sync_timestamp")

        // When: Reset is called
        SyncManager.shared.resetSyncState()

        // Then: the stamp the app reads is gone, in memory and on disk
        XCTAssertNil(SyncManager.shared.lastSyncDate, "the next account must not inherit the last sync time")
        XCTAssertNil(UserDefaults.standard.object(forKey: "last_sync_timestamp"),
            "Main sync timestamp should be cleared")
        // The per-entity stamps below have had no writer since the core took sync over
        // (checked 2026-10-22, AITD-536); reset still clears them for installs that wrote them.
        XCTAssertNil(UserDefaults.standard.object(forKey: "last_task_sync_timestamp"),
            "Task sync timestamp should be cleared")
        XCTAssertNil(UserDefaults.standard.object(forKey: "last_list_sync_timestamp"),
            "List sync timestamp should be cleared")
        XCTAssertNil(UserDefaults.standard.object(forKey: "last_comment_sync_timestamp"),
            "Comment sync timestamp should be cleared")
    }

    @MainActor
    func testSyncManagerResetClearsInMemoryState() {
        // Given: SyncManager has completed initial sync
        // (We can't directly set this, but we can verify it resets)

        // When: Reset is called
        SyncManager.shared.resetSyncState()

        // Then: hasCompletedInitialSync should be false
        XCTAssertFalse(SyncManager.shared.hasCompletedInitialSync,
            "hasCompletedInitialSync should be false after reset")
        XCTAssertNil(SyncManager.shared.lastSyncDate,
            "lastSyncDate should be nil after reset")
    }

    // MARK: - MyTasksPreferencesService Clear Tests

    @MainActor
    func testMyTasksPreferencesServiceClearData() {
        // Given: Preferences are set with custom values
        let customPrefs = MyTasksPreferences(
            filterPriority: [1, 2],
            filterAssignee: ["user-123"],
            filterDueDate: "today",
            filterCompletion: "incomplete",
            sortBy: "priority"
        )
        if let encoded = try? JSONEncoder().encode(customPrefs) {
            UserDefaults.standard.set(encoded, forKey: "my_tasks_preferences")
        }

        // When: Clear is called
        MyTasksPreferencesService.shared.clearData()

        // Then: UserDefaults should be cleared
        XCTAssertNil(UserDefaults.standard.data(forKey: "my_tasks_preferences"),
            "my_tasks_preferences should be cleared from UserDefaults")

        // And: In-memory preferences should be reset to defaults
        let prefs = MyTasksPreferencesService.shared.preferences
        XCTAssertEqual(prefs.filterDueDate, "all",
            "filterDueDate should be reset to default 'all'")
        XCTAssertEqual(prefs.filterCompletion, "default",
            "filterCompletion should be reset to default")
        XCTAssertEqual(prefs.sortBy, "auto",
            "sortBy should be reset to default 'auto'")
    }

    // MARK: - UserSettingsService Clear Tests

    @MainActor
    func testUserSettingsServiceClearData() {
        // Given: Settings are set with custom values
        let customSettings = UserSettings(
            smartTaskCreationEnabled: false,
            emailToTaskEnabled: false,
            defaultTaskDueOffset: "tomorrow",
            defaultDueTime: "09:00"
        )
        if let encoded = try? JSONEncoder().encode(customSettings) {
            UserDefaults.standard.set(encoded, forKey: "user_settings")
        }

        // When: Clear is called
        UserSettingsService.shared.clearData()

        // Then: UserDefaults should be cleared
        XCTAssertNil(UserDefaults.standard.data(forKey: "user_settings"),
            "user_settings should be cleared from UserDefaults")

        // And: In-memory settings should be reset to defaults
        let settings = UserSettingsService.shared.settings
        XCTAssertEqual(settings.smartTaskCreationEnabled, true,
            "smartTaskCreationEnabled should be reset to default true")
        XCTAssertEqual(settings.emailToTaskEnabled, true,
            "emailToTaskEnabled should be reset to default true")
    }

    // MARK: - AppleRemindersService Clear Tests

    @MainActor
    func testAppleRemindersServiceClearAllData() {
        // Given: Apple Reminders data is set
        let testData: [String: String] = ["list-123": "calendar-456"]
        if let encoded = try? JSONEncoder().encode(testData) {
            UserDefaults.standard.set(encoded, forKey: "AppleReminders.linkedLists")
        }
        UserDefaults.standard.set(Date(), forKey: "AppleReminders.lastSyncDate")

        // When: Clear is called
        AppleRemindersService.shared.clearAllData()

        // Then: UserDefaults should be cleared
        XCTAssertNil(UserDefaults.standard.data(forKey: "AppleReminders.linkedLists"),
            "AppleReminders.linkedLists should be cleared")
        XCTAssertNil(UserDefaults.standard.object(forKey: "AppleReminders.lastSyncDate"),
            "AppleReminders.lastSyncDate should be cleared")

        // And: In-memory state should be reset
        XCTAssertTrue(AppleRemindersService.shared.linkedLists.isEmpty,
            "linkedLists should be empty after clear")
        XCTAssertEqual(AppleRemindersService.shared.linkedListCount, 0,
            "linkedListCount should be 0 after clear")
        XCTAssertNil(AppleRemindersService.shared.lastSyncDate,
            "lastSyncDate should be nil after clear")
    }

    // MARK: - TaskService Clear Tests

    @MainActor
    func testTaskServiceClearCache() {
        // Given: TaskService has some tasks (we can only verify it doesn't crash)
        // When: Clear is called
        TaskService.shared.clearCache()

        // Then: Tasks should be empty
        XCTAssertTrue(TaskService.shared.tasks.isEmpty,
            "tasks should be empty after clearCache")
    }

    // MARK: - ListService Clear Tests

    @MainActor
    func testListServiceClearCache() {
        // Given: ListService has some lists (we can only verify it doesn't crash)
        // When: Clear is called
        ListService.shared.clearCache()

        // Then: Lists should be empty
        XCTAssertTrue(ListService.shared.lists.isEmpty,
            "lists should be empty after clearCache")
    }

    // MARK: - UserImageCache Clear Tests

    @MainActor
    func testUserImageCacheClearCache() {
        // Given: Cache has some images
        UserImageCache.shared.setImageURL("https://example.com/image.jpg", for: "user-123")
        XCTAssertNotNil(UserImageCache.shared.getImageURL(userId: "user-123"))

        // When: Clear is called
        UserImageCache.shared.clearCache()

        // Then: Cache should be empty
        XCTAssertNil(UserImageCache.shared.getImageURL(userId: "user-123"),
            "Cached image URL should be nil after clearCache")
    }

    // MARK: - Complete Data Isolation Tests

    @MainActor
    func testCompleteUserDataClearance() {
        // Given: All types of user data are set (simulating a signed-in user)

        // User identity
        UserDefaults.standard.set("user-previous", forKey: userIdKey)
        UserDefaults.standard.set("previous@example.com", forKey: userEmailKey)
        UserDefaults.standard.set("Previous User", forKey: userNameKey)
        UserDefaults.standard.set("https://example.com/previous.jpg", forKey: userImageKey)

        // Reminder settings
        UserDefaults.standard.set(true, forKey: "reminderPushEnabled")
        UserDefaults.standard.set(true, forKey: "reminderEmailEnabled")
        UserDefaults.standard.set(30, forKey: "defaultReminderOffset")
        UserDefaults.standard.set(true, forKey: "dailyDigestEnabled")
        UserDefaults.standard.set("America/New_York", forKey: "reminderTimezone")
        UserDefaults.standard.set(true, forKey: "quietHoursEnabled")

        // Other user data
        UserDefaults.standard.set("test-verifier", forKey: "GoogleOAuthCodeVerifier")
        UserDefaults.standard.set(["file1.jpg"], forKey: "pendingAttachments")

        // User caches
        UserImageCache.shared.setImageURL("https://example.com/avatar.jpg", for: "user-previous")

        // When: All clear methods are called (simulating sign-out)
        // Clear UserDefaults - user identity
        UserDefaults.standard.removeObject(forKey: userIdKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userImageKey)

        // Clear reminder settings
        for key in reminderKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Clear other user data
        UserDefaults.standard.removeObject(forKey: "GoogleOAuthCodeVerifier")
        UserDefaults.standard.removeObject(forKey: "pendingAttachments")

        // Clear services
        SyncManager.shared.resetSyncState()
        TaskService.shared.clearCache()
        ListService.shared.clearCache()
        AppleRemindersService.shared.clearAllData()
        MyTasksPreferencesService.shared.clearData()
        UserSettingsService.shared.clearData()
        UserImageCache.shared.clearCache()
        ProfileCache.shared.clearAllCache()
        AIAgentCache.shared.clear()

        // Then: All user data should be cleared

        // User identity cleared
        XCTAssertNil(UserDefaults.standard.string(forKey: userIdKey),
            "userId should be nil after sign-out")
        XCTAssertNil(UserDefaults.standard.string(forKey: userEmailKey),
            "userEmail should be nil after sign-out")
        XCTAssertNil(UserDefaults.standard.string(forKey: userNameKey),
            "userName should be nil after sign-out")
        XCTAssertNil(UserDefaults.standard.string(forKey: userImageKey),
            "userImage should be nil after sign-out")

        // Reminder settings cleared
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "reminderPushEnabled"),
            "reminderPushEnabled should be false (default) after sign-out")
        XCTAssertNil(UserDefaults.standard.string(forKey: "reminderTimezone"),
            "reminderTimezone should be nil after sign-out")

        // Other user data cleared
        XCTAssertNil(UserDefaults.standard.string(forKey: "GoogleOAuthCodeVerifier"),
            "GoogleOAuthCodeVerifier should be nil after sign-out")
        XCTAssertNil(UserDefaults.standard.array(forKey: "pendingAttachments"),
            "pendingAttachments should be nil after sign-out")

        // Services reset
        XCTAssertFalse(SyncManager.shared.hasCompletedInitialSync,
            "hasCompletedInitialSync should be false after sign-out")
        XCTAssertTrue(TaskService.shared.tasks.isEmpty,
            "tasks should be empty after sign-out")
        XCTAssertTrue(ListService.shared.lists.isEmpty,
            "lists should be empty after sign-out")
        XCTAssertTrue(AppleRemindersService.shared.linkedLists.isEmpty,
            "linkedLists should be empty after sign-out")

        // Caches cleared
        XCTAssertNil(UserImageCache.shared.getImageURL(userId: "user-previous"),
            "UserImageCache should be cleared after sign-out")
    }

    // MARK: - New User Session Tests

    @MainActor
    func testNewUserGetsCleanState() {
        // Given: Previous user data existed and was cleared
        UserDefaults.standard.set("previous-user-id", forKey: userIdKey)
        SyncManager.shared.resetSyncState()
        TaskService.shared.clearCache()
        ListService.shared.clearCache()
        UserImageCache.shared.clearCache()
        UserDefaults.standard.removeObject(forKey: userIdKey)

        // When: A new user signs in (simulated by setting new user ID)
        let newUserId = "new-user-id"
        let newUserEmail = "newuser@example.com"
        UserDefaults.standard.set(newUserId, forKey: userIdKey)
        UserDefaults.standard.set(newUserEmail, forKey: userEmailKey)

        // Then: New user should have clean state
        XCTAssertEqual(UserDefaults.standard.string(forKey: userIdKey), newUserId,
            "New user ID should be set")
        XCTAssertEqual(UserDefaults.standard.string(forKey: userEmailKey), newUserEmail,
            "New user email should be set")

        // And: No data from previous user should be visible
        XCTAssertTrue(TaskService.shared.tasks.isEmpty,
            "New user should start with empty tasks")
        XCTAssertTrue(ListService.shared.lists.isEmpty,
            "New user should start with empty lists")
        XCTAssertFalse(SyncManager.shared.hasCompletedInitialSync,
            "New user should start with hasCompletedInitialSync = false")
        XCTAssertNil(UserImageCache.shared.getImageURL(userId: "previous-user-id"),
            "Previous user's cached images should not be visible")
    }

    // MARK: - Edge Case Tests

    @MainActor
    func testMultipleSignOutsAreIdempotent() {
        // Given: User data is set
        UserDefaults.standard.set("user-123", forKey: userIdKey)

        // When: Sign-out is called multiple times
        for _ in 0..<3 {
            UserDefaults.standard.removeObject(forKey: userIdKey)
            SyncManager.shared.resetSyncState()
            TaskService.shared.clearCache()
            ListService.shared.clearCache()
            UserImageCache.shared.clearCache()
        }

        // Then: Should not crash and data should be cleared
        XCTAssertNil(UserDefaults.standard.string(forKey: userIdKey),
            "userId should be nil after multiple sign-outs")
        XCTAssertTrue(TaskService.shared.tasks.isEmpty,
            "tasks should be empty after multiple sign-outs")
    }
}
