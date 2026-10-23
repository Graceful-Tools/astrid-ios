import AstridCore
import Foundation
import AuthenticationServices
import Combine

@MainActor
class AuthManager: ObservableObject {
    static let shared = AuthManager(apiClient: .shared, keychainService: .shared)

    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isCheckingAuth = true  // Track initial auth check for splash screen

    private let apiClient: AstridAPIClient
    private let keychainService: KeychainService
    private let defaults: UserDefaults
    private let cookieStorage: HTTPCookieStorage
    private let journalFileURL: URL?
    private let isConnected: @MainActor () -> Bool
    private let coreSession: (@MainActor () -> CoreSession)?

    /// Everything past `keychainService` defaults to the app's own state, so `shared` behaves as
    /// it always did. A test hands in a scratch keychain service, defaults suite, cookie jar,
    /// journal file and in-memory core, and can run `signOut` end to end without wiping the host
    /// app's session (AITD-535).
    init(apiClient: AstridAPIClient, keychainService: KeychainService,
         defaults: UserDefaults = .standard,
         cookieStorage: HTTPCookieStorage = .shared,
         journalFileURL: URL? = nil,
         isConnected: @escaping @MainActor () -> Bool = { NetworkMonitor.shared.isConnected },
         core: (@MainActor () -> CoreSession)? = nil) {
        self.apiClient = apiClient
        self.keychainService = keychainService
        self.defaults = defaults
        self.cookieStorage = cookieStorage
        self.journalFileURL = journalFileURL
        self.isConnected = isConnected
        self.coreSession = core
    }

    private var core: CoreSession { coreSession?() ?? AppCore.shared.session }
    
    // MARK: - Authentication Check

    /// Check if user is authenticated locally (offline-first)
    /// Returns true if user has local auth state, false otherwise
    /// The prefix a local-only (offline) user's id carries. They never have a session cookie.
    nonisolated static let localUserIdPrefix = "local_"

    /// Whether the cached user is worth validating against the server in the background.
    ///
    /// NO for a local-only user, and that is the bug this answers (found via the flaky
    /// `OfflineModeTests.testAppWorksAfterForceClosed`, tasks e12b5390 / 91a7e180).
    /// `checkAuthentication` treats a cached `local_` user as authenticated immediately — the
    /// whole OFFLINE FIRST design — and then kicked off a background validation. A local-only
    /// user has no session cookie by construction, so that task threw `KeychainError.notFound`
    /// and called `clearStaleAuthState()`, wiping the auth state the line above had just
    /// established.
    ///
    /// For a person that means an offline-only account is signed out the moment the device has
    /// network. In the test suite it meant one test's detached task landed inside the NEXT test
    /// and cleared the id it had just written — a flake that only appeared under load.
    ///
    /// A server user is still validated. This narrows the check; it does not remove it, because
    /// a stale cookie must still sign someone out.
    /// `nonisolated` because it is a pure question about a string — no actor state is read —
    /// and a test should not have to hop to the main actor to ask it.
    nonisolated static func shouldValidateSessionInBackground(userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        return !userId.hasPrefix(localUserIdPrefix)
    }

    private func checkLocalAuthentication() -> Bool {
        // Check UserDefaults for cached user ID
        guard let userId = defaults.string(forKey: Constants.UserDefaults.userId),
              !userId.isEmpty else {
            return false
        }

        // Local-only users (offline mode) don't need a session cookie
        let isLocalUser = userId.hasPrefix(Self.localUserIdPrefix)

        // For server-authenticated users, verify session cookie still exists in Keychain
        // This prevents showing authenticated state when Keychain was cleared but UserDefaults wasn't
        if !isLocalUser {
            do {
                _ = try keychainService.getSessionCookie()
            } catch {
                AppLog.debug("⚠️ [AuthManager] UserId found in UserDefaults but no session cookie in Keychain - clearing stale auth state")
                // Clear stale UserDefaults data to prevent future mismatches
                defaults.removeObject(forKey: Constants.UserDefaults.userId)
                defaults.removeObject(forKey: Constants.UserDefaults.userEmail)
                defaults.removeObject(forKey: Constants.UserDefaults.userName)
                defaults.removeObject(forKey: Constants.UserDefaults.userImage)
                return false
            }
        }

        PrivacyLogger.debug("AuthManager", "local_auth_state=found")

        // Restore user from UserDefaults
        let email = defaults.string(forKey: Constants.UserDefaults.userEmail)
        let name = defaults.string(forKey: Constants.UserDefaults.userName)
        let image = defaults.string(forKey: Constants.UserDefaults.userImage)

        let restoredUser = User(
            id: userId,
            email: email,
            name: name,
            image: image
        )
        self.currentUser = restoredUser

        // A cached task restored from Core Data may carry only `assigneeId`. Restore the current
        // user's URL lookup from the session and promote warm disk bytes to memory before My Tasks
        // renders, so their photo is available on the first row frame (AITD-283).
        UserImageCache.shared.prepareForLaunch(restoredUser)

        return true
    }

    func checkAuthentication() async {
        AppLog.debug("🔐 [AuthManager] Checking authentication...")

        // OFFLINE FIRST: Check local auth state immediately
        let hasLocalAuth = checkLocalAuthentication()

        if hasLocalAuth {
            // User has local auth - set authenticated immediately
            self.isAuthenticated = true
            AppLog.debug("⚡ [AuthManager] User authenticated offline - will validate in background")

            // Mark auth check as complete immediately (don't block UI)
            self.isCheckingAuth = false

            // Validate session with backend in background (non-blocking, network-aware) —
            // but NOT for a local-only user, who has no session to validate and would be
            // signed out by the attempt. See `shouldValidateSessionInBackground`.
            if Self.shouldValidateSessionInBackground(
                userId: defaults.string(forKey: Constants.UserDefaults.userId)) {
                _Concurrency.Task.detached { [weak self] in
                    await self?.validateSessionInBackground()
                }
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
                AppLog.debug("🔑 [AuthManager] Session cookie found")

                // Validate session with backend
                let response: SessionResponse = try await apiClient.getSession()
                persistRenewedSession(response)
                self.currentUser = response.user

                PrivacyLogger.debug("AuthManager", "session_validation=success")

                // Save user to UserDefaults for quick access
                defaults.set(response.user.id, forKey: Constants.UserDefaults.userId)
                defaults.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
                if let name = response.user.name {
                    defaults.set(name, forKey: Constants.UserDefaults.userName)
                }
                if let image = response.user.image {
                    defaults.set(image, forKey: Constants.UserDefaults.userImage)
                }

                // Set authenticated (session-based auth, no token needed)
                self.isAuthenticated = true

            } catch {
                // Only log if it's not a "no session" error (which is expected on first launch)
                if case KeychainError.notFound = error {
                    AppLog.debug("ℹ️ [AuthManager] No session cookie found (expected on first launch)")
                } else {
                    AppLog.debug("❌ [AuthManager] Session validation failed (offline or network error): \(error)")
                    AppLog.debug("⚠️ [AuthManager] If user has cached data, they can still use the app offline")
                }
                self.isAuthenticated = false
                self.currentUser = nil
            }
        }
    }

    /// Validate session with backend in background (non-blocking)
    /// If validation fails due to network issues, keep user authenticated (offline mode)
    /// If session is explicitly rejected (401), log out the user
    func validateSessionInBackground() async {
        // Check network availability before attempting validation
        // This avoids unnecessary error logs when offline
        guard isConnected() else {
            AppLog.debug("ℹ️ [AuthManager] Skipping background session validation - no network connection")
            AppLog.debug("✅ [AuthManager] User remains authenticated with cached credentials (offline mode)")
            return
        }

        do {
            // Try to get session cookie
            _ = try keychainService.getSessionCookie()

            // Validate session with backend
            let response: SessionResponse = try await apiClient.getSession()
            persistRenewedSession(response)

            await MainActor.run {
                self.currentUser = response.user
                AppLog.debug("✅ [AuthManager] Background session validation successful")

                // Update UserDefaults with latest user info
                defaults.set(response.user.id, forKey: Constants.UserDefaults.userId)
                defaults.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
                if let name = response.user.name {
                    defaults.set(name, forKey: Constants.UserDefaults.userName)
                }
                if let image = response.user.image {
                    defaults.set(image, forKey: Constants.UserDefaults.userImage)
                }
            }
        } catch KeychainError.notFound {
            // No session cookie - this is a critical mismatch, clear auth state
            AppLog.debug("⚠️ [AuthManager] Background validation failed: no session cookie in Keychain")
            await MainActor.run {
                self.clearStaleAuthState()
            }
        } catch let error as AstridAPIError {
            // Check if this is an explicit session rejection (401 Unauthorized)
            if error.httpStatusCode == 401 {
                AppLog.debug("🔒 [AuthManager] Session rejected by server (401) - logging out user")
                await MainActor.run {
                    self.clearStaleAuthState()
                }
            } else {
                // Network or other transient error - keep user authenticated
                AppLog.debug("⚠️ [AuthManager] Background session validation failed (keeping offline mode): \(error)")
            }
        } catch {
            // Other errors (network issues, etc.) - keep user authenticated for offline access
            AppLog.debug("⚠️ [AuthManager] Background session validation failed (offline mode): \(error)")
        }
    }

    /// Clear stale authentication state when session is invalid
    /// This is a lighter cleanup than full signOut - just clears auth state without API calls
    private func clearStaleAuthState() {
        AppLog.debug("🧹 [AuthManager] Clearing stale auth state...")

        // Clear Keychain
        try? keychainService.deleteSessionCookie()

        // Clear UserDefaults user data
        defaults.removeObject(forKey: Constants.UserDefaults.userId)
        defaults.removeObject(forKey: Constants.UserDefaults.userEmail)
        defaults.removeObject(forKey: Constants.UserDefaults.userName)
        defaults.removeObject(forKey: Constants.UserDefaults.userImage)

        // Reset auth state
        self.isAuthenticated = false
        self.currentUser = nil

        AppLog.debug("✅ [AuthManager] Stale auth state cleared - user will see login screen")
    }
    
    // MARK: - Passwordless Sign Up

    /// Create account with just email - no password needed (passkeys/OAuth)
    func signUpPasswordless(email: String, name: String?) async throws {
        PrivacyLogger.debug("AuthManager", "passwordless_sign_up=started")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Call signup without password - this creates a session and returns the user
            let response: SessionResponse = try await apiClient.signUpPasswordless(email: email, name: name)

            self.currentUser = response.user

            AppLog.debug("✅ [AuthManager] Passwordless sign-up successful")

            // Save user info
            defaults.set(response.user.id, forKey: Constants.UserDefaults.userId)
            defaults.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = response.user.name {
                defaults.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = response.user.image {
                defaults.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: response.user.id)

        } catch let error as AstridAPIError {
            AppLog.debug("❌ [AuthManager] Passwordless sign-up failed: \(error.localizedDescription)")
            self.errorMessage = error.serverMessage ?? error.localizedDescription
            throw error
        } catch {
            AppLog.debug("❌ [AuthManager] Passwordless sign-up failed: \(error)")
            self.errorMessage = "An unexpected error occurred"
            throw error
        }
    }

    // MARK: - Sign In with Apple

    func signInWithApple() async throws {
        AppLog.debug("🍎 [AuthManager] Starting Apple sign-in...")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Get Apple credentials
            AppLog.debug("🍎 [AuthManager] Requesting Apple credentials...")
            let appleResult = try await AppleSignInManager.shared.signIn()
            AppLog.debug("🍎 [AuthManager] Got Apple credentials, sending to backend...")

            // Convert PersonNameComponents to String
            let fullNameString = appleResult.fullName.map {
                "\($0.givenName ?? "") \($0.familyName ?? "")".trimmingCharacters(in: .whitespaces)
            }

            // Send to backend for validation and session creation
            let response: SessionResponse = try await apiClient.signInWithApple(AppleSignInRequest(
                identityToken: appleResult.identityToken,
                authorizationCode: appleResult.authorizationCode,
                user: appleResult.user,
                email: appleResult.email,
                fullName: fullNameString
            ))

            self.currentUser = response.user

            PrivacyLogger.debug("AuthManager", "apple_sign_in=success")

            // Save user info
            defaults.set(response.user.id, forKey: Constants.UserDefaults.userId)
            defaults.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = response.user.name {
                defaults.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = response.user.image {
                defaults.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: response.user.id)

        } catch let error as AstridAPIError {
            AppLog.debug("❌ [AuthManager] Apple sign-in failed: \(error.localizedDescription)")
            self.errorMessage = error.serverMessage ?? error.localizedDescription
            throw error
        } catch {
            AppLog.debug("❌ [AuthManager] Apple sign-in failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In with Google

    func signInWithGoogle() async throws {
        AppLog.debug("🔵 [AuthManager] Starting Google sign-in...")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Get Google credentials
            AppLog.debug("🔵 [AuthManager] Requesting Google credentials...")
            let googleResult = try await GoogleSignInManager.shared.signIn()
            AppLog.debug("🔵 [AuthManager] Got Google credentials, sending to backend...")

            // Send to backend for validation and session creation
            let response: SessionResponse = try await apiClient.signInWithGoogle(idToken: googleResult.idToken)

            self.currentUser = response.user

            PrivacyLogger.debug("AuthManager", "google_sign_in=success")

            // Save user info
            defaults.set(response.user.id, forKey: Constants.UserDefaults.userId)
            defaults.set(response.user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = response.user.name {
                defaults.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = response.user.image {
                defaults.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: response.user.id)

        } catch let error as AstridAPIError {
            AppLog.debug("❌ [AuthManager] Google sign-in failed: \(error.localizedDescription)")
            self.errorMessage = error.serverMessage ?? error.localizedDescription
            throw error
        } catch {
            AppLog.debug("❌ [AuthManager] Google sign-in failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In with Passkey

    /// - Parameter presentation: `.localOnly` asks for passkeys on this device only (no nearby-device
    ///   QR) and throws `PasskeyError.noLocalPasskey` when there are none; `.fullSheet` is the
    ///   complete system flow. See `PasskeySignInPlan` (AITD-298).
    func signInWithPasskey(email: String? = nil, presentation: PasskeyPresentation = .fullSheet) async throws {
        AppLog.debug("🔑 [AuthManager] Starting Passkey sign-in...")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            // Authenticate with passkey
            let userResponse = try await PasskeyManager.shared.authenticate(email: email, presentation: presentation)

            // Convert PasskeyManager.UserResponse to User
            let user = User(
                id: userResponse.id,
                email: userResponse.email,
                name: userResponse.name,
                image: userResponse.image
            )

            self.currentUser = user

            PrivacyLogger.debug("AuthManager", "passkey_sign_in=success")

            // Save user info
            defaults.set(user.id, forKey: Constants.UserDefaults.userId)
            defaults.set(user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = user.name {
                defaults.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = user.image {
                defaults.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: user.id)

        } catch let error as PasskeyError {
            // Don't show error for user cancellation
            if case .userCancelled = error {
                AppLog.debug("ℹ️ [AuthManager] Passkey sign-in cancelled by user")
                throw error
            }
            // Nothing local answered a local-only request: the caller offers the alternatives,
            // so this is not an error banner either (AITD-298).
            if case .noLocalPasskey = error {
                AppLog.debug("ℹ️ [AuthManager] No local passkey for a local-only sign-in")
                throw error
            }
            AppLog.debug("❌ [AuthManager] Passkey sign-in failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            AppLog.debug("❌ [AuthManager] Passkey sign-in failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign In through the browser (GitHub, SSO)

    /// GitHub and SSO sign-in via the desktop hand-off (AITD-465, spec §6.5): the deployment's own
    /// sign-in page runs in an ASWebAuthenticationSession, hands back a one-time code, and the code
    /// plus this attempt's PKCE verifier is exchanged for a session. No provider SDK in the app.
    func signInWithBrowser(provider: SignInProvider) async throws {
        PrivacyLogger.debug("AuthManager", "browser_sign_in=started")
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            let attempt = DesktopHandoff.Attempt.start()
            guard let baseURL = URL(string: Constants.API.baseURL),
                  let url = DesktopHandoff.startURL(baseURL: baseURL, provider: provider, attempt: attempt) else {
                throw DesktopHandoff.HandoffError.unexpectedCallback
            }
            let callback = try await OAuthWebConnector.shared.present(url: url, callbackScheme: DesktopHandoff.callbackScheme)
            let code = try DesktopHandoff.code(from: callback, expectedState: attempt.state)

            let response = try await AstridAPIClient.shared.exchangeDesktopCode(DesktopExchangeRequest(
                code: code, codeVerifier: attempt.verifier, client: DesktopHandoff.clientId))
            try keychainService.saveSessionCookie(
                DesktopHandoff.cookieHeader(token: response.sessionToken, cookieName: response.sessionCookieName))

            let user = response.user
            self.currentUser = user
            defaults.set(user.id, forKey: Constants.UserDefaults.userId)
            defaults.set(user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = user.name {
                defaults.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = user.image {
                defaults.set(image, forKey: Constants.UserDefaults.userImage)
            }

            self.isAuthenticated = true
            PrivacyLogger.debug("AuthManager", "browser_sign_in=success")

            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: user.id)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // Closing the sheet is a choice, not a failure: no banner.
            throw error
        } catch {
            PrivacyLogger.debug("AuthManager", "browser_sign_in=failed")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Up with Passkey

    func signUpWithPasskey(email: String) async throws {
        PrivacyLogger.debug("AuthManager", "passkey_sign_up=started")
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

            PrivacyLogger.debug("AuthManager", "passkey_sign_up=success")

            // Save user info
            defaults.set(user.id, forKey: Constants.UserDefaults.userId)
            defaults.set(user.email, forKey: Constants.UserDefaults.userEmail)
            if let name = user.name {
                defaults.set(name, forKey: Constants.UserDefaults.userName)
            }
            if let image = user.image {
                defaults.set(image, forKey: Constants.UserDefaults.userImage)
            }

            // Set authenticated (session-based auth)
            self.isAuthenticated = true

            // Trigger local data upload if transitioning from offline-only mode
            ConnectionModeManager.shared.handleSuccessfulSignIn(userId: user.id)

        } catch let error as PasskeyError {
            // Don't show error for user cancellation
            if case .userCancelled = error {
                AppLog.debug("ℹ️ [AuthManager] Passkey sign-up cancelled by user")
                throw error
            }
            AppLog.debug("❌ [AuthManager] Passkey sign-up failed: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            throw error
        } catch {
            AppLog.debug("❌ [AuthManager] Passkey sign-up failed: \(error)")
            self.errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Sign Out

    /// Store a token the server just renewed (Task b8999ea3).
    ///
    /// It arrives as a bare JWT in the body, while the Keychain holds a whole Cookie header, so the
    /// value is folded INTO the stored header rather than replacing it — writing the raw token
    /// would send a nameless cookie and sign the user out on the very launch meant to keep them in.
    ///
    /// A missing token is the normal case: renewal only fires once a session is over 24 hours old.
    private func persistRenewedSession(_ response: SessionResponse) {
        guard let token = response.sessionToken else { return }
        let stored = try? keychainService.getSessionCookie()
        do {
            try keychainService.saveSessionCookie(SessionCookie.replacingToken(in: stored, with: token))
            PrivacyLogger.debug("AuthManager", "session_renewed=stored")
        } catch {
            // Not fatal: the existing cookie is still valid until its own expiry, so the user keeps
            // working and the next launch simply tries again.
            PrivacyLogger.debug("AuthManager", "session_renewed=save_failed")
        }
    }

    func signOut() async throws {
        let departingUserId = currentUser?.id
            ?? defaults.string(forKey: Constants.UserDefaults.userId)
        isLoading = true
        defer { isLoading = false }

        AppLog.debug("🚪 [AuthManager] Starting sign-out - clearing ALL user data...")

        do {
            // Call sign out endpoint
            try await apiClient.signOut()
        } catch {
            AppLog.debug("Sign out API call failed: \(error)")
            // Continue with local cleanup even if API call fails
        }

        // ===== THE CORE'S CACHE AND JOURNAL =====
        // astrid-core holds the departing user's tasks, lists and unsent writes; replaying those
        // writes under the next session would cross-post. Its sign-out wipes both, locally.
        try? await core.run(CoreCommand(kind: "signOut"))

        // ===== KEYCHAIN CLEANUP =====
        // Clear ALL keychain items to prevent credential leakage
        try? keychainService.deleteSessionCookie()
        keychainService.deleteOAuthClientSecret()
        try? keychainService.deleteOAuthAccessToken()

        // ===== HTTP COOKIE STORAGE CLEANUP =====
        // CRITICAL: Clear URLSession's cookie storage to prevent session leakage
        // This is essential for user data isolation - cached cookies can leak between users
        if let apiURL = URL(string: Constants.API.baseURL) {
            if let cookies = cookieStorage.cookies(for: apiURL) {
                AppLog.debug("🍪 [AuthManager] Clearing \(cookies.count) cached cookies for \(apiURL.host ?? "unknown")...")
                for cookie in cookies {
                    cookieStorage.deleteCookie(cookie)
                }
            }
        }
        // Also clear all cookies for the domain (covers subdomains too)
        if let allCookies = cookieStorage.cookies {
            let brandCookies = allCookies.filter { Brand.isBrandCookieDomain($0.domain) }
            AppLog.debug("🍪 [AuthManager] Clearing \(brandCookies.count) \(Brand.appName) domain cookies...")
            for cookie in brandCookies {
                cookieStorage.deleteCookie(cookie)
            }
        }

        // ===== USERDEFAULTS - USER DATA =====
        defaults.removeObject(forKey: Constants.UserDefaults.userId)
        defaults.removeObject(forKey: Constants.UserDefaults.userEmail)
        defaults.removeObject(forKey: Constants.UserDefaults.userName)
        defaults.removeObject(forKey: Constants.UserDefaults.userImage)

        // ===== USERDEFAULTS - REMINDER SETTINGS =====
        // Clear all notification/reminder preferences (user-specific)
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

        // ===== USERDEFAULTS - OTHER USER DATA =====
        defaults.removeObject(forKey: "GoogleOAuthCodeVerifier")
        defaults.removeObject(forKey: "pendingAttachments")
        defaults.removeObject(forKey: "oauth_token_cache")
        defaults.removeObject(forKey: "oauth_token_expires_at")

        // ===== CORE DATA =====
        AppLog.debug("🗑️ [AuthManager] Clearing Core Data...")
        do {
            try CoreDataManager.shared.clearAll()
            AppLog.debug("✅ [AuthManager] Core Data cleared successfully")
        } catch {
            AppLog.debug("❌ [AuthManager] Failed to clear Core Data: \(error)")
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

        // The core's `signOut` wiped its journal (queued writes belong to the departing user —
        // replaying them under a new session would cross-post). A pre-core `outbox.json` the
        // upgrade could not move goes too. Then every persisted sync ledger and cache, and the
        // services' in-memory state.
        try? FileManager.default.removeItem(at: journalFileURL ?? OutboxStore.defaultFileURL())
        SyncStateReset.clearAll(defaults: defaults)
        GitHubSyncService.shared.resetForSignOut()
        GoogleTasksSyncService.shared.resetForSignOut()
        FeatureFlagService.shared.clearCache(userId: departingUserId)

        // Clear user preferences and settings
        MyTasksPreferencesService.shared.clearData()
        UserSettingsService.shared.clearData()

        // ===== CACHE CLEANUP =====
        // Clear all user-related caches to prevent data leakage between users
        UserImageCache.shared.clearCache()
        ProfileCache.shared.clearAllCache()
        ImageCache.shared.clearCache()
        AIAgentCache.shared.clear()

        AppLog.debug("✅ [AuthManager] All user data cleared successfully")

        self.isAuthenticated = false
        self.currentUser = nil
    }
    
    // MARK: - Update Current User

    func updateCurrentUser(_ user: User) {
        AppLog.debug("👤 [AuthManager] Updating current user")
        self.currentUser = user

        // Update UserDefaults
        defaults.set(user.id, forKey: Constants.UserDefaults.userId)
        defaults.set(user.email, forKey: Constants.UserDefaults.userEmail)
        if let name = user.name {
            defaults.set(name, forKey: Constants.UserDefaults.userName)
        } else {
            defaults.removeObject(forKey: Constants.UserDefaults.userName)
        }
        if let image = user.image {
            defaults.set(image, forKey: Constants.UserDefaults.userImage)
        } else {
            defaults.removeObject(forKey: Constants.UserDefaults.userImage)
        }

        AppLog.debug("✅ [AuthManager] Current user updated")
    }

    // MARK: - Helpers

    var userId: String? {
        currentUser?.id ?? defaults.string(forKey: Constants.UserDefaults.userId)
    }

    var userEmail: String? {
        currentUser?.email ?? defaults.string(forKey: Constants.UserDefaults.userEmail)
    }
}
