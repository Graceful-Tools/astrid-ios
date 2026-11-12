import SwiftUI

/// Theme system: every palette value, spacing step, radius and shadow is read from
/// `AstridTokens` — astrid-core's `design/tokens.json`, vendored (AITD-605, AITD-610). A value
/// that should differ changes in core first, never here and never in the vendored copy.
/// Brand colours stay `Brand.*` (the tokens themselves resolve the accent through `Brand`).
struct Theme {
    /// The light palette, which iOS uses for its fixed values and the Mac for its `light` mode.
    static let light = AstridTokens.light

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

    /// Where the mode is read from: the app's own defaults, except in a test that hands in a suite
    /// so it can switch themes without writing the developer's real `themeMode` (AITD-534).
    nonisolated(unsafe) private(set) static var modeDefaults: UserDefaults = .standard

    static func readMode(from defaults: UserDefaults) {
        modeDefaults = defaults
        _cachedMode = nil
    }

    static var currentThemeMode: String {
        if let m = _cachedMode { return m }
        let m = modeDefaults.string(forKey: "themeMode") ?? "ocean"
        _cachedMode = m
        if _modeObserver == nil {
            _modeObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
                _cachedMode = modeDefaults.string(forKey: "themeMode") ?? "ocean"
            }
        }
        return m
    }

    static func themed(light: Color, dark: Color, ocean: Color) -> Color {
        themed(mode: currentThemeMode, light: light, dark: dark, ocean: ocean)
    }

    /// The mapping itself, with the mode passed in (task f040f28e).
    ///
    /// **Why this is separate.** A test that wanted to check "Ocean's input differs from Dark's"
    /// had to write `themeMode` into `UserDefaults` and read a static back, which is flaky twice
    /// over. It mutates process-wide state that other test classes read while running in
    /// parallel — and, worse, `currentThemeMode` is CACHED and only invalidated by a
    /// `UserDefaults.didChangeNotification` observer, which is delivered asynchronously. So even
    /// with the suite to itself, "set the default, then immediately read the colour" can return
    /// the previous theme's value. The test was not wrong about the behaviour; it had no way to
    /// ask the question without a race.
    ///
    /// The mapping is a pure function of the mode, so it can just take one.
    static func themed(mode: String, light: Color, dark: Color, ocean: Color) -> Color {
        switch mode {
        case "dark":  return dark
        case "ocean": return ocean
        case "light": return light
        default:      // auto → follow the system appearance
            let isDark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? dark : light
        }
    }

    // MARK: - Background Colors
    static var bgPrimary: Color { themed(light: light.bgPrimary, dark: Dark.bgPrimary, ocean: Ocean.bgPrimary) }
    static var bgSecondary: Color { themed(light: light.bgSecondary, dark: Dark.bgSecondary, ocean: Ocean.bgSecondary) }
    static var bgTertiary: Color { themed(light: light.bgTertiary, dark: Dark.bgTertiary, ocean: Ocean.bgTertiary) }
    static var bgHover: Color { themed(light: light.bgHover, dark: Dark.bgHover, ocean: Ocean.bgHover) }
    static var bgActive: Color { themed(light: light.bgActive, dark: Dark.bgActive, ocean: Ocean.bgActive) }
    static var bgSelected: Color { themed(light: light.bgSelected, dark: Dark.bgSelected, ocean: Ocean.bgSelected) }
    static let bgSelectedBorder = light.bgSelectedBorder

    // MARK: - Border Colors
    static var border: Color { themed(light: light.border, dark: Dark.border, ocean: Ocean.border) }
    static var borderHover: Color { themed(light: light.borderHover, dark: Dark.borderHover, ocean: Ocean.borderHover) }
    static let borderFocus = light.borderFocus
    static let borderInput = light.borderInput

    // MARK: - Input Colors (themed like iOS: chrome silver on Ocean, black on Dark)
    static var inputBg: Color { themed(light: light.inputBg, dark: Dark.inputBg, ocean: Ocean.inputBg) }
    static var inputBorder: Color { themed(light: light.inputBorder, dark: Dark.inputBorder, ocean: Ocean.inputBorder) }

    // MARK: - Text Colors
    static var textPrimary: Color { themed(light: light.textPrimary, dark: Dark.textPrimary, ocean: Ocean.textPrimary) }
    static var textSecondary: Color { themed(light: light.textSecondary, dark: Dark.textSecondary, ocean: Ocean.textSecondary) }
    static var textMuted: Color { themed(light: light.textMuted, dark: Dark.textMuted, ocean: Ocean.textMuted) }
    static let textInverted = light.textInverted
    static var textSelected: Color { themed(light: light.textSelected, dark: Dark.textSelected, ocean: Ocean.textSelected) }
#else
    // MARK: - Background Colors

    static let bgPrimary = light.bgPrimary
    static let bgSecondary = light.bgSecondary
    static let bgTertiary = light.bgTertiary
    static let bgHover = light.bgHover
    static let bgActive = light.bgActive
    static let bgSelected = light.bgSelected
    static let bgSelectedBorder = light.bgSelectedBorder

    // MARK: - Border Colors

    static let border = light.border
    static let borderHover = light.borderHover
    static let borderFocus = light.borderFocus
    static let borderInput = light.borderInput

    // MARK: - Text Colors

    static let textPrimary = light.textPrimary
    static let textSecondary = light.textSecondary
    static let textMuted = light.textMuted
    static let textInverted = light.textInverted
    static let textSelected = light.textSelected
#endif

    // MARK: - Interactive Colors

    // The accent is the BRAND colour, so it comes from Brand rather than being written
    // out per theme variant (task 97208a72). Theme abstracts light vs dark vs ocean; it
    // must also abstract *whose* blue, or a partner theme is a find-and-replace.
    static let accent = light.accent
    static let accentHover = light.accentHover
    static let accentText = light.accentText

    // MARK: - Status Colors

    // The fills: a badge, a dot, a button background. Text and icons read the inks below.
    static let success = light.success
    static let warning = light.warning
    static let error = light.error
    static let info = light.info

    // MARK: - Inks (core DS25, AITD-615)

    // A meaning as text or an icon — a link, error copy, a status glyph. The fills above are
    // under 4.5:1 as text on a card; each ink is held to it on the theme's surfaces and on
    // its own wash. On the Mac they follow the selected theme; on iOS a view that themes
    // itself reads `Theme.Dark.*Ink` / `Theme.Ocean.*Ink` like any other token.
#if os(macOS)
    static var accentInk: Color { themed(light: light.accentInk, dark: Dark.accentInk, ocean: Ocean.accentInk) }
    static var errorInk: Color { themed(light: light.errorInk, dark: Dark.errorInk, ocean: Ocean.errorInk) }
    static var successInk: Color { themed(light: light.successInk, dark: Dark.successInk, ocean: Ocean.successInk) }
    static var warningInk: Color { themed(light: light.warningInk, dark: Dark.warningInk, ocean: Ocean.warningInk) }
    static var infoInk: Color { themed(light: light.infoInk, dark: Dark.infoInk, ocean: Ocean.infoInk) }
#else
    static let accentInk = light.accentInk
    static let errorInk = light.errorInk
    static let successInk = light.successInk
    static let warningInk = light.warningInk
    static let infoInk = light.infoInk
#endif

    // MARK: - Priority Colors (matching web app exactly)

    static let priorityNone = light.priorityNone
    static let priorityLow = light.priorityLow
    static let priorityMedium = light.priorityMedium
    static let priorityHigh = light.priorityHigh

    // MARK: - Component Specific Colors

    static let headerBg = light.headerBg
    static let headerBorder = light.headerBorder

#if !os(macOS)
    static let inputBg = light.inputBg
    static let inputBorder = light.inputBorder
#endif
    static let inputPlaceholder = light.inputPlaceholder

    static let buttonBg = light.buttonBg
    static let buttonHover = light.buttonHover
    static let buttonBorder = light.buttonBorder

    // MARK: - Spacing (matching web app patterns)

    static let spacing2 = AstridTokens.Space.s2
    static let spacing4 = AstridTokens.Space.s4
    static let spacing8 = AstridTokens.Space.s8
    static let spacing12 = AstridTokens.Space.s12
    static let spacing16 = AstridTokens.Space.s16
    static let spacing20 = AstridTokens.Space.s20
    static let spacing24 = AstridTokens.Space.s24
    static let spacing32 = AstridTokens.Space.s32
    static let spacing40 = AstridTokens.Space.s40
    static let spacing48 = AstridTokens.Space.s48

    // MARK: - Corner Radius (matching web app)

    static let radiusSmall = AstridTokens.Radius.sm
    static let radiusMedium = AstridTokens.Radius.md
    static let radiusLarge = AstridTokens.Radius.lg
    static let radiusXLarge = AstridTokens.Radius.xl

    // MARK: - Shadows

    static let shadowSmall = AstridTokens.Shadow.sm
    static let shadowMedium = AstridTokens.Shadow.md
    static let shadowLarge = AstridTokens.Shadow.lg

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
        static let bgPrimary = AstridTokens.dark.bgPrimary
        static let bgSecondary = AstridTokens.dark.bgSecondary
        static let bgTertiary = AstridTokens.dark.bgTertiary
        static let bgHover = AstridTokens.dark.bgHover
        static let bgActive = AstridTokens.dark.bgActive
        static let bgSelected = AstridTokens.dark.bgSelected
        static let bgSelectedBorder = AstridTokens.dark.bgSelectedBorder

        // Border colors
        static let border = AstridTokens.dark.border
        static let borderHover = AstridTokens.dark.borderHover
        static let borderFocus = AstridTokens.dark.borderFocus
        static let borderInput = AstridTokens.dark.borderInput

        // Text colors
        static let textPrimary = AstridTokens.dark.textPrimary
        static let textSecondary = AstridTokens.dark.textSecondary
        static let textMuted = AstridTokens.dark.textMuted
        static let textInverted = AstridTokens.dark.textInverted
        static let textSelected = AstridTokens.dark.textSelected

        // Interactive colors (same as light)
        static let accent = AstridTokens.dark.accent
        static let accentHover = AstridTokens.dark.accentHover
        static let accentText = AstridTokens.dark.accentText
        static let accentInk = AstridTokens.dark.accentInk
        static let errorInk = AstridTokens.dark.errorInk
        static let successInk = AstridTokens.dark.successInk
        static let warningInk = AstridTokens.dark.warningInk
        static let infoInk = AstridTokens.dark.infoInk

        // Component colors
        static let headerBg = AstridTokens.dark.headerBg
        static let headerBorder = AstridTokens.dark.headerBorder

        static let inputBg = AstridTokens.dark.inputBg
        static let inputBorder = AstridTokens.dark.inputBorder
        static let inputPlaceholder = AstridTokens.dark.inputPlaceholder

        static let buttonBg = AstridTokens.dark.buttonBg
        static let buttonHover = AstridTokens.dark.buttonHover
        static let buttonBorder = AstridTokens.dark.buttonBorder
    }

    struct Ocean {
        // Background colors - Cyan ocean background (#88DCF8) - same as light except primary
        static let bgPrimary = AstridTokens.ocean.bgPrimary
        static let bgSecondary = AstridTokens.ocean.bgSecondary
        static let bgTertiary = AstridTokens.ocean.bgTertiary
        static let bgHover = AstridTokens.ocean.bgHover
        static let bgActive = AstridTokens.ocean.bgActive
        static let bgSelected = AstridTokens.ocean.bgSelected
        static let bgSelectedBorder = AstridTokens.ocean.bgSelectedBorder

        // Border colors - Cyan-tinted for Ocean theme
        static let border = AstridTokens.ocean.border
        static let borderHover = AstridTokens.ocean.borderHover
        static let borderFocus = AstridTokens.ocean.borderFocus
        static let borderInput = AstridTokens.ocean.borderInput

        // Text colors — darker than light's: grey on cyan measured 3.1:1 (register DS1, web AWTD-1496)
        static let textPrimary = AstridTokens.ocean.textPrimary
        static let textSecondary = AstridTokens.ocean.textSecondary
        static let textMuted = AstridTokens.ocean.textMuted
        static let textInverted = AstridTokens.ocean.textInverted
        static let textSelected = AstridTokens.ocean.textSelected

        // Interactive colors (same as light)
        static let accent = AstridTokens.ocean.accent
        static let accentHover = AstridTokens.ocean.accentHover
        static let accentText = AstridTokens.ocean.accentText
        static let accentInk = AstridTokens.ocean.accentInk
        static let errorInk = AstridTokens.ocean.errorInk
        static let successInk = AstridTokens.ocean.successInk
        static let warningInk = AstridTokens.ocean.warningInk
        static let infoInk = AstridTokens.ocean.infoInk

        // Component colors - Cyan headers (matching ocean background) and chrome inputs
        static let headerBg = AstridTokens.ocean.headerBg
        static let headerBorder = AstridTokens.ocean.headerBorder

        // Chrome/silver styling for inputs (metallic silver-gray)
        static let inputBg = AstridTokens.ocean.inputBg
        static let inputBorder = AstridTokens.ocean.inputBorder
        static let inputPlaceholder = AstridTokens.ocean.inputPlaceholder

        static let buttonBg = AstridTokens.ocean.buttonBg
        static let buttonHover = AstridTokens.ocean.buttonHover
        static let buttonBorder = AstridTokens.ocean.buttonBorder
    }

    struct LiquidGlass {
        // Only what is still read (AITD-623). The rest of this palette — text colours, status and
        // priority tints, three hard-coded background gradients — had no readers left.

        /// Ultra-thin glass for primary surfaces (most transparent)
        static let primaryGlassMaterial: Material = .ultraThinMaterial

        /// Thin glass for secondary surfaces (cards, panels)
        static let secondaryGlassMaterial: Material = .thinMaterial

        /// The accent behind a selected glass row. Follows the brand, so a partner's accent tints
        /// it rather than a fixed blue.
        static var accentGlassTint: Color { Brand.accentColor.opacity(0.25) }

        /// Subtle glass edge
        static let border = Color.white.opacity(0.15)
    }
}

// MARK: - Environment-aware theme access

extension View {
    // MARK: - Semantic Theme Helpers (automatically use correct theme)

    /// Apply primary background color (main app background)
    func themedBackgroundPrimary() -> some View {
        self.modifier(SemanticBackgroundModifier(semantic: .primary))
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
