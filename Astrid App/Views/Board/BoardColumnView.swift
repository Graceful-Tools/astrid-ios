import SwiftUI
import UniformTypeIdentifiers

/// One board column: header + scrollable card list + inline "Add task"
/// footer. Drops are accepted for any text-payload representing a task
/// id; the parent view computes the new task state.
///
/// The column's wrapper background matches the card background so the
/// ocean theme (cyan page) reads correctly — `Color(.secondarySystemBackground)`
/// looked off against the cyan gradient. Cards still have their own
/// border so they're individually distinguishable inside the column.
struct BoardColumnView: View {
    @Environment(\.colorScheme) var colorScheme
    @AppStorage("themeMode") private var themeMode: String = "ocean"

    let column: ProjectBoardColumn
    let tasks: [Task]
    /// The project's regular (domain) list — used by the inline footer
    /// so newly-added tasks land in the right list. Nil hides the footer.
    let selectedList: TaskList?
    /// (payload, slotIndex) — slotIndex is 0..<tasks.count for "above
    /// this card" and equals `tasks.count` for "append at end".
    let onDropAt: (BoardCardPayload, Int) -> Void

    @State private var isTargeted = false
    /// Which slot index is currently being hovered, if any. Drives the
    /// "tasks move out of the way" visual: a thin accent line appears
    /// above the hovered card and the card gains a top spacer, so the
    /// user can see exactly where the drop will land before releasing.
    @State private var hoveringIndex: Int?

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
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                        cardSlot(for: task, at: index)
                    }
                    // Append-at-end drop slot. Always present so the user
                    // can drop into an empty column or below the last card.
                    appendSlot
                }
                .padding(8)
                .animation(.spring(response: 0.25, dampingFraction: 0.85), value: hoveringIndex)
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
            // Always-visible subtle border + heavier accent when a drag is
            // hovering. The border is what defines the column shape now
            // that the fill matches the page background.
            RoundedRectangle(cornerRadius: 12)
                .stroke(isTargeted ? Color.accentColor : columnBorderColor,
                        lineWidth: isTargeted ? 2 : 1)
        )
        // The per-slot drops handle precise positioning. The column's
        // outer dropDestination remains as a fallback so a drop on the
        // header / footer chrome (above the cards) still lands —
        // defaults to inserting at the top of the column.
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .dropDestination(for: BoardCardPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            onDropAt(payload, 0)
            return true
        } isTargeted: { hovering in
            isTargeted = hovering
        }
    }

    /// One card with a hover-aware drop indicator above it. When a
    /// drag is hovering this slot, a colored line appears at the top
    /// edge and the card gets a top spacer so the user sees exactly
    /// where the drop will land before releasing.
    @ViewBuilder
    private func cardSlot(for task: Task, at index: Int) -> some View {
        VStack(spacing: 0) {
            // Drop indicator. Animates in/out via the parent's .animation.
            if hoveringIndex == index {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
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
                    onDropAt(payload, index)
                    return true
                } isTargeted: { hovering in
                    hoveringIndex = hovering ? index : (hoveringIndex == index ? nil : hoveringIndex)
                }
        }
    }

    /// Drop slot at the bottom of the column for "append at end" drops.
    /// Visible only when a drag is hovering — at rest it's invisible
    /// padding. Also covers empty columns (Inbox/Done with no cards).
    @ViewBuilder
    private var appendSlot: some View {
        let appendIndex = tasks.count
        ZStack(alignment: .top) {
            if hoveringIndex == appendIndex {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(height: 3)
                    .padding(.horizontal, 8)
                    .transition(.scale.combined(with: .opacity))
            }
            // Empty placeholder text — only when the column has zero cards
            // and nothing is hovering.
            if tasks.isEmpty && hoveringIndex == nil {
                Text("No tasks")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, minHeight: tasks.isEmpty ? 80 : 24)
        .contentShape(Rectangle())
        .dropDestination(for: BoardCardPayload.self) { items, _ in
            guard let payload = items.first else { return false }
            hoveringIndex = nil
            onDropAt(payload, appendIndex)
            return true
        } isTargeted: { hovering in
            hoveringIndex = hovering ? appendIndex : (hoveringIndex == appendIndex ? nil : hoveringIndex)
        }
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
