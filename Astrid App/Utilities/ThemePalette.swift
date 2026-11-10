import SwiftUI

// One palette per theme (register DS8, AITD-611).
//
// iOS used to read fixed light values from `Theme` and pick the dark one with a
// `colorScheme == .dark ? Theme.Dark.x : Theme.x` ternary at each use — about 625 of them. A
// ternary has two arms, so Ocean always rendered with light's text and borders, and core's Ocean
// contrast fix (DS1) never reached iOS. The Mac resolves a whole `AstridTokens.Palette` from the
// selected theme instead; this is the same resolution for iOS, done once per view.
//
// In a view:
//
//     @ThemedPalette private var palette
//     ...
//     .foregroundColor(palette.textPrimary)
//
// Views move over one at a time; each move lowers the `darkSchemeTernaries` design budget.

extension AstridTokens {
    /// The palette for a theme. `auto` follows the system appearance; every other mode is fixed,
    /// whatever the system says.
    static func palette(for mode: ThemeMode, colorScheme: ColorScheme) -> Palette {
        switch mode.resolved(for: colorScheme) {
        case .ocean: return ocean
        case .dark:  return dark
        case .light, .auto: return light
        }
    }
}

/// The current theme's palette, read from the same `themeMode` setting and system appearance
/// the rest of the app uses. A dynamic property, so a theme change re-renders the view.
@propertyWrapper
struct ThemedPalette: DynamicProperty {
    @AppStorage("themeMode") private var themeMode: ThemeMode = .ocean
    @Environment(\.colorScheme) private var colorScheme

    init() {}

    var wrappedValue: AstridTokens.Palette {
        AstridTokens.palette(for: themeMode, colorScheme: colorScheme)
    }
}
