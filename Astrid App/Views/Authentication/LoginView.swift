import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var connectionManager = ConnectionModeManager.shared
    /// The connected deployment's brand. Starts as this build's own values, so the
    /// lockup below is never blank and never flashes a placeholder (task 97208a72).
    @ObservedObject private var serverCapabilities = ServerCapabilityService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPasskeyEmailSheet = false
    @State private var passkeyEmail = ""
    @State private var isCreatingLocalUser = false

    #if DEBUG
    @State private var showingServerSettings = false
    #endif

    var body: some View {
        NavigationStack {
            ZStack {
                // Background matching web app theme
                (colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Theme.spacing16) {
                        Spacer()
                            .frame(height: Theme.spacing16)

                        // Logo and Title - centered layout with larger icon
                        HStack(spacing: Theme.spacing16) {
                            // Astrid character icon on left (2x bigger)
                            Image("AstridCharacter")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 16))

                            // Logo text and tagline on right
                            VStack(alignment: .leading, spacing: 4) {
                                Text(serverCapabilities.capabilities.brand.resolvedWordmark)
                                    .font(.system(size: 34, weight: .bold))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

                                Text(serverCapabilities.capabilities.brand.resolvedSlogan)
                                    .font(.system(size: 16))
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                            }
                        }
                        .frame(maxWidth: .infinity)  // Center the entire unit

                        Spacer()
                            .frame(height: Theme.spacing12)

                        // Sign in header and error display
                        VStack(spacing: Theme.spacing16) {
                            Text(NSLocalizedString("auth.sign_in_header", comment: ""))
                                .font(Theme.Typography.headline())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)

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
                        }
                        .padding(.horizontal, Theme.spacing32)

                        // OAuth/Passkey Buttons - Order: Google (blue), Passkey (white), Apple (black)
                        VStack(spacing: Theme.spacing12) {
                            // 1. Google button - Most prominent (blue)
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

                            // 2. Passkey button - Opens dialog with New/Returning options
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

                            // 3. Apple button - Least prominent (black)
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

                            // Divider
                            HStack {
                                Rectangle()
                                    .fill(colorScheme == .dark ? Theme.Dark.inputBorder : Theme.inputBorder)
                                    .frame(height: 1)
                                Text(NSLocalizedString("auth.or", comment: "or"))
                                    .font(Theme.Typography.caption1())
                                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                    .padding(.horizontal, Theme.spacing8)
                                Rectangle()
                                    .fill(colorScheme == .dark ? Theme.Dark.inputBorder : Theme.inputBorder)
                                    .frame(height: 1)
                            }
                            .padding(.vertical, Theme.spacing8)

                            // 4. Use without account button
                            Button {
                                createLocalUser()
                            } label: {
                                HStack(spacing: Theme.spacing12) {
                                    if isCreatingLocalUser {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .white : .black))
                                    } else {
                                        Image(systemName: "iphone")
                                            .font(Theme.Typography.headline())
                                    }
                                    Text(NSLocalizedString("auth.use_without_account", comment: "Use without account"))
                                        .font(Theme.Typography.headline())
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                            }
                            .buttonStyle(.plain)
                            .background(colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.9))
                            .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                            .disabled(isLoading || isCreatingLocalUser)
                            .opacity(isLoading || isCreatingLocalUser ? 0.6 : 1.0)

                            // Description text
                            Text(NSLocalizedString("auth.local_mode_description", comment: "Your tasks stay on this device. Sign in later to sync across devices."))
                                .font(Theme.Typography.caption2())
                                .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.spacing4)
                        }
                        .padding(.horizontal, Theme.spacing32)

                        Spacer()
                            .frame(height: Theme.spacing24)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            #if DEBUG
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingServerSettings = true
                    } label: {
                        Image(systemName: "server.rack")
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
            }
            .sheet(isPresented: $showingServerSettings) {
                NavigationStack {
                    ServerSettingsView()
                }
            }
            #else
            .navigationBarHidden(true)
            #endif
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
            // Ask the connected deployment who it is. /api/v1/capabilities is
            // unauthenticated precisely so this can happen before sign-in — which is
            // exactly when the app needs to know which brand and which sign-in methods
            // to show. Failure leaves this build's own brand in place (task 97208a72).
            .task { await serverCapabilities.refreshIfServerChanged() }
        }
    }

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
            // Don't show error for user cancellation
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
            // Don't show error for user cancellation
            if case .userCancelled = error {
                isLoading = false
                return
            }
            // Handle existing user - suggest sign in instead
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

    private func createLocalUser() {
        isCreatingLocalUser = true
        showError = false

        _Concurrency.Task {
            await connectionManager.createLocalUser()
            isCreatingLocalUser = false
        }
    }
}

// MARK: - Passkey Email Sheet

struct PasskeyEmailSheet: View {
    @Binding var email: String
    @Binding var isLoading: Bool
    let onCancel: () -> Void
    let onCreate: () -> Void
    let onSignIn: () -> Void  // For returning users without email
    @Environment(\.colorScheme) var colorScheme
    @FocusState private var isEmailFocused: Bool

    private var hasValidEmail: Bool {
        !email.isEmpty && email.contains("@") && email.contains(".")
    }

    var body: some View {
        VStack(spacing: Theme.spacing20) {
            // Header
            VStack(spacing: Theme.spacing8) {
                Image(systemName: "person.badge.key.fill")
                    .font(.system(size: 32))
                    .foregroundColor(Theme.accent)

                Text(NSLocalizedString("auth.continue_passkey", comment: "Continue with Passkey"))
                    .font(Theme.Typography.headline())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
            }
            .padding(.top, Theme.spacing16)

            // New user - Email input
            VStack(alignment: .leading, spacing: Theme.spacing8) {
                Text(NSLocalizedString("auth.new_user", comment: "New?"))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.spacing24)

                TextField("Enter your email", text: $email)
                    .font(Theme.Typography.body())
                    .padding(Theme.spacing12)
                    .background(colorScheme == .dark ? Theme.Dark.inputBg : Theme.inputBg)
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.radiusMedium)
                            .stroke(colorScheme == .dark ? Theme.Dark.inputBorder : Theme.inputBorder, lineWidth: 1)
                    )
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .focused($isEmailFocused)
                    .disabled(isLoading)
                    .padding(.horizontal, Theme.spacing24)
            }

            // Returning user - Only show when no email entered
            if email.isEmpty {
                Text(NSLocalizedString("auth.returning_user", comment: "Returning?"))
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.spacing24)
            }

            // Single button that handles both cases
            Button {
                if hasValidEmail {
                    onCreate()  // New user with email
                } else {
                    onSignIn()  // Returning user - authenticate
                }
            } label: {
                HStack(spacing: Theme.spacing8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(colorScheme == .dark ? Color.white : Color.black)
                    } else {
                        Image(systemName: "person.badge.key.fill")
                    }
                    Text(NSLocalizedString("auth.continue_passkey", comment: "Continue with Passkey"))
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
            .padding(.horizontal, Theme.spacing24)

            // Cancel button
            Button("Back") {
                onCancel()
            }
            .font(Theme.Typography.body())
            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)

            Spacer()
        }
        .background(colorScheme == .dark ? Theme.Dark.bgPrimary : Theme.bgPrimary)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthManager.shared)
}
