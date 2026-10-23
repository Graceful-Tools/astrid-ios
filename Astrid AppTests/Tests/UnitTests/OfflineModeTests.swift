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
}
