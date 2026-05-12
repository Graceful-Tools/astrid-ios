import SwiftUI
import UniformTypeIdentifiers

/// One board column: header + scrollable card list. Drops are accepted
/// for any text-payload representing a task id; the parent view computes
/// the new task state.
struct BoardColumnView: View {
    let column: ProjectBoardColumn
    let tasks: [Task]
    let onDrop: (String) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(tasks) { task in
                        BoardTaskCardView(task: task)
                            .draggable(task.id) {
                                BoardTaskCardView(task: task)
                                    .frame(width: 260)
                                    .opacity(0.85)
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
            .frame(minHeight: 200)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
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
