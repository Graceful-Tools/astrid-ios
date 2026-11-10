import SwiftUI

/// Splash screen shown during app launch while checking authentication
/// Matches the empty list screen layout exactly: header, Astrid speech bubble, bottom bar
struct SplashView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: String {
        ThemeMode.resolvedName(themeMode, colorScheme: colorScheme)
    }

    private var isOceanTheme: Bool {
        effectiveTheme == "ocean"
    }

    var body: some View {
        ZStack {
            // Theme background
            getPrimaryBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Floating header (no title, no actions)
                floatingHeader

                // Main content - Astrid with speech bubble
                ScrollView {
                    EmptyStateView(
                        message: NSLocalizedString("splash.loading", comment: "Loading your tasks..."),
                        buttonTitle: nil,
                        buttonAction: nil
                    )
                    .frame(minHeight: UIScreen.main.bounds.height - 200)
                }

                // Bottom bar (empty quick add style)
                bottomBar
            }
        }
    }

    // MARK: - Floating Header

    private var floatingHeader: some View {
        HStack(spacing: 0) {
            // Leading: Hamburger menu icon
            HamburgerMenuIcon()
                .padding(.leading, 22)
                .padding(.trailing, 10)

            Spacer()
        }
        .padding(.leading, 0)
        .padding(.trailing, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(headerBackground)
        .cornerRadius(Theme.radiusLarge)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
        .padding(.horizontal, 8)
        .padding(.top, Theme.spacing8)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            // Checkbox (neutral/gray)
            Image("check_box_0")
                .resizable()
                .frame(width: 34, height: 34)

            // Empty text input field (no placeholder)
            Rectangle()
                .fill(inputBackgroundColor)
                .frame(height: 36)
                .cornerRadius(Theme.radiusMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusMedium)
                        .stroke(inputBorderColor, lineWidth: 1)
                )

            // Plus button (muted)
            Image(systemName: "plus.circle.fill")
                .font(Theme.Typography.title2())
                .foregroundColor(mutedTextColor)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing12)
        .background(containerBackground)
        .cornerRadius(Theme.radiusLarge)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: -2)
        .padding(.horizontal, 8)
        .padding(.bottom, 0)
    }

    // MARK: - Theme Helpers

    @ViewBuilder
    private func getPrimaryBackground() -> some View {
        if effectiveTheme == "ocean" {
            Theme.Ocean.bgPrimary
        } else if effectiveTheme == "dark" {
            Theme.Dark.bgPrimary
        } else {
            Theme.bgPrimary
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        if effectiveTheme == "light" {
            Rectangle()
                .fill(Theme.LiquidGlass.secondaryGlassMaterial)
        } else if effectiveTheme == "ocean" {
            Color.white
        } else {
            getHeaderBackground()
        }
    }

    private func getHeaderBackground() -> Color {
        if effectiveTheme == "dark" {
            return Theme.Dark.headerBg
        }
        return Theme.headerBg
    }

    @ViewBuilder
    private var containerBackground: some View {
        if effectiveTheme == "light" {
            Rectangle()
                .fill(Theme.LiquidGlass.secondaryGlassMaterial)
        } else {
            containerBackgroundColor
        }
    }

    private var containerBackgroundColor: Color {
        if effectiveTheme == "dark" {
            return Theme.Dark.bgPrimary
        }
        return Color.white.opacity(0.8)
    }

    private var inputBackgroundColor: Color {
        if effectiveTheme == "dark" {
            return Theme.Dark.inputBg
        }
        return Color.white
    }

    private var inputBorderColor: Color {
        if effectiveTheme == "dark" {
            return Theme.Dark.inputBorder
        }
        return Theme.Ocean.inputBorder
    }

    private var mutedTextColor: Color {
        if isOceanTheme {
            return Theme.Ocean.textMuted
        }
        return effectiveTheme == "dark" ? Theme.Dark.textMuted : Theme.textMuted
    }
}

#Preview {
    SplashView()
}

#Preview("Dark Mode") {
    SplashView()
        .preferredColorScheme(.dark)
}
