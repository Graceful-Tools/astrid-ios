import SwiftUI

/// Custom button style that provides press feedback without blocking scroll gestures
struct ListRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    /// Handed in by the row, which already resolves the theme (AITD-611).
    let palette: AstridTokens.Palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMedium)
                    .fill(
                        configuration.isPressed
                            ? palette.bgActive
                            : (isSelected
                                ? palette.bgSelected
                                : Color.clear)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: AstridTokens.Motion.pressDuration), value: configuration.isPressed)
    }
}

struct ListRowView: View {
    @Environment(\.colorScheme) var colorScheme
    @ThemedPalette private var palette
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

    /// The sidebar row for a list, by id — what the E2E journeys tap, in any language (AITD-528).
    static func accessibilityIdentifier(for listId: String) -> String { "sidebar.list.\(listId)" }

    var body: some View {
        // With somewhere to move this list (AITD-682), long-press opens a menu — Favorite plus
        // the core's project moves; without, long-press toggles Favorite as it always has.
        let choices = ListProjectControl.menuChoices(
            offered: ListProjectControl.isOffered,
            moves: listService.projectMoves(listId: list.id),
            projects: ProjectService.shared.projects)
        if choices.isEmpty {
            row.onLongPressGesture(minimumDuration: 0.5) {
                toggleFavorite()
            }
        } else {
            row
                .contextMenu {
                    Button(action: toggleFavorite) {
                        Label(NSLocalizedString(list.isFavorite == true ? "mac.remove_favorite" : "lists.favorite",
                                                comment: ""),
                              systemImage: list.isFavorite == true ? "star.slash" : "star")
                    }
                    ListProjectMenu(list: list)
                }
                // iPad: drag the row onto a sidebar project to move it there.
                .modifier(ListRowProjectDrag(listId: list.id,
                                             enabled: UIDevice.current.userInterfaceIdiom == .pad
                                                && list.isVirtual != true))
        }
    }

    private var row: some View {
        Button(action: {
            // Haptic feedback on tap
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()

            onTap()
        }) {
            // The icon is centred under the sidebar header's logo and the name starts under its
            // wordmark — where it already sat, give or take a point (AITD-502).
            HStack(spacing: SidebarBrandHeader.spacing) {
                // List image/icon
                ListImageView(list: list, size: 12)
                    .frame(width: SidebarBrandHeader.logoSize)

                // List name
                Text(list.name)
                    .font(Theme.Typography.body())
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Privacy indicator
                ListPrivacyGlyph(privacy: list.privacy)

                // Task count badge (always show, even when 0)
                if let count = taskCount {
                    Text("\(count)")
                        .font(Theme.Typography.callout())  // A step under the name (AITD-502)
                        .foregroundColor(palette.textSecondary)
                        .padding(.horizontal, Theme.spacing4)
                        .padding(.vertical, Theme.spacing4)
                        .background(
                            Capsule()
                                .fill(palette.bgTertiary)
                        )
                }
            }
            .padding(.vertical, Theme.spacing8)
            .padding(.trailing, Theme.spacing4)  // The count sits near the edge (AITD-502)
            .contentShape(Rectangle())  // Make entire row area tappable
        }
        .buttonStyle(ListRowButtonStyle(isSelected: isSelected, palette: palette))
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: list.id))
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
                AppLog.debug("✅ [ListRowView] Toggled favorite for list: \(list.name) to \(newFavoriteStatus)")
            } catch {
                AppLog.debug("❌ [ListRowView] Failed to toggle favorite: \(error)")
            }
        }
    }
}

/// A sidebar list row as a drag source for a project row (AITD-682); off, the row is unchanged.
private struct ListRowProjectDrag: ViewModifier {
    let listId: String
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.draggable(ProjectBoardListDrag.payload(listId: listId))
        } else {
            content
        }
    }
}

// Preview removed - use ListSidebarView preview instead
