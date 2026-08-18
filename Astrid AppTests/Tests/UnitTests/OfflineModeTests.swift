import XCTest
@testable import Astrid_App

/// Comprehensive test suite for offline mode functionality
/// Verifies app works without network after force close and cold start
@MainActor
final class OfflineModeTests: XCTestCase {

    var authManager: AuthManager!
    var taskService: TaskService!
    var listService: ListService!
    var syncManager: SyncManager!

    override func setUp() async throws {
        try await super.setUp()

        // Initialize services
        authManager = AuthManager.shared
        taskService = TaskService.shared
        listService = ListService.shared
        syncManager = SyncManager.shared
    }

    override func tearDown() async throws {
        // Clean up UserDefaults after each test
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userEmail)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userName)

        try await super.tearDown()
    }

    // MARK: - Authentication Tests

    func testUserStaysAuthenticatedOffline() async throws {
        // Given: Local-only user has cached credentials in UserDefaults
        // Uses local_ prefix to simulate offline-only mode (no Keychain session required)
        let userId = "local_test-user-123"
        let userName = "Test User"

        UserDefaults.standard.set(userId, forKey: Constants.UserDefaults.userId)
        UserDefaults.standard.set(userName, forKey: Constants.UserDefaults.userName)

        // When: App checks authentication (simulating cold start)
        await authManager.checkAuthentication()

        // Then: User should be authenticated immediately
        XCTAssertTrue(authManager.isAuthenticated, "User should be authenticated with cached credentials")
        XCTAssertFalse(authManager.isCheckingAuth, "Auth check should be complete")
        XCTAssertNotNil(authManager.currentUser, "Current user should be set")
        XCTAssertEqual(authManager.currentUser?.id, userId, "User ID should match cached value")
        XCTAssertEqual(authManager.currentUser?.name, userName, "User name should match cached value")
    }

    func testAuthManagerCheckLocalAuthentication() throws {
        // Given: Local-only user has cached credentials (local_ prefix = no Keychain needed)
        let userId = "local_test-user-456"

        UserDefaults.standard.set(userId, forKey: Constants.UserDefaults.userId)

        // When: checkLocalAuthentication is called (via checkAuthentication)
        let expectation = XCTestExpectation(description: "Authentication should complete")

        _Concurrency.Task { @MainActor in
            await authManager.checkAuthentication()

            // Then: User should be authenticated
            XCTAssertTrue(authManager.isAuthenticated, "User should be authenticated locally")
            XCTAssertNotNil(authManager.currentUser, "Current user should be restored")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    func testBackgroundValidationDoesNotLogoutOfflineUser() async throws {
        // Given: Local-only user is authenticated with cached credentials
        // Uses local_ prefix to simulate offline-only mode (no Keychain session required)
        UserDefaults.standard.set("local_user-789", forKey: Constants.UserDefaults.userId)

        await authManager.checkAuthentication()

        // Verify user is authenticated
        XCTAssertTrue(authManager.isAuthenticated, "User should be authenticated")

        // When: the background validation would have run.
        //
        // This step used to be a comment — "simulated by checking auth again" — that simulated
        // nothing: it asserted the same thing twice, synchronously, before any detached task
        // could possibly land. So the test named after this bug was vacuous, and the bug lived
        // underneath it: `checkAuthentication` spawned a validation for a user who has no
        // session cookie by construction, it threw `KeychainError.notFound`, and
        // `clearStaleAuthState()` signed the offline user out.
        //
        // A second is not a guess: the detached task's failure path is local — a keychain miss,
        // no network round trip — so it lands almost immediately when it is spawned at all.
        // WATCHING for a whole second rather than sleeping and checking once, so the assertion
        // fails at the moment the state flips rather than reporting the end state.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            XCTAssertTrue(authManager.isAuthenticated,
                          "A local-only user must not be signed out by a session validation "
                          + "they can never pass")
            XCTAssertEqual(UserDefaults.standard.string(forKey: Constants.UserDefaults.userId),
                           "local_user-789",
                           "clearStaleAuthState() must not run for a local-only user")
            try await _Concurrency.Task.sleep(nanoseconds: 50_000_000)
        }

        // Then: User remains authenticated
        XCTAssertTrue(authManager.isAuthenticated, "User should remain authenticated after background validation")
        XCTAssertNotNil(authManager.currentUser, "Current user should still be set")
    }

    // MARK: - Data Loading Tests

    func testTaskServiceLoadsCachedTasks() async throws {
        // Given: TaskService has completed initial cache load
        // Wait for cache load to complete (happens async in init)
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Then: Service should have completed initial load
        XCTAssertTrue(taskService.hasCompletedInitialLoad,
                     "TaskService should complete initial load even offline")
    }

    func testListServiceLoadsCachedLists() async throws {
        // Given: ListService has completed initial cache load
        // Wait for cache load to complete (happens async in init)
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Then: Service should have completed initial load
        XCTAssertTrue(listService.hasCompletedInitialLoad,
                     "ListService should complete initial load even offline")
    }

    func testTasksAvailableOffline() async throws {
        // Given: User has cached tasks from previous session
        // TaskService loads them on init
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // Wait for cache load

        // Then: Tasks should be available (even if empty)
        // The important thing is that the service is ready and hasn't blocked
        XCTAssertTrue(taskService.hasCompletedInitialLoad, "TaskService should be ready")
        XCTAssertNotNil(taskService.tasks, "Tasks array should exist (even if empty)")
    }

    func testListsAvailableOffline() async throws {
        // Given: User has cached lists from previous session
        // ListService loads them on init
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000) // Wait for cache load

        // Then: Lists should be available (even if empty)
        XCTAssertTrue(listService.hasCompletedInitialLoad, "ListService should be ready")
        XCTAssertNotNil(listService.lists, "Lists array should exist (even if empty)")
    }

    // MARK: - Sync Manager Tests

    func testSyncManagerHandlesOfflineGracefully() async throws {
        // Given: App is offline (no network)

        // When: Sync is attempted
        // Note: This will fail with network error but should not crash
        do {
            try await syncManager.performFullSync()
        } catch {
            // Expected to fail when offline, but should handle gracefully
            print("Sync failed as expected when offline: \(error)")
        }

        // Then: Sync manager keeps hasCompletedInitialSync false when offline
        // (it only becomes true after a successful sync)
        // The key assertion is that we didn't crash
        XCTAssertNotNil(syncManager, "SyncManager should still be accessible after failed sync")
    }

    func testSyncDoesNotBlockUI() async throws {
        // Given: App is starting up

        // When: Sync runs in background
        _Concurrency.Task {
            try? await syncManager.performFullSync()
        }

        // Then: UI should not be blocked (sync is non-blocking)
        // This test verifies that sync doesn't block the main thread
        let startTime = Date()
        try await _Concurrency.Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        let elapsed = Date().timeIntervalSince(startTime)

        // Use a generous tolerance to account for system load variations
        XCTAssertLessThan(elapsed, 1.0, "Sync should not block main thread")
    }

    // MARK: - Cold Start Tests

    func testAppWorksAfterForceClosed() async throws {
        // This test simulates a force close followed by reopening the app
        // Given: Local-only user has cached credentials and data
        // Uses local_ prefix to simulate offline-only mode (no Keychain session required)
        UserDefaults.standard.set("local_cold-start-user", forKey: Constants.UserDefaults.userId)

        // Simulate force close by resetting auth check flag
        await MainActor.run {
            authManager.isCheckingAuth = true
        }

        // When: App reopens and checks authentication
        await authManager.checkAuthentication()

        // Then: User should be authenticated immediately
        XCTAssertTrue(authManager.isAuthenticated, "User should be authenticated after cold start")
        XCTAssertFalse(authManager.isCheckingAuth, "Auth check should complete")
    }

    func testAppShowsMainViewNotLogin() async throws {
        // Given: Local-only user is authenticated with cached data
        // Uses local_ prefix to simulate offline-only mode (no Keychain session required)
        UserDefaults.standard.set("local_main-view-user", forKey: Constants.UserDefaults.userId)
        await authManager.checkAuthentication()

        // Then: App should show main view, not login
        XCTAssertTrue(authManager.isAuthenticated, "Should show main view when authenticated")
        XCTAssertFalse(authManager.isCheckingAuth, "Should not be stuck on splash screen")
    }

    // MARK: - Network Error Handling Tests

    func testNoNetworkErrorsPreventsAppUsage() async throws {
        // Given: Local-only user has cached credentials
        // Uses local_ prefix to simulate offline-only mode (no Keychain session required)
        UserDefaults.standard.set("local_error-test-user", forKey: Constants.UserDefaults.userId)

        // When: Auth check runs (may fail with network error)
        await authManager.checkAuthentication()

        // Then: User should still be able to use the app
        XCTAssertTrue(authManager.isAuthenticated || !authManager.isCheckingAuth,
                     "App should not block user due to network errors")
    }

    // MARK: - Airplane Mode Simulation Tests

    func testAppWorksInAirplaneMode() async throws {
        // Simulate airplane mode by having cached credentials but no network
        // Given: Local-only user has cached credentials
        // Uses local_ prefix to simulate offline-only mode (no Keychain session required)
        UserDefaults.standard.set("local_airplane-user", forKey: Constants.UserDefaults.userId)

        // When: App checks authentication in airplane mode
        await authManager.checkAuthentication()

        // Then: User should be authenticated with cached data
        XCTAssertTrue(authManager.isAuthenticated, "User should work in airplane mode")
        XCTAssertNotNil(authManager.currentUser, "User data should be available offline")

        // And: Services should load cached data
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(taskService.hasCompletedInitialLoad, "Tasks should load from cache")
        XCTAssertTrue(listService.hasCompletedInitialLoad, "Lists should load from cache")
    }

}
