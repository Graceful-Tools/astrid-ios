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
        .task {
            // Under XCTest, keep the host inert: these long-lived loops (Outbox/SSE/sync/hotkey)
            // otherwise prevent a clean process exit and make teardown hang (Task 90fa7975).
            guard !MacRuntime.isRunningTests else { return }
            OutboxManager.shared.start()          // start the write runner (drains queued writes)

            // Local reminder notifications on Mac (Task 8b81fb9e): register + request permission,
            // then schedule for current tasks. Works offline too (local tasks have due dates).
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
                if isAuth { await startSession() } else { SSEClient.shared.disconnect() }
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
            if !checking && !hasSeenOnboarding && !MacRuntime.isRunningTests { showOnboarding = true }
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
    @State private var showSignUp = false
    @State private var email = ""

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
                    Text("astrid").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.textPrimary)
                    Text("Get it done!").font(.system(size: 16)).foregroundStyle(Theme.textSecondary)
                }
                Text("Sign in to get started!").font(.headline).foregroundStyle(Theme.textPrimary)
            }
            .padding(.bottom, 4)

            VStack(spacing: 10) {
                // Passkey — primary sign-in (discoverable credential; no email needed).
                Button { run { try await auth.signInWithPasskey(email: nil) } } label: {
                    Label("Sign in with Passkey", systemImage: "person.badge.key.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(auth.isLoading)

                secondaryButton("Continue with Google", "globe") { try await auth.signInWithGoogle() }
                secondaryButton("Sign in with Apple", "apple.logo") { try await auth.signInWithApple() }
            }
            .frame(width: 280)

            VStack(spacing: 6) {
                Button("New here? Create an account with Passkey") { showSignUp = true }
                    .buttonStyle(.link).font(.callout)
                Button("Continue without an account") {
                    _Concurrency.Task { await ConnectionModeManager.shared.createLocalUser() }
                }
                .buttonStyle(.link).font(.callout).foregroundStyle(Theme.textSecondary)
            }

            if auth.isLoading { ProgressView().controlSize(.small) }
            if let err = auth.errorMessage, !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(Theme.error)
                    .multilineTextAlignment(.center).frame(width: 300)
            }
        }
        .padding(40)
        .frame(width: 400)
        .sheet(isPresented: $showSignUp) { signUpSheet }
    }

    private var signUpSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create Account").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Enter your email, then create a passkey on this Mac (Touch ID / your device).")
                .font(.callout).foregroundStyle(Theme.textSecondary)
            TextField("Email", text: $email).textFieldStyle(.roundedBorder).onSubmit(signUp)
            HStack {
                Spacer()
                Button("Cancel") { showSignUp = false }.keyboardShortcut(.escape, modifiers: [])
                Button("Create Passkey", action: signUp)
                    .buttonStyle(.borderedProminent).disabled(!emailValid)
            }
        }
        .padding(20)
        .frame(width: 380)
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
}
#endif
