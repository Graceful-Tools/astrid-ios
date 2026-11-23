import SwiftUI

/// SwiftUI's `.paging` and `.viewAligned` scroll-target behaviors are
/// different opaque types, so we can't switch between them via a
/// ternary. A small ViewModifier picks the right one at apply time.
///
/// `.alwaysByOne` is what makes ONE swipe move ONE column. Plain `.viewAligned`
/// snaps to whichever column edge the fling happens to land nearest, so on a
/// multi-column board a normal-length swipe often does not travel far enough to
/// reach the next edge and springs back to where it started — which reads as the
/// board ignoring you until you swipe several times.
private struct BoardScrollSnapModifier: ViewModifier {
    let multiColumn: Bool
    func body(content: Content) -> some View {
        if multiColumn {
            content.scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        } else {
            // Single column: the column IS the container width, so a page and a
            // column are the same distance and paging already moves exactly one.
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

    /// The list the board was opened from (ADEV-3). Its cards are the board's, its manual order
    /// and Done window arrange them, and a column's "+ Add task" files into it. nil only where the
    /// shell has no list of the project yet.
    var listId: String?

    /// Called when the user swipes left-to-right while on the left-most column —
    /// there's nothing further left to scroll to, so it opens the shell sidebar
    /// (matching a regular list). Provided by the parent (TaskListView.onMenuTap).
    var onOpenSidebar: (() -> Void)?

    /// How to open a tapped card: the details panel beside it on iPad, the push on iPhone
    /// (`BoardCardCallout.route`, AITD-679). nil falls back to the full-screen presenter.
    var onTaskTap: ((Task) -> Void)?

    /// The task currently shown in the side panel, if any. When set, the board
    /// snaps to the column that contains it so the user sees where it lives
    /// (e.g. opening a done task scrolls the board to the Done column).
    var selectedTaskId: String?

    /// What pulling a column down runs — the list's own refresh (AITD-670).
    var onRefresh: (() async -> Void)?

    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    @StateObject private var goalsService = ProjectGoalsService.shared
    /// The columns and their cards, as astrid-core draws them (AITD-461): asked off the main
    /// thread, re-asked when tasks, lists or projects change, the last answer kept on screen.
    @StateObject private var board = BoardModel()
    @State private var dropError: String? = nil
    /// The project's decisions, as a sheet (ADEV-189).
    @State private var showingDecisions = false
    /// Which card a tap opened the panel from — that card is already beside its panel, so the
    /// board does not scroll it anywhere (AITD-679).
    @Environment(\.selectedRowReporter) private var selectedRowReporter
    /// Tracks the currently-snapped column for haptic feedback on change.
    @State private var visibleColumnId: String?
    /// Whether the board has scrolled to its opening column yet (ADEV-212).
    @State private var opening = BoardOpening()

    // MARK: Edge auto-advance while dragging a card (task 233ec244)

    /// The edge zone a dragged card is currently sitting in, if any.
    @State private var autoAdvanceEdge: BoardAutoAdvanceEdge?
    /// Which column last reported the drag point. Columns hand off as the board
    /// scrolls under the finger, and the incoming column can report before the
    /// outgoing one reports its exit — so a "drag left" only counts from the
    /// column that currently owns the drag.
    @State private var dragReporterColumnId: String?
    @State private var autoAdvanceTask: _Concurrency.Task<Void, Never>?
    /// Global x where the current drag was first seen — the baseline for
    /// "meaningful movement". Nil when no drag is in flight.
    @State private var dragOriginX: CGFloat?
    /// Whether this stay in the current edge zone has already moved the board.
    /// One advance per entry; the drag must leave and re-enter for another.
    @State private var hasAdvancedForThisEntry = false

    /// What the core is asked for: the board's list, whose manual order and Done window arrange
    /// the cards, or the project alone when this client has no list of it yet.
    private var boardQuery: BoardModel.Query {
        BoardModel.Query(listId: projectDomainList?.id, projectId: projectId,
                         doneSince: doneSince.wireValue())
    }

    /// How far back Done goes — the period its header names (ADEV-131). Part of what the core is
    /// asked, so Done holds every card finished since it rather than the list's window (ADEV-140).
    @State private var doneSince: DoneSince = .default

    /// What `doneSince` is saved under: the board's list, else the project.
    private var doneSinceKey: String { projectDomainList?.id ?? projectId }

    private var columns: [ProjectBoardColumn] {
        board.columns.map(\.column)
    }

    /// The board's list: the one it was opened from (ADEV-3). It used to be the project's FIRST
    /// domain list, which stopped being the same thing once a project held several lists — the
    /// order, the Done window and every "+ Add task" went to whichever list came first.
    private var projectDomainList: TaskList? {
        Self.boardList(openedListId: listId, projectId: projectId, lists: listService.lists)
    }

    /// The opened list when it is a domain list of this project; otherwise the project's first
    /// domain list, for a shell that opened the board without one.
    static func boardList(openedListId: String?, projectId: String, lists: [TaskList]) -> TaskList? {
        if let openedListId,
           let opened = lists.first(where: { $0.id == openedListId }),
           opened.projectId == projectId, opened.isDomainList {
            return opened
        }
        return lists.first { $0.projectId == projectId && $0.isDomainList }
    }

    /// A column's cards: the core's ids, drawn from the service's own tasks. Subtasks are not
    /// cards and Done holds recent work only — the core's decisions (CONTRACTS D43).
    private func tasksFor(_ column: ProjectBoardColumn) -> [Task] {
        guard let answered = board.columns.first(where: { $0.id == column.id }) else { return [] }
        return BoardModel.cards(answered, in: taskService.tasksById)
    }

    /// Top inset between the header chrome and the board's first row.
    /// Mirrors the implicit breathing room the list view gets between
    /// the header and the first task row.
    private let boardTopInset: CGFloat = 8

    /// The open task and the column its card is in (ADEV-175).
    private var selectedSpot: BoardCardCallout.Spot? {
        guard let selectedTaskId, let columnId = board.columnId(of: selectedTaskId) else { return nil }
        return .init(taskId: selectedTaskId, columnId: columnId)
    }

    var body: some View {
        VStack {
        // The project's goals and guardrails, folded; nothing when it has none (ADEV-183). Its
        // decisions sit beside them, open with or without goals (ADEV-189).
        HStack(alignment: .firstTextBaseline) {
            if ProjectGoalsStrip.shows(goalsService.goals(projectId: projectId)) {
                ProjectGoalsStrip(projectId: projectId)
            }
            Spacer(minLength: Theme.spacing8)
            Button {
                showingDecisions = true
            } label: {
                Label(NSLocalizedString("project_decisions.title", comment: "Decisions"),
                      systemImage: "checklist")
                    .font(Theme.Typography.caption1())
            }
            .padding(.horizontal, Theme.spacing16)
            .padding(.vertical, Theme.spacing8)
            .accessibilityIdentifier("projectDecisions.open")
        }
        .sheet(isPresented: $showingDecisions) {
            ProjectDecisionsView(projectId: projectId)
        }
        GeometryReader { geo in
            // Phone-narrow widths: one full-screen paged column (existing
            // behavior). Wider iPad layouts: fan out to multiple columns
            // side-by-side. boardColumnsVisible is the testable helper.
            let columnsVisible = boardColumnsVisible(availableWidth: geo.size.width)
            let columnWidth = geo.size.width / CGFloat(columnsVisible)
            let multiColumn = columnsVisible > 1

            ScrollViewReader { proxy in
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
                            // A tap opens the details the way a row does: the panel beside
                            // the card on iPad, the push on iPhone (AITD-679).
                            onOpenCard: { task in
                                if let onTaskTap { onTaskTap(task) } else { TaskPresenter.shared.showTask(task) }
                            },
                            selectedTaskId: selectedTaskId,
                            onDragMoved: { globalPoint in
                                handleDragMoved(globalPoint,
                                                from: column.id,
                                                boardFrame: geo.frame(in: .global),
                                                proxy: proxy)
                            },
                            onRefresh: onRefresh,
                            doneSince: $doneSince
                        )
                        // Match the floating header's `.padding(.horizontal, 8)`
                        // so the column's border lines up under the header
                        // chrome's edges. In multi-column mode the same 8pt
                        // padding gives a uniform 16pt gutter between columns.
                        .padding(.horizontal, AstridTokens.Layout.Comfortable.boardColumnGap / 2)
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
            // When a task is open, the detail overlay covers the board's trailing
            // edge. Add trailing scroll room so ANY column — including the last
            // (Done) — can scroll fully into the visible area, letting the user
            // browse that column's tasks while the detail is shown.
            .contentMargins(.trailing,
                            selectedTaskId != nil ? max(0, geo.size.width - columnWidth) : 0,
                            for: .scrollContent)
            // Collapse the scroll room INSTANTLY on close — if it animated with the
            // container's panel slide, the scroll view would re-snap and the board
            // would flash/jump as the detail slides out.
            .animation(nil, value: selectedTaskId)
            // Open on Inbox, even with Waiting to its left (ADEV-128) — once the columns are
            // there: the core's first answer arrives after this appears, and a position set
            // before its column exists is never scrolled to (ADEV-212). Imperative, because the
            // binding no-ops when it already holds that id.
            .onChange(of: columns.map(\.id), initial: true) { _, _ in
                guard let id = opening.columnToOpen(columns: columns, multiColumn: multiColumn) else { return }
                visibleColumnId = id
                proxy.scrollTo(id, anchor: .leading)
            }
            .task(id: doneSinceKey) {
                doneSince = DoneSince.load(listId: doneSinceKey, userId: AuthManager.shared.userId)
            }
            .onChange(of: doneSince) { _, since in
                since.save(listId: doneSinceKey, userId: AuthManager.shared.userId)
            }
            .task(id: boardQuery) { board.update(boardQuery) }
            .onDisappear {
                // A drag can be interrupted by navigation; don't leave a pending
                // advance to scroll a board nobody is looking at.
                endDrag()
            }
            .onChange(of: visibleColumnId) { _, newId in
                // Light haptic on snap-into-place — mirrors the sidebar's
                // open/close haptic so the board feels native to the app.
                guard newId != nil else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            // When a task opens in the side panel, scroll the board to the column
            // that holds it so the user sees its context.
            .onChange(of: selectedTaskId) { _, newId in
                guard let newId, let columnId = board.columnId(of: newId) else { return }
                // A tapped card is already on screen, and the panel opened on the side away from
                // it; scrolling its column to the leading edge could put it under that panel.
                if selectedRowReporter?.openedCard?.taskId == newId { return }
                // Scroll imperatively every time. The scrollPosition binding no-ops
                // when the target column is unchanged (e.g. tapping a second task in
                // the same Done column), which left that column stuck under the
                // overlay. scrollTo always re-scrolls, so it behaves the same on the
                // first tap and every tap after.
                withAnimation(ReducedMotion.standardSpring()) {
                    proxy.scrollTo(columnId, anchor: .leading)
                }
            }
            // The open card moved column — completed into Done, marked to-do out of it: scroll
            // the column it went to into view on the side it was opened on, clear of the panel,
            // then dock the panel beside it there so the arrow points at it (ADEV-175).
            .onChange(of: selectedSpot) { old, new in
                guard let moved = BoardCardCallout.moved(from: old, to: new) else { return }
                let edge = BoardCardCallout.scrollEdge(openedCard: selectedRowReporter?.openedCard?.frame,
                                                       board: geo.frame(in: .global))
                withAnimation(ReducedMotion.standardSpring(), completionCriteria: .logicallyComplete) {
                    proxy.scrollTo(moved.columnId, anchor: edge == .leading ? .leading : .trailing)
                } completion: {
                    selectedRowReporter?.reanchorOpenedCard(taskId: moved.taskId)
                }
            }
            // At the left-most column a left-to-right swipe can't scroll further,
            // so let it open the sidebar (the carousel still owns pans elsewhere).
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        let atLeftmost = visibleColumnId == columns.first?.id
                            || (visibleColumnId == nil)  // no columns yet, so nothing to its left
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
            } // ScrollViewReader
        }
        }
        .task(id: projectId) { await goalsService.load(projectId: projectId) }
        .alert("Couldn't move task", isPresented: .constant(dropError != nil), presenting: dropError) { _ in
            Button("OK") { dropError = nil }
        } message: { error in
            Text(error)
        }
    }

    // MARK: - Edge auto-advance (tasks 233ec244, 84595f3c)

    /// A dragged card reported a new position (or left the board entirely).
    ///
    /// On iPhone one column fills the screen, so the column you want is almost
    /// never visible when you pick a card up — and the drag session owns the
    /// gesture, so the carousel's swipe can't help. A deliberate sideways drag
    /// moves the board one column instead.
    private func handleDragMoved(_ globalPoint: CGPoint?,
                                 from columnId: String,
                                 boardFrame: CGRect,
                                 proxy: ScrollViewProxy) {
        guard let globalPoint else {
            // Only the column that currently owns the drag may end it — the
            // incoming column can report before the outgoing one exits.
            if dragReporterColumnId == columnId { endDrag() }
            return
        }
        dragReporterColumnId = columnId

        // Where the card was picked up, against which "meaningful movement" is
        // measured. Set once per drag and cleared when it ends.
        let originX = dragOriginX ?? globalPoint.x
        if dragOriginX == nil { dragOriginX = originX }

        let edge = boardAutoAdvanceEdge(dragX: globalPoint.x - boardFrame.minX,
                                        containerWidth: boardFrame.width)

        // Leaving the zone re-arms it: the next entry may advance again. This is
        // what keeps a multi-column move to one gesture per column instead of a
        // single entry walking the whole board (task 84595f3c).
        if edge != autoAdvanceEdge {
            autoAdvanceEdge = edge
            hasAdvancedForThisEntry = false
            autoAdvanceTask?.cancel()
            autoAdvanceTask = nil
        }

        guard boardShouldAutoAdvance(edge: edge,
                                     travelSincePickup: globalPoint.x - originX,
                                     hasFiredForThisEntry: hasAdvancedForThisEntry),
              let edge,
              autoAdvanceTask == nil
        else { return }

        // Dwell is a debounce on this ONE advance, not a repeat interval.
        autoAdvanceTask = _Concurrency.Task { @MainActor in
            try? await _Concurrency.Task.sleep(
                nanoseconds: UInt64(boardAutoAdvanceDwell * 1_000_000_000))
            guard !_Concurrency.Task.isCancelled else { return }

            let snapshot = columns
            guard let currentIndex = snapshot.firstIndex(where: { $0.id == visibleColumnId }),
                  let targetIndex = boardAutoAdvanceTarget(currentIndex: currentIndex,
                                                           edge: edge,
                                                           columnCount: snapshot.count)
            else { return }  // at the end of the board — stop, don't wrap

            hasAdvancedForThisEntry = true
            withAnimation(ReducedMotion.standardSpring()) {
                proxy.scrollTo(snapshot[targetIndex].id, anchor: .leading)
            }
            // Keep the snap binding in step; its onChange supplies the haptic.
            visibleColumnId = snapshot[targetIndex].id
        }
    }

    /// The drag ended (dropped, or left the board). Clear everything so the next
    /// pickup starts from a clean baseline.
    private func endDrag() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        autoAdvanceEdge = nil
        dragReporterColumnId = nil
        dragOriginX = nil
        hasAdvancedForThisEntry = false
    }

    private func handleDrop(payload: BoardCardPayload,
                            into column: ProjectBoardColumn,
                            at targetIndex: Int) {
        guard let task = taskService.tasksById[payload.taskId],
              let domainList = projectDomainList else { return }

        // Light haptic to confirm the drop registered.
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // The move and the card's new place in the list's manual order, in one core command
        // (AITD-461): completion first through the completion service (a repeating card dropped
        // on Done rolls forward — ASTRID.md rule 2), then the column, then the order, with the
        // list's sort set to manual so the order shows.
        // Into Waiting, the core may ask what the task waits for (AITD-631): the presenter shows
        // the prompt and drops the card again with the answer; Cancel leaves it where it was.
        _Concurrency.Task {
            do {
                try await WaitingPromptPresenter.shared.move(task) { wait in
                    try await taskService.dropOnBoard(taskId: payload.taskId, columnId: column.id,
                                                      listId: domainList.id, index: targetIndex, wait: wait)
                }
            } catch {
                await MainActor.run {
                    self.dropError = error.localizedDescription
                }
            }
        }
    }

}
