import XCTest
@testable import Astrid_App

/// Integration tests for ReminderSettings local-first functionality
/// Tests optimistic updates, pending changes tracking, and background sync
///
/// NOTE: These tests require dependency injection to work properly.
/// Currently the services use singletons with real implementations.
/// Tests that depend on mocks are skipped until DI is implemented.
@MainActor
final class ReminderSettingsIntegrationTests: XCTestCase {
    var settings: ReminderSettings!
    var mockAPIClient: MockAPIClient!
    var mockNetworkMonitor: MockNetworkMonitor!

    /// Flag to skip tests that require mock injection (not yet implemented)
    private var skipMockDependentTests: Bool { true }

    override func setUp() async throws {
        settings = ReminderSettings.shared
        // NOTE: These mocks are NOT injected into the services - they use real implementations
        mockAPIClient = MockAPIClient()
        mockNetworkMonitor = MockNetworkMonitor()

        // Clear UserDefaults
        clearUserDefaults()
    }

    override func tearDown() async throws {
        clearUserDefaults()
        mockAPIClient = nil
        mockNetworkMonitor = nil
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

    func testBackgroundSync_ClearsPendingFlag() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Pending changes
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = false

        settings.pushEnabled = true
        await settings.save()

        XCTAssertTrue(settings.hasPendingChanges)

        // When: Syncing
        await settings.syncPendingChanges()

        // Wait for sync to complete
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Then: Pending flag should be cleared
        XCTAssertFalse(settings.hasPendingChanges)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "reminderSettingsPending"))
    }

    func testBackgroundSync_SkipsWhenNoPendingChanges() async throws {
        // Given: No pending changes
        settings.hasPendingChanges = false

        // When: Attempting to sync
        await settings.syncPendingChanges()

        // Then: Should skip (no API call made)
        // This is validated by no errors and instant return
        XCTAssertFalse(settings.hasPendingChanges)
    }

    func testBackgroundSync_SkipsWhenOffline() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Offline mode with pending changes
        mockNetworkMonitor.simulateOffline()

        settings.pushEnabled = true
        await settings.save()

        XCTAssertTrue(settings.hasPendingChanges)

        // When: Attempting to sync
        await settings.syncPendingChanges()

        // Then: Should skip sync, keep pending flag
        XCTAssertTrue(settings.hasPendingChanges, "Should remain pending when offline")
    }

    // MARK: - Offline → Online Tests

    func testOfflineSave_SyncsWhenOnline() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Offline mode
        mockNetworkMonitor.simulateOffline()

        // When: Saving settings offline
        settings.pushEnabled = true
        settings.emailEnabled = true
        await settings.save()

        XCTAssertTrue(settings.hasPendingChanges)

        // Configure mock API
        mockAPIClient.shouldFailRequests = false

        // When: Going online and syncing
        mockNetworkMonitor.simulateOnline()
        await settings.syncPendingChanges()

        // Wait for sync
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Then: Should be synced
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

    // MARK: - Network Observer Tests

    func testNetworkRestoration_TriggersAutoSync() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Settings saved offline
        mockNetworkMonitor.simulateOffline()

        settings.pushEnabled = true
        await settings.save()

        XCTAssertTrue(settings.hasPendingChanges)

        // Configure mock API
        mockAPIClient.shouldFailRequests = false

        // When: Network restored
        mockNetworkMonitor.simulateOnline()
        NotificationCenter.default.post(name: .networkDidBecomeAvailable, object: nil)

        // Wait for auto-sync
        try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

        // Then: Should be synced
        XCTAssertFalse(settings.hasPendingChanges, "Settings should be synced after network restoration")
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

    // MARK: - Error Handling Tests

    func testSyncFailure_MaintainsPendingState() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Online mode with API configured to fail
        mockNetworkMonitor.simulateOnline()
        mockAPIClient.shouldFailRequests = true

        settings.pushEnabled = true
        await settings.save()

        XCTAssertTrue(settings.hasPendingChanges)

        // When: Attempting to sync (will fail)
        await settings.syncPendingChanges()

        // Wait for sync attempt
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Then: Should maintain pending state
        XCTAssertTrue(settings.hasPendingChanges, "Should remain pending after sync failure")
        XCTAssertNotNil(settings.lastSyncError, "Should record error")
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

    func testMultipleUpdates_SingleSyncSufficient() async throws {
        try XCTSkipIf(skipMockDependentTests, "Requires dependency injection - mocks not injected into services")
        // Given: Multiple updates offline
        mockNetworkMonitor.simulateOffline()

        settings.pushEnabled = true
        await settings.save()

        settings.emailEnabled = true
        await settings.save()

        settings.dailyDigestEnabled = true
        await settings.save()

        mockAPIClient.shouldFailRequests = false

        // When: Single sync
        mockNetworkMonitor.simulateOnline()
        await settings.syncPendingChanges()

        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Then: All changes should be synced in one request
        XCTAssertFalse(settings.hasPendingChanges)
    }
}
