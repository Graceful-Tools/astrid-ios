import SwiftUI
import UniformTypeIdentifiers

/// One board column: header + a SwiftUI `List` of task cards + inline
/// "Add task" footer.
///
/// Drag-drop mirrors the task list view: intra-column reorder uses
/// `List` + `.onMove`, which lets SwiftUI animate the row movement
/// natively while the drag is in progress (no optimistic state mutation
/// needed — server PUT lands invisibly because the visual order is
/// already correct). Cross-column moves use `.draggable` on each row
/// so the user can drag a card OUT of this list into another column's
/// `.dropDestination`.
///
/// We deliberately avoid `LazyVStack` + custom `.dropDestination` slots
/// here. That approach required optimistic mutation of the project
/// list's `manualSortOrder` and re-rendering on every drop, which read
/// as a "reload" flicker. `ListService.updateManualOrder` explicitly
/// skips its own optimistic update for the same reason. See PR #21.
struct BoardColumnView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let column: ProjectBoardColumn
    let tasks: [Task]
    /// The project's regular (domain) list — used by the inline footer
    /// so newly-added tasks land in the right list. Nil hides the footer.
    let selectedList: TaskList?
    /// Cross-column drop landing in THIS column. The parent computes the
    /// new task state from `(payload, slotIndex)` — slotIndex 0 means
    /// "insert at top"; the column-level drop just falls back to that.
    let onDropAt: (BoardCardPayload, Int) -> Void
    /// Intra-column reorder via SwiftUI's List `.onMove`. The parent
    /// computes the new manualSortOrder for the project's domain list
    /// and persists it — same mechanism as TaskListView.moveTask.
    let onIntraReorder: (IndexSet, Int) -> Void

    @State private var isTargeted = false

    private var effectiveTheme: String {
        themeMode == "auto" ? (colorScheme == .dark ? "dark" : "light") : themeMode
    }

    /// Column fill = the page's theme background. The column blends
    /// with the page so the white-wash isn't visually "too wide"; the
    /// border below defines where the column sits.
    private var columnBackgroundColor: Color {
        if effectiveTheme == "ocean" { return Theme.Ocean.bgPrimary }
        return effectiveTheme == "dark" ? Theme.Dark.bgPrimary : Theme.bgPrimary
    }

    /// Visible border to define the column shape against the theme bg.
    /// Ocean's theme `border` is the same cyan as the page, so it would
    /// be invisible — substitute a translucent white that reads on cyan.
    private var columnBorderColor: Color {
        if effectiveTheme == "ocean" { return Color.white.opacity(0.5) }
        return effectiveTheme == "dark" ? Theme.Dark.border : Theme.border
    }

    /// listIds the inline add-task footer should attach in addition to
    /// the regular list — i.e. the column's status list when this is a
    /// real status column. Inbox and Done columns add nothing extra.
    private var footerStatusListIds: [String] {
        guard column.kind == .status, let statusList = column.statusList else { return [] }
        return [statusList.id]
    }

    /// Suppress the inline footer in the virtual Done column — the web
    /// also doesn't let users directly create a "completed" task.
    private var shouldShowFooter: Bool {
        column.kind != .done && selectedList != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            cardList
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
            // Always-visible subtle border + heavier accent when a drag is
            // hovering. The border is what defines the column shape now
            // that the fill matches the page background.
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : columnBorderColor,
                        lineWidth: isTargeted ? 2 : 1)
        )
        // Cross-column drops land via the column-level dropDestination —
        // SwiftUI fires it when a `.draggable` payload from another
        // column is released anywhere over our chrome. Intra-column
        // reorder is handled by `.onMove` on the List below.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: BoardCardPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            onDropAt(payload, 0)
            return true
        } isTargeted: { hovering in
            isTargeted = hovering
        }
    }

    /// The native SwiftUI `List` that hosts the column's task rows.
    /// Mirrors TaskListView.taskList: plain style, transparent
    /// background, hidden separators, `.onMove` for reorder.
    @ViewBuilder
    private var cardList: some View {
        List {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                BoardTaskCardView(task: task)
                    .draggable(BoardCardPayload(taskId: task.id)) {
                        // The drag preview is a lightweight Text card so
                        // SwiftUI's transient preview hierarchy can't trip
                        // over @StateObject inside BoardTaskCardView.
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
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(
                        top: index == 0 ? 8 : 3,
                        leading: 8,
                        bottom: 3,
                        trailing: 8
                    ))
            }
            .onMove(perform: onIntraReorder)

            // Empty-state row so the column has a visible drop target
            // when no cards are present (e.g. Inbox/Done with no tasks).
            if tasks.isEmpty {
                Text("No tasks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(column.name)
                    .font(.headline)
                Spacer()
                Text("\(tasks.count)")
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
