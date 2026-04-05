import Foundation
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager(apiClient: APIClient.shared, keychainService: .shared)

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isCheckingAuth = true  // Track initial auth check for splash screen

    private let apiClient: APIClientProtocol
    private let keychainService: KeychainService

    init(apiClient: APIClientProtocol, keychainService: KeychainService) {
        self.apiClient = apiClient
        self.keychainService = keychainService
    }
    
    // MARK: - Authentication Check

    /// Check if user is authenticated locally (offline-first)
    /// Returns true if user has local auth state, false otherwise
    private func checkLocalAuthentication() -> Bool {
        // Check UserDefaults for cached user ID
        guard let userId = UserDefaults.standard.string(forKey: Constants.UserDefaults.userId),
              !userId.isEmpty else {
            return false
        }

        // Local-only users (offline mode) don't need a session cookie
        let isLocalUser = userId.hasPrefix("local_")

        // For server-authenticated users, verify session cookie still exists in Keychain
        // This prevents showing authenticated state when Keychain was cleared but UserDefaults wasn't
        if !isLocalUser {
            do {
                _ = try keychainService.getSessionCookie()
            } catch {
                print("⚠️ [AuthManager] UserId found in UserDefaults but no session cookie in Keychain - clearing stale auth state")
                // Clear stale UserDefaults data to prevent future mismatches
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userId)
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userEmail)
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userName)
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userImage)
                return false
            }
        }

        print("✅ [AuthManager] Found local auth state for user: \(userId)")

        // Restore user from UserDefaults
        let email = UserDefaults.standard.string(forKey: Constants.UserDefaults.userEmail)
        let name = UserDefaults.standard.string(forKey: Constants.UserDefaults.userName)
        let image = UserDefaults.standard.string(forKey: Constants.UserDefaults.userImage)

        self.currentUser = User(
            id: userId,
            email: email,
            name: name,
            image: image
        )

        return true
    }

    func checkAuthentication() async {
        print("🔐 [AuthManager] Checking authentication...")

        // OFFLINE FIRST: Check local auth state immediately
        let hasLocalAuth = checkLocalAuthentication()

        if hasLocalAuth {
            // User has local auth - set authenticated immediately
            self.isAuthenticated = true
            print("⚡ [AuthManager] User authenticated offline - will validate in background")

            // Mark auth check as complete immediately (don't block UI)
            self.isCheckingAuth = false

            // Validate session with backend in background (non-blocking, network-aware)
            _Concurrency.Task.detached { [weak self] in
                await self?.validateSessionInBackground()
            }
        } else {
            // No local auth - try to check with server (but don't require network)
            defer {
                // Mark auth check as complete (for splash screen)
                self.isCheckingAuth = false
            }

            do {
                // Try to get session cookie
                _ = try keychainService.getSessionCookie()
                print("🔑 [AuthManager] Session cookie found")

                // Validate session with backend
                let response: SessionResponse = try await apiClient.request(.session)
                self.currentUser = response.user

                print("✅ [AuthManager] Authentication successful - User: \(response.user.email ?? "unknown")")

                // Save user to UserDefaults for quick access
                UserDefaults.standard.set(response.user.id, forKey: Constants.UserDefaults.userId)
                UserDefaults.standard.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
                if let name = response.user.name {
                    UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
                }
                if let image = response.user.image {
                    UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
                }

                // Set authenticated (session-based auth, no token needed)
                self.isAuthenticated = true

            } catch {
                // Only log if it's not a "no session" error (which is expected on first launch)
                if case KeychainError.notFound = error {
                    print("ℹ️ [AuthManager] No session cookie found (expected on first launch)")
                } else {
                    print("❌ [AuthManager] Session validation failed (offline or network error): \(error)")
                    print("⚠️ [AuthManager] If user has cached data, they can still use the app offline")
                }
                self.isAuthenticated = false
                self.currentUser = nil
            }
        }
    }

    /// Validate session with backend in background (non-blocking)
    /// If validation fails due to network issues, keep user authenticated (offline mode)
    /// If session is explicitly rejected (401), log out the user
    private func validateSessionInBackground() async {
        // Check network availability before attempting validation
        // This avoids unnecessary error logs when offline
        guard NetworkMonitor.shared.isConnected else {
            print("ℹ️ [AuthManager] Skipping background session validation - no network connection")
            print("✅ [AuthManager] User remains authenticated with cached credentials (offline mode)")
            return
        }

        do {
            // Try to get session cookie
            _ = try keychainService.getSessionCookie()

            // Validate session with backend
            let response: SessionResponse = try await apiClient.request(.session)

            await MainActor.run {
                self.currentUser = response.user
                print("✅ [AuthManager] Background session validation successful")

                // Update UserDefaults with latest user info
                UserDefaults.standard.set(response.user.id, forKey: Constants.UserDefaults.userId)
                UserDefaults.standard.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
                if let name = response.user.name {
                    UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
                }
                if let image = response.user.image {
                    UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
                }
            }
        } catch KeychainError.notFound {
            // No session cookie - this is a critical mismatch, clear auth state
            print("⚠️ [AuthManager] Background validation failed: no session cookie in Keychain")
            await MainActor.run {
                self.clearStaleAuthState()
            }
        } catch let error as APIError {
            // Check if this is an explicit session rejection (401 Unauthorized)
            if case .httpError(let statusCode, _) = error, statusCode == 401 {
                print("🔒 [AuthManager] Session rejected by server (401) - logging out user")
                await MainActor.run {
                    self.clearStaleAuthState()
                }
            } else {
                // Network or other transient error - keep user authenticated
                print("⚠️ [AuthManager] Background session validation failed (keeping offline mode): \(error)")
            }
        } catch {
            // Other errors (network issues, etc.) - keep user authenticated for offline access
            print("⚠️ [AuthManager] Background session validation failed (offline mode): \(error)")
        }
    }

    /// Clear stale authentication state when session is invalid
    /// This is a lighter cleanup than full signOut - just clears auth state without API calls
    private func clearStaleAuthState() {
        print("🧹 [AuthManager] Clearing stale auth state...")

        // Clear Keychain
        try? keychainService.deleteSessionCookie()

        // Clear UserDefaults user data
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userEmail)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userName)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userImage)

        // Reset auth state
        self.isAuthenticated = false
        self.currentUser = nil

        print("✅ [AuthManager] Stale auth state cleared - user will see login screen")
    }
    
    // MARK: - Passwordless Sign Up

    /// Create account with just email - no password needed (passkeys/OAuth)
    func signUpPasswordless(email: String, name: String?) async throws {
        print("📧 [AuthManager] Creating passwordless account: \(email)")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Call signup without password - this creates a session and returns the user
            let response: SessionResponse = try await apiClient.request(.signUpPasswordless(email: email, name: name))

            self.currentUser = response.user

            print("✅ [AuthManager] Passwordless sign-up successful")

            // Save user info
            UserDefaults.standard.set(response.user.id, forKey: Constants.UserDefaults.userId)
            UserDefaults.standard.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = response.user.name {
                UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = response.user.image {
                UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: response.user.id)

        } catch let error as APIError {
            print("❌ [AuthManager] Passwordless sign-up failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            print("❌ [AuthManager] Passwordless sign-up failed: \(error)")
            self.errorMessage = "An unexpected error occurred"
            throw error
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple() async throws {
        print("🍎 [AuthManager] Starting Apple sign-in...")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Get Apple credentials
            print("🍎 [AuthManager] Requesting Apple credentials...")
            let appleResult = try await AppleSignInManager.shared.signIn()
            print("🍎 [AuthManager] Got Apple credentials, sending to backend...")

            // Convert PersonNameComponents to String
            let fullNameString = appleResult.fullName.map {
                "\($0.givenName ?? "") \($0.familyName ?? "")".trimmingCharacters(in: .whitespaces)
            }

            // Send to backend for validation and session creation
            let response: SessionResponse = try await apiClient.request(.signInWithApple(
                identityToken: appleResult.identityToken,
                authorizationCode: appleResult.authorizationCode,
                user: appleResult.user,
                email: appleResult.email,
                fullName: fullNameString
            ))

            self.currentUser = response.user

            print("✅ [AuthManager] Apple sign-in successful - User: \(response.user.email ?? "unknown")")

            // Save user info
            UserDefaults.standard.set(response.user.id, forKey: Constants.UserDefaults.userId)
            UserDefaults.standard.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = response.user.name {
                UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = response.user.image {
                UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: response.user.id)

        } catch let error as APIError {
            print("❌ [AuthManager] Apple sign-in failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            print("❌ [AuthManager] Apple sign-in failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In with Google

    func signInWithGoogle() async throws {
        print("🔵 [AuthManager] Starting Google sign-in...")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Get Google credentials
            print("🔵 [AuthManager] Requesting Google credentials...")
            let googleResult = try await GoogleSignInManager.shared.signIn()
            print("🔵 [AuthManager] Got Google credentials, sending to backend...")

            // Send to backend for validation and session creation
            let response: SessionResponse = try await apiClient.request(.signInWithGoogle(
                idToken: googleResult.idToken
            ))

            self.currentUser = response.user

            print("✅ [AuthManager] Google sign-in successful - User: \(response.user.email ?? "unknown")")

            // Save user info
            UserDefaults.standard.set(response.user.id, forKey: Constants.UserDefaults.userId)
            UserDefaults.standard.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = response.user.name {
                UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = response.user.image {
                UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: response.user.id)

        } catch let error as APIError {
            print("❌ [AuthManager] Google sign-in failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            print("❌ [AuthManager] Google sign-in failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In with Passkey

    func signInWithPasskey(email: String? = nil) async throws {
        print("🔑 [AuthManager] Starting Passkey sign-in...")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Authenticate with passkey
            let userResponse = try await PasskeyManager.shared.authenticate(email: email)

            // Convert PasskeyManager.UserResponse to User
            let user = User(
                id: userResponse.id,
                email: userResponse.email,
                name: userResponse.name,
                image: userResponse.image
            )

            self.currentUser = user

            print("✅ [AuthManager] Passkey sign-in successful - User: \(user.email ?? "unknown")")

            // Save user info
            UserDefaults.standard.set(user.id, forKey: Constants.UserDefaults.userId)
            UserDefaults.standard.set(user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = user.name {
                UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = user.image {
                UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: user.id)

        } catch let error as PasskeyError {
            // Don't show error for user cancellation
            if case .userCancelled = error {
                print("ℹ️ [AuthManager] Passkey sign-in cancelled by user")
                throw error
            }
            print("❌ [AuthManager] Passkey sign-in failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            print("❌ [AuthManager] Passkey sign-in failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Up with Passkey

    func signUpWithPasskey(email: String) async throws {
        print("🔑 [AuthManager] Starting Passkey sign-up for: \(email)")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Register new account with passkey
            let (verified, userResponse) = try await PasskeyManager.shared.register(email: email)

            guard verified, let userResponse = userResponse else {
                throw PasskeyError.registrationFailed("Account creation failed")
            }

            // Convert PasskeyManager.UserResponse to User
            let user = User(
                id: userResponse.id,
                email: userResponse.email,
                name: userResponse.name,
                image: userResponse.image
            )

            self.currentUser = user

            print("✅ [AuthManager] Passkey sign-up successful - User: \(user.email ?? "unknown")")

            // Save user info
            UserDefaults.standard.set(user.id, forKey: Constants.UserDefaults.userId)
            UserDefaults.standard.set(user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = user.name {
                UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = user.image {
                UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: user.id)

        } catch let error as PasskeyError {
            // Don't show error for user cancellation
            if case .userCancelled = error {
                print("ℹ️ [AuthManager] Passkey sign-up cancelled by user")
                throw error
            }
            print("❌ [AuthManager] Passkey sign-up failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            print("❌ [AuthManager] Passkey sign-up failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Out

    func signOut() async throws {
        isLoading = true
        defer { isLoading = false }

        print("🚪 [AuthManager] Starting sign-out - clearing ALL user data...")

        // Disconnect SSE first to stop receiving updates
        await SSEClient.shared.disconnect()

        do {
            // Call sign out endpoint
            let _: EmptyResponse = try await apiClient.request(.signOut)
        } catch {
            print("Sign out API call failed: \(error)")
            // Continue with local cleanup even if API call fails
        }

        // ===== KEYCHAIN CLEANUP =====
        // Clear ALL keychain items to prevent credential leakage
        try? keychainService.deleteSessionCookie()
        keychainService.deleteMCPToken()
        keychainService.deleteOAuthClientSecret()

        // ===== HTTP COOKIE STORAGE CLEANUP =====
        // CRITICAL: Clear URLSession's cookie storage to prevent session leakage
        // This is essential for user data isolation - cached cookies can leak between users
        if let apiURL = URL(string: Constants.API.baseURL) {
            if let cookies = HTTPCookieStorage.shared.cookies(for: apiURL) {
                print("🍪 [AuthManager] Clearing \(cookies.count) cached cookies for \(apiURL.host ?? "unknown")...")
                for cookie in cookies {
                    HTTPCookieStorage.shared.deleteCookie(cookie)
                }
            }
        }
        // Also clear all cookies for the domain (covers subdomains too)
        if let allCookies = HTTPCookieStorage.shared.cookies {
            let astridCookies = allCookies.filter { $0.domain.contains("astrid") }
            print("🍪 [AuthManager] Clearing \(astridCookies.count) Astrid domain cookies...")
            for cookie in astridCookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }

        // ===== USERDEFAULTS - USER DATA =====
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userId)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userEmail)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userName)
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userImage)

        // ===== USERDEFAULTS - REMINDER SETTINGS =====
        // Clear all notification/reminder preferences (user-specific)
        UserDefaults.standard.removeObject(forKey: "reminderPushEnabled")
        UserDefaults.standard.removeObject(forKey: "reminderEmailEnabled")
        UserDefaults.standard.removeObject(forKey: "defaultReminderOffset")
        UserDefaults.standard.removeObject(forKey: "dailyDigestEnabled")
        UserDefaults.standard.removeObject(forKey: "dailyDigestTime")
        UserDefaults.standard.removeObject(forKey: "reminderTimezone")
        UserDefaults.standard.removeObject(forKey: "quietHoursEnabled")
        UserDefaults.standard.removeObject(forKey: "quietHoursStart")
        UserDefaults.standard.removeObject(forKey: "quietHoursEnd")
        UserDefaults.standard.removeObject(forKey: "reminderSettingsPending")

        // ===== USERDEFAULTS - OTHER USER DATA =====
        UserDefaults.standard.removeObject(forKey: "GoogleOAuthCodeVerifier")
        UserDefaults.standard.removeObject(forKey: "pendingAttachments")
        UserDefaults.standard.removeObject(forKey: "oauth_token_cache")

        // ===== CORE DATA =====
        print("🗑️ [AuthManager] Clearing Core Data...")
        do {
            try CoreDataManager.shared.clearAll()
            print("✅ [AuthManager] Core Data cleared successfully")
        } catch {
            print("❌ [AuthManager] Failed to clear Core Data: \(error)")
            // Continue with logout even if Core Data clear fails
        }

        // ===== SERVICE CLEANUP =====
        // Clear sync manager state (all sync timestamps)
        SyncManager.shared.resetSyncState()

        // Clear in-memory task and list caches
        TaskService.shared.clearCache()
        ListService.shared.clearCache()

        // Clear Apple Reminders integration data
        AppleRemindersService.shared.clearAllData()

        // Clear user preferences and settings
        MyTasksPreferencesService.shared.clearData()
        UserSettingsService.shared.clearData()

        // ===== CACHE CLEANUP =====
        // Clear all user-related caches to prevent data leakage between users
        UserImageCache.shared.clearCache()
        ProfileCache.shared.clearAllCache()
        ImageCache.shared.clearCache()
        AIAgentCache.shared.clear()

        print("✅ [AuthManager] All user data cleared successfully")

        self.isAuthenticated = false
        self.currentUser = nil
    }
    
    // MARK: - Update Current User

    func updateCurrentUser(_ user: User) {
        print("👤 [AuthManager] Updating current user")
        self.currentUser = user

        // Update UserDefaults
        UserDefaults.standard.set(user.id, forKey: Constants.UserDefaults.userId)
        UserDefaults.standard.set(user.email, forKey: Constants.UserDefaults.userEmail)
        if let name = user.name {
            UserDefaults.standard.set(name, forKey: Constants.UserDefaults.userName)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userName)
        }
        if let image = user.image {
            UserDefaults.standard.set(image, forKey: Constants.UserDefaults.userImage)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaults.userImage)
        }

        print("✅ [AuthManager] Current user updated")
    }

    // MARK: - Helpers

    var userId: String? {
        currentUser?.id ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userId)
    }

    var userEmail: String? {
        currentUser?.email ?? UserDefaults.standard.string(forKey: Constants.UserDefaults.userEmail)
    }
}
