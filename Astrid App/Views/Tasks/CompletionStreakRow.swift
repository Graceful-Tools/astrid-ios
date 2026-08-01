import SwiftUI

/// A folded run of repeating-task completions, shown as one line (Task dd3fda86).
///
/// Tapping expands it to the individual completion dates and times — the run is summarised, not
/// discarded, so nothing that happened becomes unavailable.
struct CompletionStreakRow: View {
    let streak: CompletionStreak.Streak
    let colorScheme: ColorScheme

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing4) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: Theme.spacing8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.accent)
                    Text(CompletionStreak.summary(for: streak))
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11))
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(NSLocalizedString("comments.streak_expand_hint", comment: "")))

            if isExpanded {
                VStack(alignment: .leading, spacing: Theme.spacing4) {
                    ForEach(streak.dates, id: \.self) { date in
                        Text(date, format: .dateTime.month().day().hour().minute())
                            .font(Theme.Typography.caption2())
                            .foregroundColor(colorScheme == .dark ? Theme.Dark.textMuted : Theme.textMuted)
                    }
                }
                .padding(.leading, Theme.spacing24)
            }
        }
        .padding(.vertical, Theme.spacing4)
    }
}
