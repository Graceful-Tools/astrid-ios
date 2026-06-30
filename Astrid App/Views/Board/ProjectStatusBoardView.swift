import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI's `.paging` and `.viewAligned` scroll-target behaviors are
/// different opaque types, so we can't switch between them via a
/// ternary. A small ViewModifier picks the right one at apply time.
private struct BoardScrollSnapModifier: ViewModifier {
    let multiColumn: Bool
    func body(content: Content) -> some View {
        if multiColumn {
            content.scrollTargetBehavior(.viewAligned)
        } else {
            content.scrollTargetBehavior(.paging)
        }
    }
}

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

    /// Called when the user swipes left-to-right while on the left-most column —
    /// there's nothing further left to scroll to, so it opens the shell sidebar
    /// (matching a regular list). Provided by the parent (TaskListView.onMenuTap).
    var onOpenSidebar: (() -> Void)?

    /// How to open a tapped task. iPad supplies this to use its side panel so the
    /// board stays visible in the left column; nil falls back to the full-screen
    /// presenter (iPhone).
    var onTaskTap: ((Task) -> Void)?

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @State private var dropError: String? = nil
    /// Tracks the currently-snapped column for haptic feedback on change.
    @State private var visibleColumnId: String?

    private var columns: [ProjectBoardColumn] {
        getProjectBoardColumns(listService.lists)
    }

    /// The project's regular (domain) list. Cached lookup so the per-
    /// column "+ Add task" footer can drop new tasks into the right list.
    /// Returns nil for projects with no regular list attached yet (very
    /// rare — should only happen for an unfinished migration).
    private var projectDomainList: TaskList? {
        listService.lists.first { $0.projectId == projectId && $0.listType != "status" }
    }

    private var domainTasks: [Task] {
        getProjectDomainTasks(taskService.tasks, lists: listService.lists, projectId: projectId)
    }

    private func tasksFor(_ column: ProjectBoardColumn) -> [Task] {
        boardColumnTasksSorted(
            domainTasks,
            projectId: projectId,
            column: column,
            lists: listService.lists,
            manualOrder: projectDomainList?.manualSortOrder,
            recentlyCompletedWindow: projectDomainList?.recentlyCompletedWindow,
            completionFilter: projectDomainList?.filterCompletion
        )
    }

    /// Top inset between the header chrome and the board's first row.
    /// Mirrors the implicit breathing room the list view gets between
    /// the header and the first task row.
    private let boardTopInset: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            // Phone-narrow widths: one full-screen paged column (existing
            // behavior). Wider iPad layouts: fan out to multiple columns
            // side-by-side. boardColumnsVisible is the testable helper.
            let columnsVisible = boardColumnsVisible(availableWidth: geo.size.width)
            let columnWidth = geo.size.width / CGFloat(columnsVisible)
            let multiColumn = columnsVisible > 1

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 0) {
                    ForEach(columns) { column in
                        BoardColumnView(
                            column: column,
                            tasks: tasksFor(column),
                            selectedList: projectDomainList,
                            onDropAt: { payload, index in
                                handleDrop(payload: payload, into: column, at: index)
                            },
                            onTaskTap: onTaskTap
                        )
                        // Match the floating header's `.padding(.horizontal, 8)`
                        // so the column's border lines up under the header
                        // chrome's edges. In multi-column mode the same 8pt
                        // padding gives a uniform 16pt gutter between columns.
                        .padding(.horizontal, 8)
                        .frame(width: columnWidth)
                        .id(column.id)
                    }
                }
                .scrollTargetLayout()
                .padding(.top, boardTopInset)
            }
            // Phone: full-page paging snap. iPad multi-column: snap to
            // each column's leading edge (.viewAligned) so a swipe-right
            // reveals one more column at a time, not a full screen.
            .modifier(BoardScrollSnapModifier(multiColumn: multiColumn))
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
            // At the left-most column a left-to-right swipe can't scroll further,
            // so let it open the sidebar (the carousel still owns pans elsewhere).
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let atLeftmost = visibleColumnId == columns.first?.id
                            || (visibleColumnId == nil)  // not yet snapped → defaults to Inbox
                        let decision = BoardSidebarSwipeState(
                            // Fire whenever there's a sidebar this swipe can open
                            // (a drawer): iPhone, and iPad portrait / 2-column. In
                            // iPad 3-column landscape onOpenSidebar is nil (sidebar
                            // is permanent), so the swipe stays inert there.
                            isMobile: onOpenSidebar != nil,
                            isAtLeftmostColumn: atLeftmost,
                            translationWidth: value.translation.width,
                            translationHeight: value.translation.height,
                            predictedEndTranslationWidth: value.predictedEndTranslation.width
                        )
                        if shouldBoardSwipeOpenSidebar(decision) {
                            onOpenSidebar?()
                        }
                    }
            )
        }
        .alert("Couldn't move task", isPresented: .constant(dropError != nil), presenting: dropError) { _ in
            Button("OK") { dropError = nil }
        } message: { error in
            Text(error)
        }
    }

    private func handleDrop(payload: BoardCardPayload,
                            into column: ProjectBoardColumn,
                            at targetIndex: Int) {
        let taskId = payload.taskId
        guard let task = taskService.tasks.first(where: { $0.id == taskId }) else {
            print("⚠️ [Board] Drop received for unknown task id=\(taskId)")
            return
        }
        guard let domainList = projectDomainList else {
            print("⚠️ [Board] No regular project list found — drop ignored")
            return
        }

        // Compute the new task state AND the new manual sort order so a
        // drop at index N lands the card at that visual position.
        let reorder = resolveBoardReorder(
            task: task,
            targetColumn: column,
            targetIndex: targetIndex,
            projectId: projectId,
            lists: listService.lists,
            allTasks: taskService.tasks,
            currentManualOrder: domainList.manualSortOrder ?? [],
            recentlyCompletedWindow: domainList.recentlyCompletedWindow,
            completionFilter: domainList.filterCompletion
        )

        // Light haptic to confirm the drop registered.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        _Concurrency.Task {
            do {
                // Persist the task move first so list-membership / completion
                // is correct before the order is interpreted.
                _ = try await taskService.updateTask(
                    taskId: task.id,
                    completed: reorder.completed,
                    listIds: reorder.listIds
                )
                // Then persist the new manualSortOrder on the project's
                // domain list so the order survives across launches.
                // We also auto-set the list's sortBy to "manual" if it
                // wasn't already, so the rendering respects the order.
                var listUpdate = UpdateListRequest()
                listUpdate.manualSortOrder = reorder.newManualOrder
                if domainList.sortBy != "manual" {
                    listUpdate.sortBy = "manual"
                }
                _ = try await ListService.shared.updateListOnServer(
                    listId: domainList.id,
                    updates: listUpdate
                )
                print("✅ [Board] Moved task=\(task.id) → \(column.id)@\(targetIndex)")
            } catch {
                print("❌ [Board] Move failed for task=\(task.id): \(error)")
                await MainActor.run {
                    self.dropError = error.localizedDescription
                }
            }
        }
    }

}
