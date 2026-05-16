import SwiftUI

/// A board card that reuses TaskRowView for visual parity with the list
/// view. The web version shares `TaskRowContent` between MainContent and
/// ProjectStatusBoard for the same reason. Wrapping in a card-shaped
/// container makes it visually distinct from a row in a flat list.
///
/// The card draws the SINGLE card chrome (background + border).
/// TaskRowView is rendered with `embeddedInCard: true` so it doesn't
/// add its own background/border — previously the two nested borders
/// looked like a frame-within-a-frame and wasted horizontal space.
///
/// Important: this view is also used as the SwiftUI `.draggable` preview
/// (a transient view hierarchy outside the main tree). Storing a
/// `@StateObject` here crashes on iOS 17+ paged scroll containers because
/// the preview instantiation can't reconcile the state-object lifecycle.
/// We hit `TaskService.shared` directly inside the onToggle closure
/// instead — no observation is needed (the parent already observes).
struct BoardTaskCardView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let task: Task
    /// List ids the board context already conveys (the project's
    /// domain list + this column's status list) — filtered out of the
    /// row's chip set so cards don't show "iOS To-do / Doing" when
    /// the column header is "Doing" inside the iOS project's board.
    var hiddenListIds: Set<String> = []

    private var effectiveTheme: String {
        themeMode == "auto" ? (colorScheme == .dark ? "dark" : "light") : themeMode
    }

    /// Card fill. Dark mode uses the mid `bgSecondary` tier — darker
    /// than the board frame (`bgTertiary`) so the card recedes against
    /// the chrome, still above the deep `bgPrimary` interior well. The
    /// card's own separator stroke carries the edge definition.
    private var cardBackgroundColor: Color {
        switch effectiveTheme {
        case "ocean": return Color.white.opacity(0.8)
        case "dark":  return Theme.Dark.bgSecondary
        default:      return Theme.bgPrimary
        }
    }

    var body: some View {
        TaskRowView(
            task: task,
            onToggle: {
                _Concurrency.Task {
                    do {
                        _ = try await TaskService.shared.completeTask(
                            id: task.id,
                            completed: !task.completed,
                            task: task
                        )
                    } catch {
                        print("⚠️ [BoardTaskCardView] Toggle failed: \(error)")
                    }
                }
            },
            // Always wrap titles on board cards. The list view truncates
            // on iPad because the details side-panel shares the row, but
            // the board has no such layout constraint — let titles use
            // multiple lines when they need to.
            compactMode: false,
            hiddenListIds: hiddenListIds,
            // Suppress TaskRowView's own background/border so the card
            // shows a single border, not a nested pair.
            embeddedInCard: true
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(cardBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
