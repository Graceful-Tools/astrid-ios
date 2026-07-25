import SwiftUI

/// Theme system matching the web app's design tokens
/// Based on styles/themes/light-theme.css and dark-theme.css
struct Theme {
#if os(macOS)
    // On macOS the base surface/text/border tokens resolve to the SELECTED theme (ocean/light/dark/
    // auto), so the Mac app renders every theme — not just the light palette (Task: Mac themes).
    // iOS keeps the fixed light values below (#else) and does its own per-view effectiveTheme.

    // Cached theme mode (Task 3c34c411): tokens are computed vars, so every color access used to
    // read UserDefaults (~6 reads × N rows × every render). The cache invalidates synchronously on
    // any UserDefaults change (queue: nil → delivered on the posting thread). Color access happens
    // on the main thread (SwiftUI render), so the unsafe statics are effectively main-confined.
    nonisolated(unsafe) private static var _cachedMode: String?
    nonisolated(unsafe) private static var _modeObserver: NSObjectProtocol?

    static var currentThemeMode: String {
        if let m = _cachedMode { return m }
        let m = UserDefaults.standard.string(forKey: "themeMode") ?? "ocean"
        _cachedMode = m
        if _modeObserver == nil {
            _modeObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
                _cachedMode = UserDefaults.standard.string(forKey: "themeMode") ?? "ocean"
            }
        }
        return m
    }

    static func themed(light: Color, dark: Color, ocean: Color) -> Color {
        switch currentThemeMode {
        case "dark":  return dark
        case "ocean": return ocean
        case "light": return light
        default:      // auto → follow the system appearance
            let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    // MARK: - Background Colors
    static var bgPrimary: Color { themed(light: .init(red: 1, green: 1, blue: 1), dark: Dark.bgPrimary, ocean: Ocean.bgPrimary) }
    static var bgSecondary: Color { themed(light: .init(red: 249/255, green: 250/255, blue: 251/255), dark: Dark.bgSecondary, ocean: Ocean.bgSecondary) }
    static var bgTertiary: Color { themed(light: .init(red: 243/255, green: 244/255, blue: 246/255), dark: Dark.bgTertiary, ocean: Ocean.bgTertiary) }
    static var bgHover: Color { themed(light: .init(red: 1, green: 1, blue: 1), dark: Dark.bgHover, ocean: Ocean.bgHover) }
    static var bgActive: Color { themed(light: .init(red: 229/255, green: 231/255, blue: 235/255), dark: Dark.bgActive, ocean: Ocean.bgActive) }
    static var bgSelected: Color { themed(light: .init(red: 239/255, green: 246/255, blue: 255/255), dark: Dark.bgSelected, ocean: Ocean.bgSelected) }
    static let bgSelectedBorder = Color(red: 191/255, green: 219/255, blue: 254/255)

    // MARK: - Border Colors
    static var border: Color { themed(light: .init(red: 229/255, green: 231/255, blue: 235/255), dark: Dark.border, ocean: Ocean.border) }
    static var borderHover: Color { themed(light: .init(red: 209/255, green: 213/255, blue: 219/255), dark: Dark.borderHover, ocean: Ocean.borderHover) }
    static let borderFocus = Color(red: 59/255, green: 130/255, blue: 246/255)
    static let borderInput = Color(red: 209/255, green: 213/255, blue: 219/255)

    // MARK: - Input Colors (themed like iOS: chrome silver on Ocean, black on Dark)
    static var inputBg: Color { themed(light: .init(red: 1, green: 1, blue: 1), dark: Dark.inputBg, ocean: Ocean.inputBg) }
    static var inputBorder: Color { themed(light: .init(red: 209/255, green: 213/255, blue: 219/255), dark: Dark.inputBorder, ocean: Ocean.inputBorder) }

    // MARK: - Text Colors
    static var textPrimary: Color { themed(light: .init(red: 17/255, green: 24/255, blue: 39/255), dark: Dark.textPrimary, ocean: Ocean.textPrimary) }
    static var textSecondary: Color { themed(light: .init(red: 75/255, green: 85/255, blue: 99/255), dark: Dark.textSecondary, ocean: Ocean.textSecondary) }
    static var textMuted: Color { themed(light: .init(red: 107/255, green: 114/255, blue: 128/255), dark: Dark.textMuted, ocean: Ocean.textMuted) }
    static let textInverted = Color(red: 255/255, green: 255/255, blue: 255/255)
    static var textSelected: Color { themed(light: .init(red: 17/255, green: 24/255, blue: 39/255), dark: Dark.textSelected, ocean: Ocean.textSelected) }
#else
    // MARK: - Background Colors

    static let bgPrimary = Color(red: 255/255, green: 255/255, blue: 255/255)
    static let bgSecondary = Color(red: 249/255, green: 250/255, blue: 251/255)
    static let bgTertiary = Color(red: 243/255, green: 244/255, blue: 246/255)
    static let bgHover = Color(red: 255/255, green: 255/255, blue: 255/255)
    static let bgActive = Color(red: 229/255, green: 231/255, blue: 235/255)
    static let bgSelected = Color(red: 239/255, green: 246/255, blue: 255/255)
    static let bgSelectedBorder = Color(red: 191/255, green: 219/255, blue: 254/255)

    // MARK: - Border Colors

    static let border = Color(red: 229/255, green: 231/255, blue: 235/255)
    static let borderHover = Color(red: 209/255, green: 213/255, blue: 219/255)
    static let borderFocus = Color(red: 59/255, green: 130/255, blue: 246/255)
    static let borderInput = Color(red: 209/255, green: 213/255, blue: 219/255)

    // MARK: - Text Colors

    static let textPrimary = Color(red: 17/255, green: 24/255, blue: 39/255)
    static let textSecondary = Color(red: 75/255, green: 85/255, blue: 99/255)
    static let textMuted = Color(red: 107/255, green: 114/255, blue: 128/255)
    static let textInverted = Color(red: 255/255, green: 255/255, blue: 255/255)
    static let textSelected = Color(red: 17/255, green: 24/255, blue: 39/255)
#endif

    // MARK: - Interactive Colors

    static let accent = Color(red: 59/255, green: 130/255, blue: 246/255)
    static let accentHover = Color(red: 37/255, green: 99/255, blue: 235/255)
    static let accentText = Color(red: 255/255, green: 255/255, blue: 255/255)

    // MARK: - Status Colors

    static let success = Color(red: 34/255, green: 197/255, blue: 94/255)
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)
    static let error = Color(red: 239/255, green: 68/255, blue: 68/255)
    static let info = Color(red: 6/255, green: 182/255, blue: 212/255)

    // MARK: - Priority Colors (matching web app exactly)

    static let priorityNone = Color(red: 107/255, green: 114/255, blue: 128/255)     // rgb(107, 114, 128) - Gray
    static let priorityLow = Color(red: 59/255, green: 130/255, blue: 246/255)       // rgb(59, 130, 246) - Blue
    static let priorityMedium = Color(red: 251/255, green: 191/255, blue: 36/255)    // rgb(251, 191, 36) - Yellow
    static let priorityHigh = Color(red: 239/255, green: 68/255, blue: 68/255)       // rgb(239, 68, 68) - Red

    // MARK: - Component Specific Colors

    static let headerBg = Color(red: 249/255, green: 250/255, blue: 251/255)
    static let headerBorder = Color(red: 229/255, green: 231/255, blue: 235/255)

#if !os(macOS)
    static let inputBg = Color(red: 255/255, green: 255/255, blue: 255/255)
    static let inputBorder = Color(red: 209/255, green: 213/255, blue: 219/255)
#endif
    static let inputPlaceholder = Color(red: 156/255, green: 163/255, blue: 175/255)

    static let buttonBg = Color(red: 255/255, green: 255/255, blue: 255/255)
    static let buttonHover = Color(red: 243/255, green: 244/255, blue: 246/255)
    static let buttonBorder = Color(red: 209/255, green: 213/255, blue: 219/255)

    // MARK: - Spacing (matching web app patterns)

    static let spacing2: CGFloat = 2
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
    static let spacing32: CGFloat = 32
    static let spacing40: CGFloat = 40
    static let spacing48: CGFloat = 48

    // MARK: - Corner Radius (matching web app)

    static let radiusSmall: CGFloat = 6
    static let radiusMedium: CGFloat = 8
    static let radiusLarge: CGFloat = 12
    static let radiusXLarge: CGFloat = 16

    // MARK: - Shadows

    static let shadowSmall: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
        Color.black.opacity(0.05),
        2,
        0,
        1
    )

    static let shadowMedium: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
        Color.black.opacity(0.1),
        3,
        0,
        1
    )

    static let shadowLarge: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) = (
        Color.black.opacity(0.1),
        15,
        0,
        10
    )

    // MARK: - Typography (matching web app font weights and sizes)
    // Now supports iOS Dynamic Type for accessibility

    struct Typography {
        /// Title 1 - 34pt, scales with Dynamic Type
        static func title1() -> Font {
            .system(.largeTitle, design: .default, weight: .bold)
        }

        /// Title 2 - 28pt, scales with Dynamic Type
        static func title2() -> Font {
            .system(.title, design: .default, weight: .bold)
        }

        /// Title 3 - 22pt, scales with Dynamic Type
        static func title3() -> Font {
            .system(.title2, design: .default, weight: .semibold)
        }

        /// Headline - 17pt semibold, scales with Dynamic Type
        static func headline() -> Font {
            .system(.headline, design: .default, weight: .semibold)
        }

        /// Body - 17pt, scales with Dynamic Type
        static func body() -> Font {
            .system(.body, design: .default)
        }

        /// Callout - 16pt, scales with Dynamic Type
        static func callout() -> Font {
            .system(.callout, design: .default)
        }

        /// Subheadline - 15pt, scales with Dynamic Type
        static func subheadline() -> Font {
            .system(.subheadline, design: .default)
        }

        /// Footnote - 13pt, scales with Dynamic Type
        static func footnote() -> Font {
            .system(.footnote, design: .default)
        }

        /// Caption 1 - 12pt, scales with Dynamic Type
        static func caption1() -> Font {
            .system(.caption, design: .default)
        }

        /// Caption 2 - 11pt, scales with Dynamic Type
        static func caption2() -> Font {
            .system(.caption2, design: .default)
        }
    }
}

// MARK: - Dark Theme Support

extension Theme {
    struct Dark {
        // Background colors
        static let bgPrimary = Color(red: 17/255, green: 24/255, blue: 39/255)
        static let bgSecondary = Color(red: 31/255, green: 41/255, blue: 55/255)
        static let bgTertiary = Color(red: 55/255, green: 65/255, blue: 81/255)
        static let bgHover = Color(red: 55/255, green: 65/255, blue: 81/255)
        static let bgActive = Color(red: 75/255, green: 85/255, blue: 99/255)
        static let bgSelected = Color(red: 30/255, green: 58/255, blue: 138/255)
        static let bgSelectedBorder = Color(red: 59/255, green: 130/255, blue: 246/255)

        // Border colors
        static let border = Color(red: 75/255, green: 85/255, blue: 99/255)
        static let borderHover = Color(red: 107/255, green: 114/255, blue: 128/255)
        static let borderFocus = Color(red: 59/255, green: 130/255, blue: 246/255)
        static let borderInput = Color(red: 75/255, green: 85/255, blue: 99/255)

        // Text colors
        static let textPrimary = Color(red: 255/255, green: 255/255, blue: 255/255)
        static let textSecondary = Color(red: 209/255, green: 213/255, blue: 219/255)
        static let textMuted = Color(red: 156/255, green: 163/255, blue: 175/255)
        static let textInverted = Color(red: 17/255, green: 24/255, blue: 39/255)
        static let textSelected = Color(red: 255/255, green: 255/255, blue: 255/255)

        // Interactive colors (same as light)
        static let accent = Color(red: 59/255, green: 130/255, blue: 246/255)
        static let accentHover = Color(red: 37/255, green: 99/255, blue: 235/255)
        static let accentText = Color(red: 255/255, green: 255/255, blue: 255/255)

        // Component colors
        static let headerBg = Color(red: 31/255, green: 41/255, blue: 55/255)
        static let headerBorder = Color(red: 75/255, green: 85/255, blue: 99/255)

        static let inputBg = Color.black  // pure black input fields (dark mode)
        static let inputBorder = Color(red: 75/255, green: 85/255, blue: 99/255)
        static let inputPlaceholder = Color(red: 156/255, green: 163/255, blue: 175/255)

        static let buttonBg = Color(red: 55/255, green: 65/255, blue: 81/255)
        static let buttonHover = Color(red: 75/255, green: 85/255, blue: 99/255)
        static let buttonBorder = Color(red: 75/255, green: 85/255, blue: 99/255)
    }

    struct Ocean {
        // Background colors - Cyan ocean background (#88DCF8) - same as light except primary
        static let bgPrimary = Color(red: 136/255, green: 220/255, blue: 248/255)
        static let bgSecondary = Color(red: 249/255, green: 250/255, blue: 251/255)
        static let bgTertiary = Color(red: 243/255, green: 244/255, blue: 246/255)
        static let bgHover = Color(red: 255/255, green: 255/255, blue: 255/255)
        static let bgActive = Color(red: 229/255, green: 231/255, blue: 235/255)
        static let bgSelected = Color(red: 239/255, green: 246/255, blue: 255/255)
        static let bgSelectedBorder = Color(red: 191/255, green: 219/255, blue: 254/255)

        // Border colors - Cyan-tinted for Ocean theme
        static let border = Color(red: 136/255, green: 220/255, blue: 248/255)
        static let borderHover = Color(red: 209/255, green: 213/255, blue: 219/255)
        static let borderFocus = Color(red: 59/255, green: 130/255, blue: 246/255)
        static let borderInput = Color(red: 209/255, green: 213/255, blue: 219/255)

        // Text colors (same as light)
        static let textPrimary = Color(red: 17/255, green: 24/255, blue: 39/255)
        static let textSecondary = Color(red: 75/255, green: 85/255, blue: 99/255)
        static let textMuted = Color(red: 107/255, green: 114/255, blue: 128/255)
        static let textInverted = Color(red: 255/255, green: 255/255, blue: 255/255)
        static let textSelected = Color(red: 17/255, green: 24/255, blue: 39/255)

        // Interactive colors (same as light)
        static let accent = Color(red: 59/255, green: 130/255, blue: 246/255)
        static let accentHover = Color(red: 37/255, green: 99/255, blue: 235/255)
        static let accentText = Color(red: 255/255, green: 255/255, blue: 255/255)

        // Component colors - Cyan headers (matching ocean background) and chrome inputs
        static let headerBg = Color(red: 136/255, green: 220/255, blue: 248/255)  // Cyan (same as bgPrimary)
        static let headerBorder = Color(red: 136/255, green: 220/255, blue: 248/255)  // Cyan border (same as bgPrimary)

        // Chrome/silver styling for inputs (metallic silver-gray)
        static let inputBg = Color(red: 220/255, green: 223/255, blue: 228/255)  // Silver #DCE0E4
        static let inputBorder = Color(red: 180/255, green: 184/255, blue: 188/255)  // Chrome border #B4B8BC
        static let inputPlaceholder = Color(red: 107/255, green: 114/255, blue: 128/255)

        static let buttonBg = Color(red: 220/255, green: 223/255, blue: 228/255)  // Silver
        static let buttonHover = Color(red: 200/255, green: 204/255, blue: 209/255)  // Darker silver on hover
        static let buttonBorder = Color(red: 180/255, green: 184/255, blue: 188/255)  // Chrome border
    }

    struct LiquidGlass {
        // Liquid Glass uses dynamic, adaptive materials that reflect and refract surroundings
        // This theme leverages iOS 15+ Material blur with vibrancy
        // On iOS 26+, native .glassEffect() APIs provide enhanced glass rendering

        // MARK: - Glass Materials (for backgrounds)

        /// Ultra-thin glass for primary surfaces (most transparent)
        static let primaryGlassMaterial: Material = .ultraThinMaterial

        /// Thin glass for secondary surfaces (cards, panels)
        static let secondaryGlassMaterial: Material = .thinMaterial

        /// Regular glass for tertiary surfaces (more prominent elements)
        static let tertiaryGlassMaterial: Material = .regularMaterial

        /// Thick glass for modals and overlays
        static let thickGlassMaterial: Material = .thickMaterial

        // MARK: - Text Colors (use system dynamic colors for vibrancy)

        static let textPrimary = Color.primary       // Adapts automatically with vibrancy
        static let textSecondary = Color.secondary   // System secondary with vibrancy
        static let textMuted = Color.secondary.opacity(0.7)
        static let textInverted = Color.primary      // Inverts automatically in dark mode

        // MARK: - Accent Colors with Glass Tints

        /// Blue accent with glass transparency
        static let accentGlassTint = Color.blue.opacity(0.25)

        /// Accent color for text and icons
        static let accent = Color.blue
        static let accentHover = Color.blue.opacity(0.8)
        static let accentText = Color.white

        // MARK: - Status Glass Tints

        static let successGlassTint = Color.green.opacity(0.25)
        static let warningGlassTint = Color.orange.opacity(0.25)
        static let errorGlassTint = Color.red.opacity(0.25)
        static let infoGlassTint = Color.cyan.opacity(0.25)

        // MARK: - Border Colors (subtle glass edges)

        static let border = Color.white.opacity(0.15)
        static let borderHover = Color.white.opacity(0.25)
        static let borderFocus = Color.blue.opacity(0.5)
        static let borderInput = Color.white.opacity(0.2)

        // MARK: - Priority Glass Tints

        static let priorityNoneGlassTint = Color.gray.opacity(0.2)
        static let priorityLowGlassTint = Color.blue.opacity(0.25)
        static let priorityMediumGlassTint = Color.yellow.opacity(0.25)
        static let priorityHighGlassTint = Color.red.opacity(0.25)

        // MARK: - Background Gradients (for depth behind glass)

        /// Soft gradient for light mode backgrounds
        static let lightGradient = LinearGradient(
            colors: [
                Color(red: 245/255, green: 247/255, blue: 250/255),
                Color(red: 230/255, green: 235/255, blue: 245/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Rich gradient for dark mode backgrounds
        static let darkGradient = LinearGradient(
            colors: [
                Color(red: 20/255, green: 25/255, blue: 35/255),
                Color(red: 30/255, green: 40/255, blue: 60/255)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        /// Ocean cyan gradient for Liquid Glass Ocean theme
        static let oceanGradient = LinearGradient(
            colors: [
                Color(red: 136/255, green: 220/255, blue: 248/255),  // Cyan #88DCF8 (Ocean theme color)
                Color(red: 120/255, green: 210/255, blue: 245/255)   // Slightly richer cyan
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Environment-aware theme access

extension View {
    @ViewBuilder
    func themedBackground(light: Color, dark: Color, ocean: Color? = nil) -> some View {
        self.modifier(ThemedBackgroundModifier(lightColor: light, darkColor: dark, oceanColor: ocean))
    }

    @ViewBuilder
    func themedForeground(_ lightColor: Color, darkColor: Color, oceanColor: Color? = nil) -> some View {
        self.modifier(ThemedForegroundModifier(lightColor: lightColor, darkColor: darkColor, oceanColor: oceanColor))
    }

    @ViewBuilder
    func themedBorder(_ lightColor: Color, darkColor: Color, oceanColor: Color? = nil, width: CGFloat = 1) -> some View {
        self.modifier(ThemedBorderModifier(lightColor: lightColor,
                                          darkColor: darkColor,
                                          oceanColor: oceanColor,
                                          width: width))
    }

    // MARK: - Semantic Theme Helpers (automatically use correct theme)

    /// Apply primary background color (main app background)
    func themedBackgroundPrimary() -> some View {
        self.modifier(SemanticBackgroundModifier(semantic: .primary))
    }

    /// Apply secondary background color (panels, cards)
    func themedBackgroundSecondary() -> some View {
        self.modifier(SemanticBackgroundModifier(semantic: .secondary))
    }

    /// Apply tertiary background color (subtle backgrounds)
    func themedBackgroundTertiary() -> some View {
        self.modifier(SemanticBackgroundModifier(semantic: .tertiary))
    }

    // MARK: - Liquid Glass Effects

    /// Apply liquid glass effect with material blur
    /// Falls back to standard material on pre-iOS 26 devices
    @ViewBuilder
    func liquidGlassEffect(
        style: LiquidGlassStyle = .regular,
        tint: Color? = nil
    ) -> some View {
        if let tintColor = tint {
            self.background(style.material)
                .background(tintColor)
        } else {
            self.background(style.material)
        }
    }

    /// Conditional modifier helper
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - View Modifiers

/// Semantic background types
enum SemanticBackground {
    case primary    // Main app background
    case secondary  // Panels, sidebars
    case tertiary   // Subtle backgrounds
}

/// Automatically applies correct background color based on current theme
struct SemanticBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean

    let semantic: SemanticBackground

    func body(content: Content) -> some View {
        // All themes use solid colors - glass materials provide the visual effect
        content.background(backgroundColor)
    }

    private var backgroundColor: Color {
        // Determine which color set to use
        let isOcean = themeMode == .ocean
        let isDark = !isOcean && colorScheme == .dark

        switch semantic {
        case .primary:
            if isOcean { return Theme.Ocean.bgPrimary }
            if isDark { return Theme.Dark.bgPrimary }
            return Theme.bgPrimary

        case .secondary:
            if isOcean { return Theme.Ocean.bgSecondary }
            if isDark { return Theme.Dark.bgSecondary }
            return Theme.bgSecondary

        case .tertiary:
            if isOcean { return Theme.Ocean.bgTertiary }
            if isDark { return Theme.Dark.bgTertiary }
            return Theme.bgTertiary
        }
    }
}

struct ThemedBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let lightColor: Color
    let darkColor: Color
    let oceanColor: Color?

    func body(content: Content) -> some View {
        let bgColor: Color = {
            if themeMode == "ocean", let ocean = oceanColor {
                return ocean
            }
            return colorScheme == .dark ? darkColor : lightColor
        }()
        content.background(bgColor)
    }
}

struct ThemedForegroundModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let lightColor: Color
    let darkColor: Color
    let oceanColor: Color?

    func body(content: Content) -> some View {
        let fgColor: Color = {
            if themeMode == "ocean", let ocean = oceanColor {
                return ocean
            }
            return colorScheme == .dark ? darkColor : lightColor
        }()
        content.foregroundColor(fgColor)
    }
}

struct ThemedBorderModifier: ViewModifier {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"
    let lightColor: Color
    let darkColor: Color
    let oceanColor: Color?
    let width: CGFloat

    func body(content: Content) -> some View {
        let borderColor: Color = {
            if themeMode == "ocean", let ocean = oceanColor {
                return ocean
            }
            return colorScheme == .dark ? darkColor : lightColor
        }()
        content.overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMedium)
                .stroke(borderColor, lineWidth: width)
        )
    }
}

// MARK: - UIColor Extensions

#if canImport(UIKit)
import UIKit
extension UIColor {
    convenience init(_ swiftUIColor: Color) {
        // Convert SwiftUI Color to UIColor
        // This works by creating a UIColor from the Color's resolved values
        if let components = swiftUIColor.cgColor?.components, components.count >= 3 {
            self.init(red: components[0], green: components[1], blue: components[2], alpha: components.count > 3 ? components[3] : 1.0)
        } else {
            self.init(white: 0.5, alpha: 1.0)
        }
    }
}
#endif

// MARK: - Liquid Glass Style

/// Glass effect styles for liquid glass theme
enum LiquidGlassStyle {
    case ultraThin  // Most transparent, minimal blur
    case thin       // Light blur for subtle glass
    case regular    // Standard glass effect
    case thick      // Heavy blur for prominent glass
    case prominent  // Maximum blur for modals/overlays

    var material: Material {
        switch self {
        case .ultraThin: return .ultraThinMaterial
        case .thin: return .thinMaterial
        case .regular: return .regularMaterial
        case .thick: return .thickMaterial
        case .prominent: return .thickMaterial
        }
    }
}
