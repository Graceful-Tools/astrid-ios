import Foundation

/// The colours a list can be given, and the form one is stored in (AITD-500).
///
/// Mirrors astrid-web `lib/brand/colors.ts` (`LIST_COLOR_PALETTE`, `isListColor`): the palette is
/// the same eight in the same order, so a swatch ticked on one platform is ticked on the other,
/// and only `#rrggbb` is ever sent — the server refuses anything else.
enum ListColors {
    /// The choices offered, as web offers them.
    nonisolated static let palette = [
        "#ef4444", // red
        "#f97316", // orange
        "#eab308", // yellow
        "#22c55e", // green
        "#06b6d4", // cyan
        "#3b82f6", // blue
        "#8b5cf6", // violet
        "#ec4899", // pink
    ]

    /// Whether `value` may be stored as a list's colour: six-digit hex, nothing else.
    nonisolated static func isListColor(_ value: String) -> Bool {
        value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil
    }

    /// Whether a stored colour is one the palette does not offer, so the custom swatch owns it.
    nonisolated static func isCustom(_ stored: String) -> Bool {
        !palette.contains(stored.lowercased())
    }

    /// What picking `next` stores, or nil when there is nothing to save: the colour the list
    /// already has, or one the server would refuse.
    nonisolated static func change(from stored: String, to next: String) -> String? {
        guard isListColor(next), next.lowercased() != stored.lowercased() else { return nil }
        return next.lowercased()
    }

    /// sRGB components as a storable colour. Clamped: a wide-gamut pick resolves outside 0…1.
    nonisolated static func hex(red: Double, green: Double, blue: Double) -> String {
        func byte(_ component: Double) -> Int { Int((min(max(component, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}
