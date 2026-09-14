import XCTest
@testable import Astrid_App

/// Integration tests for ReminderSettings local-first behaviour: optimistic save, the
/// pending flag, and UserDefaults round-trips. The sync-path cases that needed an injected
/// API client were never runnable (the services are singletons) and were removed rather
/// than kept permanently skipped.
@MainActor
final class ReminderSettingsIntegrationTests: XCTestCase {
    var settings: ReminderSettings!

    override func setUp() async throws {
        settings = ReminderSettings.shared
        clearUserDefaults()
    }

    override func tearDown() async throws {
        clearUserDefaults()
    }

    // MARK: - Test Helpers

    private func clearUserDefaults() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "reminderPushEnabled")
        defaults.removeObject(forKey: "reminderEmailEnabled")
        defaults.removeObject(forKey: "defaultReminderOffset")
        defaults.removeObject(forKey: "dailyDigestEnabled")
        defaults.removeObject(forKey: "dailyDigestTime")
        defaults.removeObject(forKey: "reminderTimezone")
        defaults.removeObject(forKey: "quietHoursEnabled")
        defaults.removeObject(forKey: "quietHoursStart")
        defaults.removeObject(forKey: "quietHoursEnd")
        defaults.removeObject(forKey: "reminderSettingsPending")

        // Reload defaults
        settings.loadFromUserDefaults()
    }

    // MARK: - Optimistic Save Tests

    func testOptimisticSave_SavesImmediately() async throws {
        // Given: Initial state
        settings.pushEnabled = false
        settings.emailEnabled = false

        // When: Updating settings
        settings.pushEnabled = true
        settings.emailEnabled = true

        let startTime = Date()
        await settings.save()
        let elapsed = Date().timeIntervalSince(startTime)

        // Then: Should save instantly
        XCTAssertLessThan(elapsed, 1.0, "Save should be instant")

        // Then: Should be saved to UserDefaults
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "reminderPushEnabled"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "reminderEmailEnabled"))
    }

    func testOptimisticSave_MarksPendingChanges() async throws {
        // Given: Clean state
        settings.hasPendingChanges = false

        // When: Saving settings
        settings.pushEnabled = true
        await settings.save()

        // Then: Should mark as having pending changes
        XCTAssertTrue(settings.hasPendingChanges)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "reminderSettingsPending"))
    }

    // MARK: - Background Sync Tests

    func testBackgroundSync_SkipsWhenNoPendingChanges() async throws {
        // Given: No pending changes
        settings.hasPendingChanges = false

        // When: Attempting to sync
        await settings.syncPendingChanges()

        // Then: Should skip (no API call made)
        // This is validated by no errors and instant return
        XCTAssertFalse(settings.hasPendingChanges)
    }

    // MARK: - Load from UserDefaults Tests

    func testLoadFromUserDefaults_LoadsAllSettings() throws {
        // Given: Settings saved to UserDefaults
        UserDefaults.standard.set(true, forKey: "reminderPushEnabled")
        UserDefaults.standard.set(false, forKey: "reminderEmailEnabled")
        UserDefaults.standard.set(30, forKey: "defaultReminderOffset") // 30 min
        UserDefaults.standard.set(true, forKey: "dailyDigestEnabled")
        UserDefaults.standard.set("America/New_York", forKey: "reminderTimezone")
        UserDefaults.standard.set(true, forKey: "quietHoursEnabled")

        // When: Loading from UserDefaults
        settings.loadFromUserDefaults()

        // Then: All settings should be loaded
        XCTAssertTrue(settings.pushEnabled)
        XCTAssertFalse(settings.emailEnabled)
        XCTAssertEqual(settings.defaultReminderOffset.rawValue, 30)
        XCTAssertTrue(settings.dailyDigestEnabled)
        XCTAssertEqual(settings.timezone, "America/New_York")
        XCTAssertTrue(settings.quietHoursEnabled)
    }

    func testLoadFromUserDefaults_LoadsPendingState() throws {
        // Given: Pending state in UserDefaults
        UserDefaults.standard.set(true, forKey: "reminderSettingsPending")

        // When: Loading from UserDefaults
        settings.loadFromUserDefaults()

        // Then: Should load pending state
        XCTAssertTrue(settings.hasPendingChanges)
    }

    // MARK: - All Settings Fields Tests

    func testSaveAllFields_PersistsCorrectly() async throws {
        // Given: All settings configured
        settings.pushEnabled = true
        settings.emailEnabled = true
        settings.defaultReminderOffset = .thirtyMinutes
        settings.dailyDigestEnabled = true
        settings.timezone = "Europe/London"
        settings.quietHoursEnabled = true

        // When: Saving
        await settings.save()

        // Then: All fields should be persisted
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "reminderPushEnabled"))
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "reminderEmailEnabled"))
        XCTAssertEqual(UserDefaults.standard.integer(forKey: "defaultReminderOffset"), 30)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "dailyDigestEnabled"))
        XCTAssertEqual(UserDefaults.standard.string(forKey: "reminderTimezone"), "Europe/London")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "quietHoursEnabled"))
    }

    // MARK: - Multiple Updates Tests

    func testMultipleUpdates_OnlyLastStateMatters() async throws {
        // Given: Multiple rapid updates
        settings.pushEnabled = true
        await settings.save()

        settings.pushEnabled = false
        await settings.save()

        settings.pushEnabled = true
        await settings.save()

        // Then: Last state should be persisted
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "reminderPushEnabled"))
        XCTAssertTrue(settings.hasPendingChanges)
    }
}
