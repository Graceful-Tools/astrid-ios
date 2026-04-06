import SwiftUI

/// Floating header with rounded corners and shadow (modern look)
/// Used across the app for consistent section headers
struct FloatingHeader<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // Effective theme - Auto resolves to Light or Dark based on time of day
    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    var body: some View {
        content
            .padding(.horizontal, Theme.spacing16)
            .padding(.vertical, Theme.spacing12)
            .background(headerBackground)
            .cornerRadius(Theme.radiusLarge)
            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
            .padding(.horizontal, 8)  // Match standard margins
    }

    /// Header background with support for all themes
    @ViewBuilder
    private var headerBackground: some View {
        if effectiveTheme == "light" {
            // Light theme: Use thin material for glass effect
            Rectangle()
                .fill(Theme.LiquidGlass.secondaryGlassMaterial)
        } else if effectiveTheme == "ocean" {
            Color.white  // Pure white header on Ocean theme
        } else {
            getHeaderBackground()
        }
    }

    /// Get header background color based on current theme
    private func getHeaderBackground() -> Color {
        return effectiveTheme == "dark" ? Theme.Dark.headerBg : Theme.headerBg
    }
}

/// Floating header with text and optional icon (most common use case)
struct FloatingTextHeader: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let text: String
    let icon: String?
    let iconColor: Color?
    let showBackButton: Bool
    let onBack: (() -> Void)?

    init(_ text: String, icon: String? = nil, iconColor: Color? = nil, showBackButton: Bool = false, onBack: (() -> Void)? = nil) {
        self.text = text
        self.icon = icon
        self.iconColor = iconColor
        self.showBackButton = showBackButton
        self.onBack = onBack
    }

    /// Effective theme - Auto resolves to Light or Dark based on system setting
    /// Ocean and Light themes always use dark text (light backgrounds)
    /// Dark theme always uses light text (dark background)
    private var effectiveTheme: String {
        if themeMode == "auto" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return themeMode
    }

    /// Text color based on effective theme (not system colorScheme)
    /// Ocean and Light themes have light backgrounds → dark text
    /// Dark theme has dark background → light text
    private var textColor: Color {
        switch effectiveTheme {
        case "dark":
            return Theme.Dark.textPrimary  // White text on dark background
        case "ocean", "light":
            return Theme.textPrimary       // Dark text on light/ocean background
        default:
            return Theme.textPrimary
        }
    }

    var body: some View {
        FloatingHeader {
            HStack(spacing: Theme.spacing8) {
                // Back button (leading)
                if showBackButton {
                    Button(action: { onBack?() ?? dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(Theme.Typography.headline())
                            .foregroundColor(textColor)
                    }
                    .buttonStyle(.plain)
                }

                if let icon = icon {
                    Image(systemName: icon)
                        .font(Theme.Typography.headline())
                        .foregroundColor(iconColor ?? textColor)
                }

                Text(text)
                    .font(Theme.Typography.headline())
                    .foregroundColor(textColor)

                Spacer()
            }
        }
    }
}

#Preview {
    VStack(spacing: Theme.spacing16) {
        FloatingTextHeader("Settings")
        FloatingTextHeader("Reminders", icon: "bell", iconColor: Theme.accent)
        FloatingTextHeader("Appearance", icon: "paintbrush")
    }
    .themedBackgroundPrimary()
}
