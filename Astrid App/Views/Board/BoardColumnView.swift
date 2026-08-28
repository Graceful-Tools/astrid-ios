import SwiftUI
import UniformTypeIdentifiers

/// Collects each card's vertical extent in the column's coordinate space so
/// the drop handler can resolve a release point to a slot.
private struct BoardCardSlotsKey: PreferenceKey {
    static var defaultValue: [BoardCardSlot] { [] }
    static func reduce(value: inout [BoardCardSlot], nextValue: () -> [BoardCardSlot]) {
        value.append(contentsOf: nextValue())
    }
}

/// The column's origin in global space, so a drag point reported in column
/// coordinates can be placed on the board.
private struct BoardColumnOriginKey: PreferenceKey {
    static var defaultValue: CGPoint { .zero }
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}

/// The column's single drop target.
///
/// A `DropDelegate` rather than `.dropDestination` because it reports the
/// drag's live LOCATION (`dropUpdated`), not just a hovering flag — and the
/// location is the whole fix: it's what lets any point in the column resolve to
/// the slot the user is aiming at.
private struct BoardColumnDropDelegate: DropDelegate {
    let slots: [BoardCardSlot]
    @Binding var hoveringIndex: Int?
    @Binding var isTargeted: Bool
    /// Reports the drag point in GLOBAL coordinates (nil once the drag leaves
    /// or lands) so the board can auto-advance columns at its edges.
    let onDragMoved: (CGPoint?) -> Void
    /// The column's origin in global space, for that conversion.
    let columnOrigin: CGPoint
    let onDrop: (BoardCardPayload, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [BoardCardPayload.contentType])
    }

    func dropEntered(info: DropInfo) {
        isTargeted = true
        track(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        track(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
        hoveringIndex = nil
        onDragMoved(nil)
    }

    func performDrop(info: DropInfo) -> Bool {
        let index = boardDropInsertionIndex(dropY: info.location.y, slots: slots)
        isTargeted = false
        hoveringIndex = nil
        onDragMoved(nil)

        guard let provider = info.itemProviders(for: [BoardCardPayload.contentType]).first else {
            return false
        }
        provider.loadDataRepresentation(
            forTypeIdentifier: BoardCardPayload.contentType.identifier
        ) { data, _ in
            guard let data, let payload = try? BoardCardPayload(data: data) else { return }
            DispatchQueue.main.async { onDrop(payload, index) }
        }
        return true
    }

    private func track(_ info: DropInfo) {
        let index = boardDropInsertionIndex(dropY: info.location.y, slots: slots)
        if hoveringIndex != index {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                hoveringIndex = index
            }
        }
        onDragMoved(CGPoint(x: columnOrigin.x + info.location.x,
                            y: columnOrigin.y + info.location.y))
    }
}

/// One board column: header + scrollable card list + inline "Add task"
/// footer.
///
/// Drag-drop uses a custom `.draggable` + a column-wide `DropDelegate` (not
/// List + `.onMove`) so a card can be dragged ACROSS columns — which is the
/// board's whole point. List's `.onMove` captures the long-press
/// gesture exclusively and blocks `.draggable` from escaping the list
/// bounds.
///
/// The column has exactly ONE drop target, covering header, cards, gaps and
/// footer alike; the release point is resolved against the cards' measured
/// frames by `boardDropInsertionIndex`. It used to scatter a target per card
/// plus a column-wide fallback pinned to index 0, so every uncovered point —
/// the 6pt gaps, the header, the footer — silently sent the card to the top
/// (task 2b2c9ee2).
///
/// To kill the "card refreshes after drop" flicker, the column keeps
/// a **local** `@State pendingTaskOrder` that survives parent
/// re-renders. While it's non-empty, the column uses it instead of
/// the parent's `tasks` ordering. As soon as the server PUT lands and
/// the parent's `tasks` arrives in the same order, the override
/// auto-clears. This mirrors the trick `List.onMove` uses internally:
/// the visual order is owned by the row container, not by the
/// upstream data source, until the data source catches up.
struct BoardColumnView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let column: ProjectBoardColumn
    let tasks: [Task]
    /// The project's regular (domain) list — used by the inline footer
    /// so newly-added tasks land in the right list. Nil hides the footer.
    let selectedList: TaskList?
    /// Parent callback: persist the drop. `index` is the desired slot
    /// in the column AFTER the drop (0 = top; tasks.count = end).
    let onDropAt: (BoardCardPayload, Int) -> Void
    /// How to open a tapped task. The iPad split view supplies this to route into
    /// its side panel (keeping the board visible); when nil we fall back to the
    /// global TaskPresenter (full-screen push, used on iPhone).
    var onTaskTap: ((Task) -> Void)?
    /// The task currently open in the detail panel (for the selected highlight).
    var selectedTaskId: String?
    /// Live drag point in global coordinates while a card hovers this column
    /// (nil when it leaves or lands). The board uses it to auto-advance columns
    /// when the drag reaches its edges — task 233ec244.
    var onDragMoved: ((CGPoint?) -> Void)?

    @State private var isTargeted = false
    /// Insertion index the drag is currently aiming at, if any. Drives the
    /// drop indicator.
    @State private var hoveringIndex: Int?
    /// Card extents in this column's coordinate space, reported by the cards
    /// as they lay out.
    @State private var slotFrames: [BoardCardSlot] = []
    /// This column's origin in global space, for converting the drag point.
    @State private var columnOrigin: CGPoint = .zero
    /// Local override for this column's task order. Set on drop so
    /// the user sees the card land at its final slot immediately;
    /// auto-cleared once the parent's `tasks` prop catches up.
    @State private var pendingTaskOrder: [String] = []

    private var effectiveTheme: String {
        themeMode == "auto" ? (colorScheme == .dark ? "dark" : "light") : themeMode
    }

    /// The column's "frame" surface — the rounded outer rectangle. The
    /// header strip, the side borders and the add-task footer are all
    /// just this one colour showing through, so the frame reads as a
    /// single continuous surface.
    ///
    /// This is the *elevated* tier — it matches the card surface, and
    /// contrasts with the recessed `interiorColor` well. (Ocean already
    /// worked this way: white frame, cyan well.) On dark/light the
    /// frame previously sat one tier off the interior, which was barely
    /// distinguishable.
    private var frameColor: Color {
        switch effectiveTheme {
        case "ocean": return Color.white.opacity(0.8)
        case "dark":  return Theme.Dark.headerBg
        default:      return Theme.bgPrimary
        }
    }

    /// The recessed interior "well" behind the cards, inset from the
    /// frame by `columnBorderWidth` on the left and right. A distinct
    /// tier from the frame/card surface so cards and borders are
    /// clearly visible against it.
    private var interiorColor: Color {
        switch effectiveTheme {
        case "ocean": return Theme.Ocean.bgPrimary
        case "dark":  return Theme.Dark.bgPrimary
        default:      return Theme.bgTertiary
        }
    }

    /// Width of the white side border between the column edge and the
    /// cyan interior — roughly double the previous 3pt stroke.
    private let columnBorderWidth: CGFloat = 6

    /// The column's own coordinate space. Card frames and the drag location are
    /// both measured in it, so they can be compared directly — and because it
    /// scrolls with the cards, the comparison stays right mid-scroll.
    private var columnSpaceName: String { "board-column-\(column.id)" }

    /// List ids the board context already conveys on each card: the project's
    /// domain list, because the whole board lives inside it. Hidden from chip
    /// rendering on each row.
    ///
    /// This used to also carry the column's status list id — the column header
    /// IS the status name, so the chip was noise. There is no such list any more
    /// (task e5c74b5e): a column is a role, and a card's status is its
    /// `statusRole`, never a membership.
    private var rowHiddenListIds: Set<String> {
        guard let domainListId = selectedList?.id else { return [] }
        return [domainListId]
    }

    private var shouldShowFooter: Bool {
        column.kind != .done && selectedList != nil
    }

    /// The tasks to render, honoring the local `pendingTaskOrder`
    /// override if one is in effect. Unknown ids in the override are
    /// dropped; tasks not yet in the override (e.g. just-arrived
    /// cross-column drops) are appended in their parent order.
    private var displayedTasks: [Task] {
        guard !pendingTaskOrder.isEmpty else { return tasks }
        let byId = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        var seen = Set<String>()
        var result: [Task] = []
        for id in pendingTaskOrder {
            if let task = byId[id], !seen.contains(id) {
                result.append(task)
                seen.insert(id)
            }
        }
        for task in tasks where !seen.contains(task.id) {
            result.append(task)
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(displayedTasks.enumerated()), id: \.element.id) { index, task in
                        cardSlot(for: task, at: index)
                    }
                    appendSlot
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .animation(.spring(response: 0.28, dampingFraction: 0.88),
                           value: displayedTasks.map { $0.id })
                .animation(.spring(response: 0.2, dampingFraction: 0.85),
                           value: hoveringIndex)
            }
            .frame(minHeight: 160)
            // Cyan interior, inset from the column edges by the border
            // width — the frame colour shows through as the side walls.
            .background(interiorColor)
            .padding(.horizontal, columnBorderWidth)
            // When there's no footer (e.g. the Done column) the interior would
            // otherwise run to the very bottom and hide the frame's bottom wall.
            // Inset it so the bottom border closes the column.
            .padding(.bottom, shouldShowFooter ? 0 : columnBorderWidth)

            if shouldShowFooter {
                // Flush footer: full column width, transparent — the
                // column frame provides the white surface behind it.
                // No `additionalListIds`: quick-adding into a column used to
                // attach the column's status list, which is now a deleted row —
                // and one dangling id fails the whole create (task e5c74b5e).
                // The column id IS the role, so `statusRole` carries all of it.
                QuickAddTaskView(
                    selectedList: selectedList,
                    boardFooterStyle: true,
                    statusRole: column.id
                )
            }
        }
        // The whole column is the white frame; the header, side
        // borders and footer are all this one surface.
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(frameColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            // Accent ring only while a drag is hovering — the resting
            // frame is the column background itself, not an overlay.
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.clear,
                              lineWidth: 3)
        )
        // The drop indicator, drawn OVER the cards rather than inserted
        // between them. As a sibling in the card stack it pushed the hovered
        // card down and out from under the pointer, which ended the hover,
        // which hid the indicator, which moved the card back — the flicker
        // reported as "finiky" (task 2b2c9ee2).
        .overlay(alignment: .top) { dropIndicator }
        .coordinateSpace(name: columnSpaceName)
        // Collect the card frames the drop resolution needs, and this column's
        // global origin so the board can locate the drag across columns.
        .onPreferenceChange(BoardCardSlotsKey.self) { frames in
            slotFrames = frames.sorted { $0.minY < $1.minY }
        }
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: BoardColumnOriginKey.self,
                                       value: proxy.frame(in: .global).origin)
            }
        )
        .onPreferenceChange(BoardColumnOriginKey.self) { columnOrigin = $0 }
        // ONE drop target for the whole column — header, cards, gaps and
        // footer alike. Every point resolves to a slot.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onDrop(of: [BoardCardPayload.contentType],
                delegate: BoardColumnDropDelegate(
                    slots: slotFrames,
                    hoveringIndex: $hoveringIndex,
                    isTargeted: $isTargeted,
                    onDragMoved: { onDragMoved?($0) },
                    columnOrigin: columnOrigin,
                    onDrop: { payload, index in handleDrop(payload: payload, at: index) }
                ))
        // Auto-clear the local override once the parent's tasks have
        // caught up to the pending order. Comparing id-arrays directly
        // avoids holding the override stale forever in edge cases.
        .onChange(of: tasks.map { $0.id }) { _, newIds in
            if !pendingTaskOrder.isEmpty {
                let pendingTrimmed = pendingTaskOrder.filter { Set(newIds).contains($0) }
                if pendingTrimmed == newIds {
                    pendingTaskOrder = []
                }
            }
        }
    }

    /// The drop indicator: a line at the slot the drag is aiming at, positioned
    /// from the cards' measured frames so it costs the layout nothing.
    @ViewBuilder
    private var dropIndicator: some View {
        if let hoveringIndex, !slotFrames.isEmpty {
            Capsule()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 14)
                .offset(y: boardDropIndicatorOffset(forInsertionIndex: hoveringIndex,
                                                    slots: slotFrames) - 1.5)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    /// One card. Long-press to drag; the column's single drop target decides
    /// where a release lands. The card reports its own extent so it can.
    @ViewBuilder
    private func cardSlot(for task: Task, at index: Int) -> some View {
        VStack(spacing: 0) {
            BoardTaskCardView(task: task, hiddenListIds: rowHiddenListIds,
                              isSelected: task.id == selectedTaskId)
                // Tap opens the task detail — same as tapping a row in
                // the flat list. Routed through the global TaskPresenter,
                // which TaskListView (the board's host) already wires up
                // via `.withTaskPresentation()`. The checkbox Button
                // inside the card intercepts its own taps first, so a
                // completion toggle doesn't also open the detail.
                .onTapGesture {
                    if let onTaskTap {
                        onTaskTap(task)
                    } else {
                        TaskPresenter.shared.showTask(task)
                    }
                }
                .draggable(BoardCardPayload(taskId: task.id)) {
                    Text(task.title)
                        .font(.body)
                        .padding(12)
                        .frame(maxWidth: 260, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator), lineWidth: 0.5)
                        )
                        .opacity(0.92)
                }
                .background(
                    GeometryReader { proxy in
                        let frame = proxy.frame(in: .named(columnSpaceName))
                        Color.clear.preference(
                            key: BoardCardSlotsKey.self,
                            value: [BoardCardSlot(taskId: task.id,
                                                  minY: frame.minY,
                                                  maxY: frame.maxY)]
                        )
                    }
                )
        }
    }

    /// Empty-column placeholder message. Reuses the same Astrid
    /// empty-state copy the flat list view shows so the board and the
    /// list feel like the same app.
    private var emptyColumnMessage: String {
        NSLocalizedString("empty_state.default", comment: "")
    }

    /// Breathing room under the last card. Releases here resolve to "append"
    /// through the column's single drop target — the empty-state art is all
    /// this view is still responsible for.
    @ViewBuilder
    private var appendSlot: some View {
        ZStack(alignment: .top) {
            if displayedTasks.isEmpty && !isTargeted {
                // Same EmptyStateView (Astrid + speech bubble) the flat
                // list view uses — board columns get the same friendly
                // empty state instead of a bare "No tasks" label.
                EmptyStateView(message: emptyColumnMessage)
                    .padding(.vertical, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: displayedTasks.isEmpty ? 260 : 24)
        .allowsHitTesting(false)
    }

    /// On drop: update the local override immediately so the card
    /// shows up at its final slot without waiting for the server PUT
    /// (no flicker), then notify the parent so the persistence layer
    /// fires.
    ///
    /// Works for both intra-column drops (taskId already in `tasks`)
    /// and cross-column drops (taskId arriving from a sibling column —
    /// will land in `tasks` once `taskService.updateTask` propagates).
    private func handleDrop(payload: BoardCardPayload, at index: Int) {
        let taskId = payload.taskId

        // Snapshot the current displayed order, remove the dragged id
        // if present, then insert it at the target slot. The clamp
        // handles index == displayedTasks.count (append at end).
        var newIds = displayedTasks.map { $0.id }.filter { $0 != taskId }
        let target = max(0, min(index, newIds.count))
        newIds.insert(taskId, at: target)

        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            pendingTaskOrder = newIds
        }

        onDropAt(payload, index)
    }

    /// Task-count pill — same treatment as the list count badge in the
    /// left sidebar (`ListRowView`): caption text in a soft capsule.
    @ViewBuilder
    private var countBadge: some View {
        Text("\(displayedTasks.count)")
            .font(Theme.Typography.caption1())
            .foregroundColor(colorScheme == .dark ? Theme.Dark.textSecondary : Theme.textSecondary)
            .padding(.horizontal, Theme.spacing8)
            .padding(.vertical, Theme.spacing4)
            .background(
                Capsule()
                    .fill(colorScheme == .dark ? Theme.Dark.bgTertiary : Color.gray.opacity(0.1))
            )
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(column.name)
                    .font(.headline)
                Spacer()
                countBadge
            }
            if !column.description.isEmpty {
                Text(column.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No own background — the header sits directly on the column
        // frame, so it's the same surface as the side borders/footer.
    }
}
