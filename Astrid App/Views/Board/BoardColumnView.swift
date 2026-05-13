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
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    private var effectiveTheme: String {
        themeMode == "auto" ? (colorScheme == .dark ? "dark" : "light") : themeMode
    }

    /// Mirrors TaskRowView.getCardBackground so the column wrapper reads
    /// the same on every theme — especially ocean, where the secondary
    /// system bg clashed with the cyan gradient.
    private var columnBackgroundColor: Color {
        if effectiveTheme == "ocean" {
            return Color.white.opacity(0.8)
        }
        return effectiveTheme == "dark" ? Theme.Dark.bgPrimary : Theme.bgPrimary
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
                    ForEach(tasks) { task in
                        BoardTaskCardView(task: task)
                            .draggable(task.id) {
                                // Lightweight static preview — see the
                                // note in BoardColumnView's earlier commit
                                // about transient drag-preview crashes.
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
                    }
                    if tasks.isEmpty {
                        Text("No tasks")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 20)
                    }
                }
                .padding(8)
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
                .stroke(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .dropDestination(for: String.self) { items, _ in
            guard let taskId = items.first else { return false }
            onDrop(taskId)
            return true
        } isTargeted: { hovering in
            isTargeted = hovering
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
