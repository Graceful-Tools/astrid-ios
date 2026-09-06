//  MacAuthGateView.swift
//  Astrid for Mac — auth gate + native sign-in (tasks A1 + A2).
//
//  Root routing: restore the session on launch, then show the sign-in screen when signed out
//  and the shell when signed in — reacting live to AuthManager. Mirrors AstridApp.swift (iOS).
//  All auth logic is the shared AuthManager; this is presentation only.

#if os(macOS)
import SwiftUI
import AppKit
import UserNotifications

struct MacAuthGateView: View {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var hotKeyController = QuickEntryHotKeyController()
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @AppStorage("mac.hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var showOnboarding = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if auth.isCheckingAuth {
                VStack(spacing: 12) {
                    Image("AstridCharacter").resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    ProgressView().controlSize(.small)
                }
            } else if auth.isAuthenticated {
                MacRootView()
            } else {
                MacLoginView()
            }
        }
        .overlay { MacErrorBanner() }   // app-wide write-failure surface (Task 8a5f3066)
        .tint(Theme.accent)   // match the iOS app's accent blue app-wide
        .preferredColorScheme(themeMode.colorScheme)
        .animation(MacMotion.medium, value: themeMode)   // theme switch cross-fades (4c7b9f08)
        .task {
            // Under XCTest, keep the host inert: these long-lived loops (Outbox/SSE/sync/hotkey)
            // otherwise prevent a clean process exit and make teardown hang (Task 90fa7975).
            guard !MacRuntime.isRunningTests else { return }
            // UI testing: start from a clean signed-out state with no network work, so the sign-in
            // screen shows deterministically regardless of the machine's saved session (6c30df95).
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                auth.isCheckingAuth = false
                auth.isAuthenticated = false
                return
            }
            OutboxManager.shared.start()          // start the write runner (drains queued writes)
            MacServiceProvider.register()          // Services menu "Add to Astrid" (Task 3b9883d0)

            // Local reminder notifications on Mac (Task 8b81fb9e): register + request permission,
            // then schedule for current tasks. Works offline too (local tasks have due dates).
            MacWakeRecovery.start()   // live updates must survive sleep (task de2764fb)
            UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
            NotificationManager.shared.registerNotificationCategories()
            _ = try? await NotificationManager.shared.requestPermission()

            await auth.checkAuthentication()
            hotKeyController.registerIfNeeded()
            if auth.isAuthenticated { await startSession() }
            await NotificationManager.shared.rescheduleAllNotifications(for: TaskService.shared.tasks)
        }
        .onChange(of: auth.isAuthenticated) { _, isAuth in
            _Concurrency.Task {
                if isAuth { await startSession() }
                else { await SSEClient.shared.disconnect(); SyncManager.shared.stopAutoSync() }
            }
        }
        // Global Quick Add hotkey (and menu-bar/command actions) post this; open + focus the
        // Quick Add window here where openWindow is available (Task e51bec20).
        .onReceive(NotificationCenter.default.publisher(for: .astridOpenQuickAdd)) { _ in
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: QuickEntryHotKeyController.windowID)
        }
        // Route astrid:// / https://astrid.cc task & list deep links to the main window (Task 84993a68).
        .onOpenURL { url in
            switch MacDeepLink.parse(url) {
            case .task(let id): MacAppModel.shared.openTask(listId: nil, taskId: id)
            case .list(let id): MacAppModel.shared.openList(id)
            case .none: break
            }
        }
        .onChange(of: auth.isCheckingAuth) { _, checking in
            // Show onboarding once, after the initial auth check resolves (Task 0eeac7e8).
            // Skipped under UI testing (-uiTesting) for a deterministic login screen.
            let uiTesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")
            if !checking && !hasSeenOnboarding && !MacRuntime.isRunningTests && !uiTesting { showOnboarding = true }
        }
        .sheet(isPresented: $showOnboarding, onDismiss: { hasSeenOnboarding = true }) {
            MacOnboardingView()
        }
    }

    /// Post-auth service startup — mirrors AstridApp.swift (SSE real-time + sync workers).
    private func startSession() async {
        // Local-only mode has no server session — skip network services.
        guard ConnectionModeManager.shared.currentMode != .offlineOnly else { return }
        await SSEClient.shared.connect()                 // live updates

        // Full task+list sync via the SHARED SyncManager (same path as iOS): fetches every list
        // and every task (paginated) into the global stores, then keeps them fresh on a timer.
        // This is why lists / My Tasks now show everything instead of only opened lists.
        try? await SyncManager.shared.performFullSync(includeUserTasks: true)
        SyncManager.shared.startAutoSync()

        // Honor remote feature rollouts before scheduling gated providers (Task b0048881).
        await FeatureFlagService.shared.refreshIfStale()

        await GitHubSyncService.shared.refreshStatus()
        GitHubSyncService.shared.scheduleSync()

        // Google Tasks is behind a remote rollout / kill switch — only touch it when enabled.
        // (The service self-gates too, but skip the work entirely when off.)
        if FeatureFlagService.shared.isEnabled(.googleTasks) {
            await GoogleTasksSyncService.shared.refreshStatus()
            GoogleTasksSyncService.shared.scheduleSync()
        }
    }
}

/// Native sign-in screen — Passkey-first (primary), with Google/Apple. Passkeys share the
/// astrid.cc Relying Party with web + iOS (webcredentials associated-domain + AASA). All via
/// the shared AuthManager; mirrors the iOS LoginView, adapted to native macOS (ASAuthorization).
struct MacLoginView: View {
    @StateObject private var auth = AuthManager.shared
    /// The connected deployment's brand. Starts as this build's own values, so the
    /// lockup below is never blank and never flashes a placeholder (task 97208a72).
    @ObservedObject private var serverCapabilities = ServerCapabilityService.shared
    @State private var showSignUp = false
    @State private var email = ""
    /// A local-only passkey request found nothing on this Mac: offer the routes explicitly
    /// instead of greeting the user with the nearby-device QR (AITD-298).
    @State private var showPasskeyAlternatives = false

    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".")
    }

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 10) {
                Image("AstridCharacter").resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 88, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                VStack(spacing: 2) {
                    Text(serverCapabilities.capabilities.brand.resolvedWordmark)
                        .font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text(serverCapabilities.capabilities.brand.resolvedSlogan)
                        .font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                }
                Text(NSLocalizedString("auth.sign_in_header", comment: "")).font(.headline).foregroundStyle(Theme.textPrimary)
            }
            .padding(.bottom, 4)

            VStack(spacing: 10) {
                // Passkey — primary sign-in (discoverable credential; no email needed). Local
                // credentials first: iCloud Keychain and enabled password managers, never the
                // nearby-device QR as the opening move (AITD-298).
                Button { signInWithPasskey(PasskeySignInPlan.initialPresentation(isMac: true)) } label: {
                    Label(NSLocalizedString("mac.sign_in_passkey", comment: ""), systemImage: "person.badge.key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(auth.isLoading)
                .accessibilityIdentifier("login.passkey")

                if showPasskeyAlternatives {
                    passkeyAlternatives
                }

                secondaryButton(NSLocalizedString("auth.continue_with_google", comment: ""), "globe") { try await auth.signInWithGoogle() }
                // Hidden in the direct-download build: Developer ID profiles cannot carry the
                // Sign In with Apple entitlement, so the button would fail on tap (MacSignInOptions).
                if MacSignInOptions.showsAppleSignIn {
                    secondaryButton(NSLocalizedString("mac.sign_in_apple", comment: ""), "apple.logo") { try await auth.signInWithApple() }
                }
            }
            .frame(width: 280)

            VStack(spacing: 6) {
                Button(NSLocalizedString("mac.new_here", comment: "")) { showSignUp = true }
                    .buttonStyle(.link).font(.callout)
                Button(NSLocalizedString("mac.continue_without_account", comment: "")) {
                    _Concurrency.Task { await ConnectionModeManager.shared.createLocalUser() }
                }
                .buttonStyle(.link).font(.callout).foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("login.offline")
            }

            if auth.isLoading { ProgressView().controlSize(.small) }
            if let err = auth.errorMessage, !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(Theme.error)
                    .multilineTextAlignment(.center).frame(width: 300)
            }
        }
        .padding(40)
        .frame(width: 400)
        .background(Theme.bgPrimary)
        .sheet(isPresented: $showSignUp) { signUpSheet }
        // Ask the connected deployment who it is. /api/v1/capabilities is
        // unauthenticated precisely so this can happen before sign-in — which is exactly
        // when the app needs to know which brand to show. Failure leaves this build's
        // own brand in place (task 97208a72).
        .task { await serverCapabilities.refreshIfServerChanged() }
    }

    private var signUpSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("auth.create_account", comment: "")).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(NSLocalizedString("mac.passkey_intro", comment: ""))
                .font(.callout).foregroundStyle(Theme.textSecondary)
            TextField(NSLocalizedString("auth.email", comment: ""), text: $email).textFieldStyle(.roundedBorder).onSubmit(signUp)
            HStack {
                Spacer()
                Button(NSLocalizedString("actions.cancel", comment: "")) { showSignUp = false }.keyboardShortcut(.escape, modifiers: [])
                Button(NSLocalizedString("mac.create_passkey", comment: ""), action: signUp)
                    .buttonStyle(.borderedProminent).disabled(!emailValid)
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(Theme.bgPrimary)
    }

    private func secondaryButton(_ title: String, _ icon: String, _ op: @escaping () async throws -> Void) -> some View {
        Button { run(op) } label: {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered).controlSize(.large).disabled(auth.isLoading)
    }

    private func signUp() {
        guard emailValid else { return }
        showSignUp = false
        run { try await auth.signUpWithPasskey(email: email.trimmingCharacters(in: .whitespaces)) }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        _Concurrency.Task { try? await op() }
    }

    // MARK: - Passkey (AITD-298)

    /// The routes offered when nothing on this Mac answered: a passkey on another device (the
    /// full system sheet — the QR, when asked for), or a password manager enabled as a provider.
    private var passkeyAlternatives: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(NSLocalizedString("mac.passkey_no_local", comment: ""))
                .font(.callout).foregroundStyle(Theme.textPrimary)
            Button {
                signInWithPasskey(PasskeySignInPlan.otherDevicePresentation)
            } label: {
                Label(NSLocalizedString("mac.passkey_use_other_device", comment: ""), systemImage: "qrcode")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered).disabled(auth.isLoading)
            .accessibilityIdentifier("login.passkey.otherDevice")
            Button {
                PlatformApplication.open(PasskeySignInPlan.passwordOptionsSettingsURL)
            } label: {
                Label(NSLocalizedString("mac.passkey_password_manager", comment: ""), systemImage: "key.horizontal")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("login.passkey.passwordManager")
            Text(NSLocalizedString("mac.passkey_password_manager_hint", comment: ""))
                .font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.bgSecondary, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier("login.passkey.alternatives")
    }

    private func signInWithPasskey(_ presentation: PasskeyPresentation) {
        _Concurrency.Task {
            do {
                try await auth.signInWithPasskey(email: nil, presentation: presentation)
                showPasskeyAlternatives = false
            } catch let error as PasskeyError {
                switch PasskeySignInPlan.nextStep(after: presentation, error: error) {
                case .offerAlternatives: showPasskeyAlternatives = true
                case .surfaceError, .none: break   // AuthManager already set errorMessage for real failures
                }
            } catch {
                // Non-passkey failures (network, server) are surfaced by AuthManager.errorMessage.
            }
        }
    }
}
#endif
