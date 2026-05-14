import SwiftUI

/// A board card that reuses TaskRowView for visual parity with the list
/// view. The web version shares `TaskRowContent` between MainContent and
/// ProjectStatusBoard for the same reason. Wrapping in a card-shaped
/// container makes it visually distinct from a row in a flat list.
///
/// Important: this view is also used as the SwiftUI `.draggable` preview
/// (a transient view hierarchy outside the main tree). Storing a
/// `@StateObject` here crashes on iOS 17+ paged scroll containers because
/// the preview instantiation can't reconcile the state-object lifecycle.
/// We hit `TaskService.shared` directly inside the onToggle closure
/// instead — no observation is needed (the parent already observes).
struct BoardTaskCardView: View {
    let task: Task
    /// List ids the board context already conveys (the project's
    /// domain list + this column's status list) — filtered out of the
    /// row's chip set so cards don't show "iOS To-do / Doing" when
    /// the column header is "Doing" inside the iOS project's board.
    var hiddenListIds: Set<String> = []

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
            compactMode: true,
            hiddenListIds: hiddenListIds
        )
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}
