import SwiftUI

/// Custom button style that provides press feedback without blocking scroll gestures
struct ListRowButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(
                        configuration.isPressed
                            ? (colorScheme == .dark ? Theme.Dark.bgTertiary.opacity(0.5) : Color.gray.opacity(0.2))
                            : (isSelected
                                ? (colorScheme == .dark ? Theme.Dark.bgTertiary : Color.blue.opacity(0.1))
                                : Color.clear)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ListRowView: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var listService = ListService.shared

    let list: TaskList
    let taskCount: Int?
    let isSelected: Bool
    let onTap: () -> Void

    init(list: TaskList, taskCount: Int? = nil, isSelected: Bool = false, onTap: @escaping () -> Void) {
        self.list = list
        self.taskCount = taskCount
        self.isSelected = isSelected
        self.onTap = onTap
    }

    var body: some View {
        Button(action: {
            // Haptic feedback on tap
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            onTap()
        }) {
            HStack(spacing: Theme.spacing12) {
                // List image/icon
                ListImageView(list: list, size: 12)

                // List name
                Text(list.name)
                    .font(Theme.Typography.body())
                    .foregroundColor(colorScheme == .dark ? Theme.Dark.textPrimary : Theme.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Privacy indicator
                if let privacy = list.privacy {
                    privacyIcon(privacy)
                }

                // Task count badge (always show, even when 0)
                if let count = taskCount {
                    Text("\(count)")
                        .font(Theme.Typography.caption1())
                        .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
                        .padding(.horizontal, Theme.spacing4)
                        .padding(.vertical, Theme.spacing4)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Color.gray.opacity(0.1))
                        )
                }
            }
            .padding(.vertical, Theme.spacing8)
            .padding(.horizontal, Theme.spacing12)
            .contentShape(Rectangle())  // Make entire row area tappable
        }
        .buttonStyle(ListRowButtonStyle(isSelected: isSelected))
        .onLongPressGesture(minimumDuration: 0.5) {
            toggleFavorite()
        }
    }

    @ViewBuilder
    private func privacyIcon(_ privacy: TaskList.Privacy) -> some View {
        Group {
            switch privacy {
            case .PUBLIC:
                Image(systemName: "globe")
                    .font(.caption)
                    .foregroundColor(Theme.accent)
            case .SHARED:
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            case .PRIVATE:
                EmptyView()
            }
        }
    }

    private func toggleFavorite() {
        // Haptic feedback - medium for long press action
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()

        // Toggle favorite status
        _Concurrency.Task {
            do {
                let newFavoriteStatus = !(list.isFavorite ?? false)
                _ = try await listService.favoriteList(listId: list.id, favorite: newFavoriteStatus)
                print("✅ [ListRowView] Toggled favorite for list: \(list.name) to \(newFavoriteStatus)")
            } catch {
                print("❌ [ListRowView] Failed to toggle favorite: \(error)")
            }
        }
    }
}

// Preview removed - use ListSidebarView preview instead
