//  MacAuthGateView.swift
//  Astrid for Mac — auth gate + native sign-in (tasks A1 + A2).
//
//  Root routing: restore the session on launch, then show the sign-in screen when signed out
//  and the shell when signed in — reacting live to AuthManager. Mirrors AstridApp.swift (iOS).
//  All auth logic is the shared AuthManager; this is presentation only.

#if os(macOS)
import SwiftUI

struct MacAuthGateView: View {
    @StateObject private var auth = AuthManager.shared
    @StateObject private var hotKeyController = QuickEntryHotKeyController()
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    var body: some View {
        Group {
            if auth.isCheckingAuth {
                VStack(spacing: 12) {
                    Image(systemName: "checklist").font(.system(size: 44)).foregroundStyle(.tint)
                    ProgressView().controlSize(.small)
                }
            } else if auth.isAuthenticated {
                MacRootView()
            } else {
                MacLoginView()
            }
        }
        .tint(Theme.accent)   // match the iOS app's accent blue app-wide
        .preferredColorScheme(themeMode.colorScheme)
        .task {
            await auth.checkAuthentication()
            hotKeyController.registerIfNeeded()
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
            VStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 52)).foregroundStyle(Theme.accent)
                Text("Astrid").font(.largeTitle.bold()).foregroundStyle(Theme.textPrimary)
                Text("Sign in to your account").foregroundStyle(Theme.textSecondary)
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

            Button("New here? Create an account with Passkey") { showSignUp = true }
                .buttonStyle(.link).font(.callout)

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
