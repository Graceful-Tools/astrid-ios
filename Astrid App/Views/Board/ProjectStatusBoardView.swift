import SwiftUI
import UniformTypeIdentifiers

/// Renders a project's status board: virtual Inbox + real status lists +
/// virtual Done. Columns are full-screen-wide and snap one at a time
/// (paging) — cards drag-drop between columns via SwiftUI's Transferable
/// API. Mirrors `components/project-status-board.tsx` on the web.
///
/// The view observes the canonical singletons (TaskService, ListService,
/// ProjectService) so it stays in sync with the rest of the app and
/// supports offline cache hydration.
struct ProjectStatusBoardView: View {
    /// The project being rendered. Identified by id alone so the board
    /// can render before the Project model has been pulled from
    /// /api/v1/projects — status lists already live on ListService.lists
    /// keyed by projectId, so that's the only thing the column derivation
    /// needs.
    let projectId: String

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var dropError: String? = nil
    /// Tracks the currently-snapped column for haptic feedback on change.
    @State private var visibleColumnId: String?

    private var columns: [ProjectBoardColumn] {
        getProjectBoardColumns(listService.lists, projectId: projectId)
    }

    private var domainTasks: [Task] {
        getProjectDomainTasks(taskService.tasks, lists: listService.lists, projectId: projectId)
    }

    private func tasksFor(_ column: ProjectBoardColumn) -> [Task] {
        domainTasks.filter { task in
            getTaskProjectColumnId(task, projectId: projectId, lists: listService.lists) == column.id
        }
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(columns) { column in
                        BoardColumnView(
                            column: column,
                            tasks: tasksFor(column),
                            onDrop: { taskId in handleDrop(taskId: taskId, into: column) }
                        )
                        .frame(width: geo.size.width)
                        .id(column.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $visibleColumnId)
            .onAppear {
                // Default to virtual Inbox when the board first appears
                // so the user doesn't start mid-board.
                if visibleColumnId == nil {
                    visibleColumnId = columns.first?.id
                }
            }
            .onChange(of: visibleColumnId) { _, newId in
                // Light haptic on snap-into-place — mirrors the sidebar's
                // open/close haptic so the board feels native to the app.
                guard newId != nil else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .alert("Couldn't move task", isPresented: .constant(dropError != nil), presenting: dropError) { _ in
            Button("OK") { dropError = nil }
        } message: { error in
            Text(error)
        }
    }

    private func handleDrop(taskId: String, into column: ProjectBoardColumn) {
        guard let task = taskService.tasks.first(where: { $0.id == taskId }) else { return }
        let move = resolveProjectColumnMove(
            task,
            targetColumn: column,
            projectId: projectId,
            lists: listService.lists
        )
        _Concurrency.Task {
            do {
                _ = try await taskService.updateTask(
                    taskId: task.id,
                    completed: move.completed,
                    listIds: move.listIds
                )
            } catch {
                await MainActor.run {
                    self.dropError = error.localizedDescription
                }
            }
        }
    }
}
