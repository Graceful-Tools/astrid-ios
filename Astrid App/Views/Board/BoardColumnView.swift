import SwiftUI
import UniformTypeIdentifiers

/// One board column: header + scrollable card list + inline "Add task"
/// footer.
///
/// Drag-drop uses custom `.draggable` + `.dropDestination` (not List +
/// `.onMove`) so a card can be dragged ACROSS columns — which is the
/// board's whole point. List's `.onMove` captures the long-press
/// gesture exclusively and blocks `.draggable` from escaping the list
/// bounds.
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

    @State private var isTargeted = false
    /// Slot index currently being hovered over, if any. Drives the
    /// "tasks move out of the way" drop indicator.
    @State private var hoveringIndex: Int?
    /// Local override for this column's task order. Set on drop so
    /// the user sees the card land at its final slot immediately;
    /// auto-cleared once the parent's `tasks` prop catches up.
    @State private var pendingTaskOrder: [String] = []

    private var effectiveTheme: String {
        themeMode == "auto" ? (colorScheme == .dark ? "dark" : "light") : themeMode
    }

    private var columnBackgroundColor: Color {
        if effectiveTheme == "ocean" { return Theme.Ocean.bgPrimary }
        return effectiveTheme == "dark" ? Theme.Dark.bgPrimary : Theme.bgPrimary
    }

    private var columnBorderColor: Color {
        if effectiveTheme == "ocean" { return Color.white.opacity(0.5) }
        return effectiveTheme == "dark" ? Theme.Dark.border : Theme.border
    }

    private var footerStatusListIds: [String] {
        guard column.kind == .status, let statusList = column.statusList else { return [] }
        return [statusList.id]
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
                .padding(8)
                .animation(.spring(response: 0.28, dampingFraction: 0.88),
                           value: displayedTasks.map { $0.id })
                .animation(.spring(response: 0.2, dampingFraction: 0.85),
                           value: hoveringIndex)
            }
            .frame(minHeight: 160)

            if shouldShowFooter {
                Divider()
                QuickAddTaskView(
                    selectedList: selectedList,
                    additionalListIds: footerStatusListIds
                )
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(columnBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : columnBorderColor,
                        lineWidth: isTargeted ? 2 : 1)
        )
        // Column-level drop is the fallback when a drag releases over
        // the header / footer chrome (above or below the cards). Defaults
        // to inserting at the top of the column. Per-slot drops below
        // handle precise positioning when the user releases over a card.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: BoardCardPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            handleDrop(payload: payload, at: 0)
            return true
        } isTargeted: { hovering in
            isTargeted = hovering
        }
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

    /// One card with a hover-aware drop indicator above it. Mirrors
    /// the list view's drag-handle behavior — long-press to drag, drop
    /// on another card to insert above it.
    @ViewBuilder
    private func cardSlot(for task: Task, at index: Int) -> some View {
        VStack(spacing: 0) {
            if hoveringIndex == index {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                    .transition(.scale.combined(with: .opacity))
            }

            BoardTaskCardView(task: task)
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
                .dropDestination(for: BoardCardPayload.self) { items, _ in
                    guard let payload = items.first else { return false }
                    hoveringIndex = nil
                    handleDrop(payload: payload, at: index)
                    return true
                } isTargeted: { hovering in
                    hoveringIndex = hovering ? index : (hoveringIndex == index ? nil : hoveringIndex)
                }
        }
    }

    /// Drop slot at the bottom of the column for "append at end" drops.
    @ViewBuilder
    private var appendSlot: some View {
        let appendIndex = displayedTasks.count
        ZStack(alignment: .top) {
            if hoveringIndex == appendIndex {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .transition(.scale.combined(with: .opacity))
            }
            if displayedTasks.isEmpty && hoveringIndex == nil {
                Text("No tasks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: displayedTasks.isEmpty ? 80 : 24)
        .contentShape(Rectangle())
        .dropDestination(for: BoardCardPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            hoveringIndex = nil
            handleDrop(payload: payload, at: appendIndex)
            return true
        } isTargeted: { hovering in
            hoveringIndex = hovering ? appendIndex : (hoveringIndex == appendIndex ? nil : hoveringIndex)
        }
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

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(column.name)
                    .font(.headline)
                Spacer()
                Text("\(displayedTasks.count)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
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
        .padding(.bottom, 6)
    }
}
