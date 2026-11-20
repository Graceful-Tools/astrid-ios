//  MacBoardView.swift
//  Astrid for Mac — project-status board (Task 196d482a). Columns and cards are astrid-core's
//  `board`, through the shared `BoardModel` (AITD-461): the board iOS draws — top-level cards in
//  the list's manual order, Done holding recent work. Cards drag between columns via
//  Transferable and move through the core's `moveTaskToColumn`.

#if os(macOS)
import SwiftUI

struct MacBoardView: View {
    let listId: String
    /// The task whose details pop-out is open, for the card's selection outline.
    var selectedTaskId: String?
    /// A card was clicked: open its details the way a list row does — the pop-out, docked on the
    /// side of the card with more room (AITD-679). The frame is the card's, in the global space;
    /// nil when there is no card to stand beside (a card just added).
    var onOpenCard: (String, CGRect?) -> Void = { _, _ in }
    /// Draw this list as its row of a project's board: the project's columns, the list's cards
    /// (core `projectBoardRow`, D67). Nil is the list's own board (ADEV-59).
    var rowOfProjectId: String? = nil
    /// A fixed height for the columns — a project board's row shows three or four cards and
    /// scrolls inside each column. Nil fills the window, as the list's own board does (ADEV-59).
    var columnHeight: CGFloat? = nil
    @AppStorage(MacScrollBars.defaultsKey) private var showScrollBars = false
    @StateObject private var taskService = TaskService.shared
    @StateObject private var listService = ListService.shared
    /// The columns and their cards, as astrid-core draws them — iOS's board (AITD-461).
    @StateObject private var board = BoardModel()
    @StateObject private var appModel = MacAppModel.shared
    @State private var dropTargetColumnId: String?
    /// Shared with the detail panel and its header toggle, so "full screen" means one
    /// thing app-wide (7017c3c1).
    @AppStorage("macDetailFullScreen") private var detailFullScreen = false
    @State private var hoveredCardId: String?    // Mac hover affordance (77225941)
    @StateObject private var memberService = ListMemberService.shared
    /// The cached hi-fi empathy frame for an empty column (ADEV-127).
    @ObservedObject private var empathyArt = EmpathyArtService.shared
    /// Priority being picked on a card, before the save lands (task 9be8cb1b).
    ///
    /// `MacPriorityPicker` WRITES its binding as well as calling `onSelect`, so a read-only
    /// binding would leave the swatch showing the old value for the instant the popover is still
    /// up. Cleared on save, after which the task itself is the truth again.
    @State private var priorityDraft: [String: Task.Priority] = [:]
    /// The last priority this board WROTE per task, as opposed to the one a card was rendered
    /// with. Only a repeat of this is worth suppressing.
    @State private var lastWrittenPriority: [String: Task.Priority] = [:]

    /// The board's own width, measured — the columns divide it (AITD-330).
    @State private var boardWidth: CGFloat = 0

    /// For the card menu's "Open in new window" — the same action the list row offers (AITD-372).
    @Environment(\.openWindow) private var openWindow

    /// What each column gets: an equal share of the room, never below the floor.
    private var columnWidth: CGFloat {
        MacLayout.boardColumnWidth(columnCount: columns.count, availableWidth: boardWidth)
    }

    private var list: TaskList? { listService.lists.first { $0.id == listId } }

    /// The board draws no header of its own (AITD-553: "this separate header needs to go!").
    /// Its only control was a ⋯ holding Disable Board; that is in List Settings ▸ Admin now, and
    /// the window toolbar is the one header — the board is only ever shown when it is enabled
    /// (`MacViewMode.offersBoard`), so its Enable branch never drew.
    static let hasHeaderStrip = false

    private var columns: [ProjectBoardColumn] { board.columns.map(\.column) }

    /// How far back Done goes on this list's board, per person (ADEV-131).
    @State private var doneSince: DoneSince = .default

    /// The period Done's header names is part of the question, so Done holds every card finished
    /// since it rather than the list's window (ADEV-140).
    private var query: BoardModel.Query {
        BoardModel.Query(listId: listId, rowOfProjectId: rowOfProjectId, doneSince: doneSince.wireValue())
    }

    /// Each column's cards, from the core's ids: the service's own tasks.
    private func cardsByColumn() -> [String: [Task]] {
        Dictionary(board.columns.map { col -> (String, [Task]) in
            let cards = BoardModel.cards(col, in: taskService.tasksById)
            return (col.id, col.kind == .done ? doneSince.filter(cards) : cards)
        }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: MacLayout.boardColumnSpacing) {
                    let buckets = cardsByColumn()
                    ForEach(columns) { col in columnView(col, items: buckets[col.id] ?? []) }
                }
                .frame(height: columnHeight)
                .padding(MacLayout.boardPadding)
            }
            // The columns share whatever room the board has, down to their minimum — below that
            // this still scrolls, exactly as it did when the width was fixed (AITD-330).
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boardWidth = $0 }
            .macScrollBars(showScrollBars)
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bgPrimary)   // pervasive theme background (Ocean cyan) behind the board
        // The card's leading control offers an assignee picker (task 9be8cb1b), and it can only
        // list people it knows about. Fetching here rather than relying on another screen having
        // opened the members sheet first, which is not something the board can assume.
        .task(id: listId) { try? await memberService.fetchMembers(listId: listId) }
        .task(id: query) { board.update(query) }
        .task(id: listId) { doneSince = DoneSince.load(listId: listId, userId: AuthManager.shared.userId) }
        .onChange(of: doneSince) { _, since in since.save(listId: listId, userId: AuthManager.shared.userId) }
    }

    private func columnView(_ col: ProjectBoardColumn, items: [Task]) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(col.name).macFont(.headline).foregroundStyle(Theme.textSecondary)
                if col.kind == .done {
                    // "Done … 15 ✓ This week", on the right — a click picks how far back
                    // (ADEV-131, ADEV-134).
                    Spacer()
                    // iOS's capsule (ADEV-166): the shared header badge IS the button.
                    DoneSinceMenu(since: $doneSince, count: items.count) { text in
                        BoardHeaderBadge {
                            HStack(spacing: Theme.spacing4) {
                                Text(verbatim: text)
                                Image(systemName: "chevron.down").imageScale(.small)
                            }
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                    BoardHeaderBadge { Text(verbatim: "\(items.count)") }
                }
            }
            .help(col.description)
            // The CARDS scroll, not the board. Without this the column was a plain stack of
            // every card, so a long column simply grew past the bottom of the window and took
            // the whole board with it — the header and the add-card field went with it and
            // there was no way to reach them (task e508ae5b).
            //
            // Lazy, because a column is exactly the place a list gets long.
            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(items) { t in card(t) }
                }
                // An empty column says something about its own state, as on iOS (ADEV-81).
                if items.isEmpty {
                    // The shared empty state at the Mac's density, as on iOS (ADEV-166). The hi-fi
                    // art, once today's set is cached; a project's short rows skip it so one board
                    // never shows a different metaphor per row (ADEV-127).
                    AstridSpeechBubble(
                        message: BoardColumnEmptyMessage.decide(col).text,
                        character: rowOfProjectId == nil ? empathyArt.frame(listId: listId, column: col) : nil,
                        density: rowOfProjectId == nil ? .compact : .textOnly,
                        messageIdentifier: "board.column.empty.\(col.id)")
                        .padding(.leading, rowOfProjectId == nil ? Theme.spacing16 : 0)
                        .padding(.vertical, Theme.spacing8)
                }
            }
            .macScrollBars(showScrollBars)
            .scrollContentBackground(.hidden)
            // Takes the room left over between the header and the add field, so those two
            // stay put at the top and bottom of the column instead of scrolling away.
            .frame(maxHeight: .infinity)
            // Stays at the bottom of the column (iPad/web placement). Not on Done, as on iOS
            // (`BoardColumnView.shouldShowFooter`): a card is not born finished (ADEV-60).
            if col.kind != .done { addCardField(col) }
        }
        .padding(10)
        .frame(width: columnWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(dropTargetColumnId == col.id ? Theme.accent.opacity(0.15) : Theme.bgTertiary.opacity(0.4)))
        .animation(MacMotion.fast, value: dropTargetColumnId)   // drop-target highlight eases (4c7b9f08)
        .dropDestination(for: String.self) { items, _ in
            // A list dragged from the sidebar is not a card (web `PROJECT_BOARD_LIST_DRAG_TYPE`).
            guard let taskId = items.first, ProjectBoardListDrag.listId(from: taskId) == nil else { return false }
            move(taskId: taskId, to: col)
            return true
        } isTargeted: { dropTargetColumnId = $0 ? col.id : nil }
    }

    /// The column's Add-a-task bar: the SAME bar the list column draws (AITD-431), told which
    /// column it is in so the card is born there. It was a bare TextField of its own, without the
    /// list's defaults, smart parsing, the defaults picker or ⊕.
    @ViewBuilder private func addCardField(_ col: ProjectBoardColumn) -> some View {
        MacQuickAddBar(selectedListId: listId, selectionIsVirtual: false, list: list,
                       column: col, style: .boardColumn,
                       // ⊕ adds the card and opens its details, as the list's ⊕ does.
                       onOpen: { created in onOpenCard(created.id, nil) })
    }

    private func card(_ t: Task) -> some View {
        let selected = selectedTaskId == t.id
        return HStack(alignment: .top, spacing: 8) {
            // The SAME control the detail panel uses (task 9be8cb1b). This was a button whose
            // only action was complete, which made the most prominent thing on a card a
            // trapdoor: the click that reads as "pick this one" finished the task.
            //
            // The control already depicts priority (its colour) and assignee (whose photo),
            // so those are what it should let you set — the argument `MacLeadingControlButton`
            // was written for. Adopting it rather than copying it is the point: a second
            // implementation is exactly how the board and the panel came to disagree.
            VStack(spacing: 0) {
                MacLeadingControlButton(
                    task: t,
                    priority: priorityBinding(t),
                    members: members,
                    surface: .boardCard,
                    onPriority: { setPriority(t, $0) },
                    onAssignee: { setAssignee(t, $0) },
                    onToggleComplete: { toggleComplete(t) }
                )
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t.title).foregroundStyle(Theme.textPrimary).strikethrough(t.completed)
                // A Done card's completed date, as a pill under the title — the iOS card's
                // (Jon, 2026-11-19). A finished card is only ever in Done.
                if let completedOn = CompletedOnLabel.text(for: t) {
                    CompletedOnPill(text: completedOn)
                        .macFont(.caption2)
                        .padding(.vertical, Theme.spacing2)
                }
                // The task id, muted, before the date — the iOS card's metadata row (AITD-505).
                let identifier = TaskIdentifiers.boardCardLabel(for: t)
                if identifier != nil || t.dueDateTime != nil {
                    HStack(spacing: 6) {
                        if let identifier {
                            Text(identifier).lineLimit(1).fixedSize()
                                .accessibilityIdentifier("board.card.taskId")
                        }
                        // The row's short format, not `style: .date` ("October 3, 2027") (AITD-520).
                        if let due = MacDueText.text(for: t.dueDateTime, isAllDay: t.isAllDay) {
                            Text(due).lineLimit(1)
                        }
                    }
                    .macFont(.caption2).foregroundStyle(Theme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacSelectionStyle.fill(isSelected: false, hovering: hoveredCardId == t.id))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        // The selection outline the pop-out wears too (b8d1ec16, AITD-302), hover-hairline otherwise.
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(MacSelectionStyle.borderColor(isSelected: selected, hovering: hoveredCardId == t.id),
                    lineWidth: MacSelectionStyle.borderWidth(isSelected: selected)))
        // A click anywhere but the leading control opens the details the way a list row does —
        // the pop-out beside the card — never inline in the column (AITD-679). The control
        // takes its own clicks first.
        .modifier(MacBoardCardAnchor(isSelected: selected) { onOpenCard(t.id, $0) })
        .onHover { h in withAnimation(ReducedMotion.hover) { hoveredCardId = h ? t.id : (hoveredCardId == t.id ? nil : hoveredCardId) } }
        // Right-click gets the SAME actions as a list row (AITD-372). Rendered from the shared
        // model rather than restated here, so the board cannot fall behind the row: a card had no
        // context menu at all while the row had nine actions.
        //
        // Before `.draggable`, so the menu wins the right-click. A card is a drag source, and a
        // drag gesture attached first swallows the secondary click on the way past.
        .contextMenu {
            MacTaskRowMenuContent(
                task: t,
                surface: .boardCard,
                lists: listService.lists,
                currentListId: listId,
                actions: cardActions(t)
            )
        }
        .draggable(t.id)
    }

    // MARK: moves

    private func move(taskId: String, to col: ProjectBoardColumn) {
        // The core's move against this board's columns (CONTRACTS D45): nothing when the card is
        // already there, un-complete before leaving Done, Done through the completion service.
        // Into Waiting, the core may ask what the task waits for (AITD-631): the prompt moves it
        // again with the answer, and Cancel leaves it where it was.
        guard let task = taskService.tasksById[taskId] else { return }
        let listId = self.listId
        AppActions.perform("Move task") {
            try await WaitingPromptPresenter.shared.move(task) { wait in
                try await TaskService.shared.moveToBoardColumn(taskId: taskId, columnId: col.id,
                                                               listId: listId, wait: wait)
            }
        }
    }

    /// One set of card actions for both the right-click menu and the open card's ⋮ (AITD-470).
    private func cardActions(_ t: Task) -> MacTaskRowMenuActions {
        MacTaskRowMenuActions(
            toggleComplete: { toggleComplete(t) },
            // Opens the details, whose title is a field (AITD-471, AITD-679).
            rename: { if selectedTaskId != t.id { onOpenCard(t.id, nil) } },
            setPriority: { setPriority(t, $0) },
            move: { moveToList(t, $0) },
            copyToList: { copyTask(t, to: $0) },
            share: { shareTask(t) },
            copyToPasteboard: {
                MacTaskActions.copyToPasteboard(
                    MacTaskActions.clipboardText(title: t.title, shareURL: nil))
            },
            openInNewWindow: { openWindow(id: "task", value: t.id) },
            delete: { deleteTask(t) },
            fullScreen: { openFullScreen(t) }
        )
    }

    private func toggleComplete(_ t: Task) {
        // Recorded for ⌘Z, as the list row has always done. A card that completes a task without
        // an undo step is the same click with less of a way back (AITD-372).
        MacUndoCoordinator.shared.record(MacUndo.completeStep(previous: [t.id: t.completed],
                                                             to: !t.completed))
        AppActions.perform("Complete task") {
            _ = try await taskService.completeTask(id: t.id, completed: !t.completed, task: t)
        }
    }

    // MARK: - The card menu's remaining actions (AITD-372)
    //
    // Each is the SAME service call the list row's menu makes, undo step included, so the two
    // menus cannot mean different things by the same word.

    /// Move to another LIST — distinct from `move(taskId:to:)` above, which moves between the
    /// board's own columns.
    private func moveToList(_ t: Task, _ targetListId: String) {
        MacUndoCoordinator.shared.record(
            MacUndo.moveStep(previous: [t.id: t.listIds ?? []], to: targetListId))
        AppActions.perform("Move task") {
            _ = try await taskService.updateTask(taskId: t.id, listIds: [targetListId], task: t)
        }
    }

    private func copyTask(_ t: Task, to targetListId: String?) {
        AppActions.perform("Copy task") {
            _ = try await taskService.copyTask(id: t.id, targetListId: targetListId,
                                               includeComments: true)
        }
    }

    /// Open this task filling the content area — the action that used to be the second button in
    /// the card's gutter (AITD-377). Unchanged in what it does: set the app-wide full-screen flag
    /// and select the task, so `MacDetailPresentation` renders the pane over the board.
    private func openFullScreen(_ t: Task) {
        withAnimation(MacMotion.fast) { detailFullScreen = true }
        MacAppModel.shared.openTask(listId: listId, taskId: t.id)
    }

    private func shareTask(_ t: Task) {
        AppActions.perform("Share task") {
            if let url = try await MacTaskActions.makeShareURL(taskId: t.id) {
                MacTaskActions.presentShareSheet(url: url, relativeTo: nil)
            }
        }
    }

    private func deleteTask(_ t: Task) {
        MacUndoCoordinator.shared.record(MacUndo.deleteStep(
            snapshots: MacUndoCoordinator.shared.deletionSnapshots(for: [t],
                                                                   allTasks: taskService.tasks)))
        AppActions.perform("Delete task") {
            try await taskService.deleteTask(id: t.id, task: t)
        }
    }

    // MARK: - The leading control's three actions (task 9be8cb1b)

    /// Members of the list this board belongs to, for the assignee picker. Empty until the fetch
    /// below lands, and an empty picker is honest about that — it offers only Unassigned rather
    /// than pretending nobody exists.
    private var members: [ListMember] { memberService.membersByList[listId] ?? [] }

    private func priorityBinding(_ t: Task) -> Binding<Task.Priority> {
        Binding(get: { priorityDraft[t.id] ?? t.priority },
                set: { priorityDraft[t.id] = $0 })
    }

    private func setPriority(_ t: Task, _ priority: Task.Priority) {
        // Asked of the shared rule, which does NOT consult `t.priority`. Comparing the tap
        // against the card's snapshot is what stalled this: whichever priority the card was
        // rendered with became a dead button, and the draft was wiped so it snapped back.
        let outcome = MacBoardPriorityTap.tap(priority, lastWritten: lastWrittenPriority[t.id])

        // The card shows what was pressed, always — even when there is nothing to write.
        priorityDraft[t.id] = outcome.draft

        guard let write = outcome.write else { return }
        lastWrittenPriority[t.id] = write
        AppActions.perform("Set priority") {
            _ = try await taskService.updateTask(taskId: t.id, priority: write.rawValue, task: t)
            // Only if this write is still the newest thing the user asked for: clearing
            // unconditionally discarded a tap made while this one was in flight.
            priorityDraft[t.id] = MacBoardPriorityTap.draftAfterWriting(
                write, currentDraft: priorityDraft[t.id])
        }
    }

    private func setAssignee(_ t: Task, _ assigneeId: String?) {
        AppActions.perform("Set assignee") {
            _ = try await taskService.updateTask(taskId: t.id, assigneeId: assigneeId ?? "", task: t)
        }
    }
}
/// Where a board card is on screen (AITD-679). A click hands its frame to the pop-out, which docks
/// on the side with more room; while it is the open card it keeps reporting the frame, so the
/// arrow follows it as the column scrolls. Shared by the list board and the project board.
struct MacBoardCardAnchor: ViewModifier {
    let isSelected: Bool
    let onOpen: (CGRect?) -> Void
    @State private var frame: CGRect?

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture { onOpen(frame) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .background(GeometryReader { g in
                Color.clear.preference(key: MacSelectedCardFrameKey.self,
                                       value: isSelected ? g.frame(in: .global) : nil)
            })
    }
}

/// The open card reports its frame (global) so the pop-out's arrow points at it (AITD-679), as
/// the selected row reports its middle. First non-nil wins.
struct MacSelectedCardFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}
#endif
