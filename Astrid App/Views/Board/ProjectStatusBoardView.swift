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

    /// Horizontal inset between the screen edge and each board column.
    /// Matches TaskRowView's `.padding(.horizontal, Theme.spacing16)` so
    /// the board column edges align with the list view's row edges.
    private let columnHorizontalInset: CGFloat = 16
    /// Top inset between the header chrome and the board's first row.
    /// Mirrors the implicit breathing room the list view gets between
    /// the header and the first task row.
    private let boardTopInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            // Each column is the available width minus 2× the horizontal
            // inset, so paging snaps to a fully-inset column with the
            // adjacent column peeking on neither side (it sits off-screen).
            let columnWidth = max(geo.size.width - (columnHorizontalInset * 2), 0)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: columnHorizontalInset * 2) {
                    ForEach(columns) { column in
                        BoardColumnView(
                            column: column,
                            tasks: tasksFor(column),
                            onDrop: { taskId in handleDrop(taskId: taskId, into: column) }
                        )
                        .frame(width: columnWidth)
                        .id(column.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.top, boardTopInset)
            }
            .contentMargins(.horizontal, columnHorizontalInset, for: .scrollContent)
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
