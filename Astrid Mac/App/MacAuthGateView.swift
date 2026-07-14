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
        .task {
            await auth.checkAuthentication()
            hotKeyController.registerIfNeeded()
        }
    }
}

/// Native sign-in screen — Apple / Google / Passkey / email (passwordless), all via AuthManager.
struct MacLoginView: View {
    @StateObject private var auth = AuthManager.shared
    @State private var email = ""

    private var emailValid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".")
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "checklist").font(.system(size: 52)).foregroundStyle(.tint)
                Text("Astrid").font(.largeTitle.bold())
                Text("Sign in to your account").foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)

            VStack(spacing: 10) {
                signInButton("Sign in with Apple", "apple.logo") { try await auth.signInWithApple() }
                signInButton("Sign in with Google", "globe") { try await auth.signInWithGoogle() }
                signInButton("Sign in with Passkey", "key.fill") {
                    try await auth.signInWithPasskey(email: emailValid ? email : nil)
                }
            }

            Divider().frame(width: 260)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit { if emailValid { emailContinue() } }
                Button(action: emailContinue) {
                    Text("Continue with Email").frame(width: 244)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!emailValid || auth.isLoading)
            }

            if auth.isLoading { ProgressView().controlSize(.small) }
            if let err = auth.errorMessage, !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                    .frame(width: 280)
            }
        }
        .padding(40)
        .frame(width: 380)
    }

    @ViewBuilder
    private func signInButton(_ title: String, _ icon: String, _ op: @escaping () async throws -> Void) -> some View {
        Button {
            run(op)
        } label: {
            Label(title, systemImage: icon).frame(width: 244)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(auth.isLoading)
    }

    private func emailContinue() {
        guard emailValid else { return }
        run { try await auth.signUpPasswordless(email: email.trimmingCharacters(in: .whitespaces), name: nil) }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        _Concurrency.Task { try? await op() }
    }
}
#endif
