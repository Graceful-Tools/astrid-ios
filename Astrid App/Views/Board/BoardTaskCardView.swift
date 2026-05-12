import SwiftUI

/// A board card that reuses TaskRowView for visual parity with the list
/// view. The web version shares `TaskRowContent` between MainContent and
/// ProjectStatusBoard for the same reason. Wrapping in a card-shaped
/// container makes it visually distinct from a row in a flat list.
struct BoardTaskCardView: View {
    let task: Task

    @StateObject private var taskService = TaskService.shared

    var body: some View {
        TaskRowView(
            task: task,
            onToggle: {
                _Concurrency.Task {
                    do {
                        _ = try await taskService.completeTask(
                            id: task.id,
                            completed: !task.completed,
                            task: task
                        )
                    } catch {
                        print("⚠️ [BoardTaskCardView] Toggle failed: \(error)")
                    }
                }
            },
            compactMode: true
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
