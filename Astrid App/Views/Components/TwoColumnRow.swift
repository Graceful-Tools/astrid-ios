import SwiftUI

/// Two-column row helper for task detail fields
/// Label on the left, content on the right
/// Uses standard label width for all iPad orientations since portrait has 72% detail panel
struct TwoColumnRow<Content: View>: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.verticalSizeClass) var verticalSizeClass
    let label: String
    /// When set, the row is identified by this SF Symbol INSTEAD of the label text (Task
    /// 42013da7). An icon column keeps every row's content starting at the same x — the thing the
    /// label was really doing — in 24pt rather than 80, and the word is redundant next to a
    /// calendar chip or a coloured priority chip anyway. The label stays as the accessibility name.
    var icon: String? = nil
    @ViewBuilder let content: () -> Content

    // The icon column is exactly as wide as the title row's CHECKBOX (34pt), and this row uses
    // the same 16pt horizontal padding and 12pt spacing as that row. So the icon lands centred
    // under the checkbox, and the content's left edge lands on the title field's left edge —
    // 16 + 34 + 12 = 62pt in both rows (42013da7). Changing one without the other breaks it.
    /// Computed, not stored: a generic type cannot hold a static stored property.
    static var iconColumnWidth: CGFloat { 34 }
    private var labelWidth: CGFloat { icon == nil ? 80 : Self.iconColumnWidth }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.spacing12) {
            Group {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .accessibilityLabel(Text(label))
                } else {
                    Text(label)
                        .font(Theme.Typography.body())
                }
            }
            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            // Centred for an icon (to sit under the checkbox), leading for a text label.
            .frame(width: labelWidth, alignment: icon == nil ? .leading : .center)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.spacing16)
        .padding(.vertical, Theme.spacing8)
    }
}

#Preview {
    VStack {
        TwoColumnRow(label: "Date") {
            Text("Today")
        }

        TwoColumnRow(label: "Priority") {
            Text("High")
        }
    }
}
