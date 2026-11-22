import SwiftUI

/// The fill behind a task — a list row and a board card alike (ADEV-194).
///
/// Both read astrid-core's `surface` token, and `surface-hover` when the task is the one open,
/// the same pair web's row and card use (`theme-surface` / `theme-surface-hover`). In dark that
/// is #1F2937 / #374151, which stands off the #111827 screen; the list row used `bgPrimary` and
/// sank into it. Ocean keeps its translucent card (0.8), solid when selected, so the open task
/// stands out against the water. Light keeps `surface` when selected — the card's accent stroke
/// already marks it, and the task asked for light and Ocean not to move.
enum TaskCardFill {
    /// Opacity of an unselected card on Ocean, whose background shows through.
    static let oceanUnselectedOpacity: Double = 0.8

    /// `theme` is the resolved name (`ThemeMode.resolvedName`): "light", "dark" or "ocean".
    static func color(theme: String, isSelected: Bool) -> Color {
        let palette = AstridTokens.themes[theme] ?? AstridTokens.light
        switch theme {
        case "ocean": return isSelected ? palette.surface : palette.surface.opacity(oceanUnselectedOpacity)
        case "dark":  return isSelected ? palette.surfaceHover : palette.surface
        default:      return palette.surface
        }
    }
}
