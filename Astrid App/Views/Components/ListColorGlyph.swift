import SwiftUI

// Shared with the Mac target (MacListIcon); ListImageView.swift is iOS-only.

/// A list's colour standing in for its image while list images are hidden (AITD-468): a `#`,
/// as web's sidebar draws it, or a dot where a glyph would be too small to read.
struct ListColorGlyph: View {
    let list: TaskList
    let size: CGFloat

    var body: some View {
        let color = Color(hex: list.displayColor) ?? Theme.accent
        switch ListImagesVisibility.Placeholder.forSize(size) {
        case .hash:
            Image(systemName: "number")
                .font(.system(size: size * 0.85, weight: .semibold))
                .foregroundColor(color)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        case .dot:
            Circle().fill(color)
        }
    }
}
