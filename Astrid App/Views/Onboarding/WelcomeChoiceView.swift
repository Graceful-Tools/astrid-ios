import SwiftUI

/// First-run welcome screen that lets users choose between signing in or using the app locally.
/// This enables offline-only mode where users can use the app without an account.
struct WelcomeChoiceView: View {
    @EnvironmentObject var authManager: AuthManager
    @ObservedObject private var connectionManager = ConnectionModeManager.shared
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    @State private var isCreatingLocalUser = false
    @State private var navigateToLogin = false

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Theme background
                backgroundColor
                    .ignoresSafeArea()

                VStack(spacing: Theme.spacing24) {
                    Spacer()

                    // Astrid character and welcome message
                    VStack(spacing: Theme.spacing16) {
                        Image("AstridCharacter")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 24))

                        Text(Brand.localized("welcome.title"))
                            .font(Theme.Typography.title1())
                            .foregroundColor(textColor)

                        Text(NSLocalizedString("welcome.subtitle", comment: "Your intelligent task manager"))
                            .font(Theme.Typography.body())
                            .foregroundColor(secondaryTextColor)
                    }

                    Spacer()

                    // Choice buttons
                    VStack(spacing: Theme.spacing16) {
                        // Sign in option (primary)
                        Button {
                            markWelcomeSeen()
                            navigateToLogin = true
                        } label: {
                            HStack(spacing: Theme.spacing12) {
                                Image(systemName: "person.circle.fill")
                                    .font(Theme.Typography.headline())
                                Text(NSLocalizedString("welcome.sign_in", comment: "Sign in"))
                                    .font(Theme.Typography.headline())
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .background(Theme.accent)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))

                        // Local mode option (secondary)
                        Button {
                            createLocalUser()
                        } label: {
                            HStack(spacing: Theme.spacing12) {
                                if isCreatingLocalUser {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: textColor))
                                } else {
                                    Image(systemName: "iphone")
                                        .font(Theme.Typography.headline())
                                }
                                Text(NSLocalizedString("welcome.use_locally", comment: "Use without account"))
                                    .font(Theme.Typography.headline())
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.plain)
                        .background(secondaryButtonBackground)
                        .foregroundColor(textColor)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLarge))
                        .disabled(isCreatingLocalUser)
                    }
                    .padding(.horizontal, Theme.spacing32)

                    Text(NSLocalizedString("welcome.local_note", comment: "You can sign in later to sync across devices"))
                        .font(Theme.Typography.caption2())
                        .foregroundColor(secondaryTextColor)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.spacing32)

                    Spacer()
                        .frame(height: Theme.spacing32)
                }
            }
            .navigationDestination(isPresented: $navigateToLogin) {
                LoginView()
                    .environmentObject(authManager)
                    .navigationBarBackButtonHidden(false)
            }
        }
    }

    // MARK: - Actions

    private func markWelcomeSeen() {
        UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
    }

    private func createLocalUser() {
        isCreatingLocalUser = true
        markWelcomeSeen()

        _Concurrency.Task {
            await connectionManager.createLocalUser()
            isCreatingLocalUser = false
        }
    }

    // MARK: - Theme Colors

    private var backgroundColor: Color {
        switch effectiveTheme {
        case "ocean":
            return Theme.Ocean.bgPrimary
        case "dark":
            return Theme.Dark.bgPrimary
        default:
            return Theme.bgPrimary
        }
    }

    private var textColor: Color {
        switch effectiveTheme {
        case "dark":
            return Theme.Dark.textPrimary
        default:
            return Theme.textPrimary
        }
    }

    private var secondaryTextColor: Color {
        switch effectiveTheme {
        case "dark":
            return Theme.Dark.textSecondary
        default:
            return Theme.textSecondary
        }
    }

    private var secondaryButtonBackground: Color {
        switch effectiveTheme {
        case "dark":
            return Color(white: 0.2)
        default:
            return Color(white: 0.95)
        }
    }
}

#Preview {
    WelcomeChoiceView()
        .environmentObject(AuthManager.shared)
}

#Preview("Dark Mode") {
    WelcomeChoiceView()
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
