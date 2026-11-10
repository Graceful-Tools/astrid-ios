import SwiftUI

/// Sign-in prompt view shown to local-only users
/// Displays benefits of signing in and login buttons
struct SignInPromptView: View {
    @Environment(\.colorScheme) var colorScheme
    @ThemedPalette private var palette
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authManager: AuthManager

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPasskeyEmailSheet = false
    @State private var passkeyEmail = ""

    var body: some View {
        ZStack {
            // Theme background
            Color.clear.themedBackgroundPrimary()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                FloatingTextHeader(NSLocalizedString("auth.sign_in_prompt_title", comment: ""), icon: "person.circle", showBackButton: true)
                    .padding(.top, Theme.spacing8)

                ScrollView {
                    VStack(spacing: Theme.spacing24) {
                        // Benefits section
                        benefitsSection

                        // Error display
                        if showError {
                            HStack(spacing: Theme.spacing8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(Theme.Typography.caption1())
                                Text(errorMessage)
                                    .font(Theme.Typography.caption1())
                            }
                            .foregroundColor(Theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.spacing4)
                        }

                        // Sign in buttons
                        signInButtons
                    }
                    .padding(Theme.spacing24)
                }
            }
        }
        .navigationBarHidden(true)
        .swipeToDismiss()
        .sheet(isPresented: $showPasskeyEmailSheet) {
            PasskeyEmailSheet(
                email: $passkeyEmail,
                isLoading: $isLoading,
                onCancel: {
                    showPasskeyEmailSheet = false
                },
                onCreate: {
                    showPasskeyEmailSheet = false
                    _Concurrency.Task { await signUpWithPasskey() }
                },
                onSignIn: {
                    showPasskeyEmailSheet = false
                    _Concurrency.Task { await signInWithPasskey() }
                }
            )
            .presentationDetents([.height(380)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Benefits Section

    private var benefitsSection: some View {
        VStack(spacing: Theme.spacing16) {
            // Header
            VStack(spacing: Theme.spacing8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(Theme.accent)

                Text(NSLocalizedString("auth.sign_in_cta", comment: ""))
                    .font(Theme.Typography.headline())
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.center)
            }

            // Benefits list
            VStack(spacing: Theme.spacing12) {
                benefitRow(
                    icon: "icloud.and.arrow.up",
                    title: NSLocalizedString("auth.benefit_sync_title", comment: ""),
                    description: NSLocalizedString("auth.benefit_sync_desc", comment: "")
                )

                benefitRow(
                    icon: "person.2.fill",
                    title: NSLocalizedString("auth.benefit_collaborate_title", comment: ""),
                    description: NSLocalizedString("auth.benefit_collaborate_desc", comment: "")
                )

                benefitRow(
                    icon: "lock.shield.fill",
                    title: NSLocalizedString("auth.benefit_backup_title", comment: ""),
                    description: NSLocalizedString("auth.benefit_backup_desc", comment: "")
                )
            }
        }
        .padding(Theme.spacing16)
        .background(palette.bgSecondary)
        .cornerRadius(Theme.radiusMedium)
    }

    private func benefitRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Theme.spacing12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Theme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: Theme.spacing4) {
                Text(title)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)

                Text(description)
                    .font(Theme.Typography.caption1())
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()
        }
    }

    // MARK: - Sign In Buttons

    private var signInButtons: some View {
        VStack(spacing: Theme.spacing12) {
            // Google button
            Button {
                _Concurrency.Task { await signInWithGoogle() }
            } label: {
                HStack(spacing: Theme.spacing12) {
                    Image(systemName: "globe")
                        .font(Theme.Typography.headline())
                    Text(NSLocalizedString("auth.continue_with_google", comment: ""))
                        .font(Theme.Typography.headline())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.plain)
            .background(Theme.accent)
            .foregroundColor(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)

            // Passkey button
            Button {
                passkeyEmail = ""
                showPasskeyEmailSheet = true
            } label: {
                HStack(spacing: Theme.spacing12) {
                    Image(systemName: "person.badge.key.fill")
                        .font(Theme.Typography.headline())
                    Text(NSLocalizedString("auth.continue_with_passkey", comment: ""))
                        .font(Theme.Typography.headline())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.plain)
            .background(colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95))
            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)

            // Apple button
            Button {
                _Concurrency.Task { await signInWithApple() }
            } label: {
                HStack(spacing: Theme.spacing12) {
                    Image(systemName: "apple.logo")
                        .font(Theme.Typography.headline())
                    Text(NSLocalizedString("auth.continue_with_apple", comment: ""))
                        .font(Theme.Typography.headline())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
            }
            .buttonStyle(.plain)
            .background(Color.black)
            .foregroundColor(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
            .disabled(isLoading)
            .opacity(isLoading ? 0.6 : 1.0)

            // Note about data
            Text(NSLocalizedString("auth.sign_in_data_note", comment: ""))
                .font(Theme.Typography.caption2())
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, Theme.spacing8)
        }
    }

    // MARK: - Sign In Methods

    private func signInWithApple() async {
        isLoading = true
        showError = false

        do {
            try await authManager.signInWithApple()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }

    private func signInWithGoogle() async {
        isLoading = true
        showError = false

        do {
            try await authManager.signInWithGoogle()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }

    private func signInWithPasskey() async {
        isLoading = true
        showError = false

        do {
            try await authManager.signInWithPasskey()
        } catch let error as PasskeyError {
            if case .userCancelled = error {
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }

    private func signUpWithPasskey() async {
        isLoading = true
        showError = false

        do {
            try await authManager.signUpWithPasskey(email: passkeyEmail)
        } catch let error as PasskeyError {
            if case .userCancelled = error {
                isLoading = false
                return
            }
            if case .existingUser = error {
                errorMessage = error.localizedDescription
                showError = true
                isLoading = false
                return
            }
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isLoading = false
        }
    }
}

#Preview {
    SignInPromptView()
        .environmentObject(AuthManager.shared)
}
