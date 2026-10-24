import SwiftUI

/// Quick task creation UI for Share Extension
/// Minimal interface focused on speed - full editing available in main app
struct TaskQuickCreateView: View {
    let draft: SharedTaskDraft?
    private var fileData: SharedFileData? { draft?.file }
    let onSave: (SharedTaskData) -> Void
    let onCancel: () -> Void

    @State private var taskTitle: String = ""
    @State private var taskDescription: String = ""
    @State private var selectedPriority: Int = 0
    @FocusState private var isTitleFocused: Bool

    private let priorities = [
        (value: 0, name: "None", icon: "circle"),
        (value: 1, name: "Low", icon: "flag.fill"),
        (value: 2, name: "Medium", icon: "flag.fill"),
        (value: 3, name: "High", icon: "flag.fill")
    ]

    var body: some View {
        NavigationView {
            Form {
                // File preview section
                if let fileData = fileData {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: fileData.iconName)
                                .font(.system(size: 32))
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileData.fileName)
                                    .font(.subheadline)
                                    .lineLimit(2)

                                Text(fileData.formattedSize)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    } header: {
                        Text("Attachment")
                    }
                }

                // Task details section
                Section {
                    TextField("Task title", text: $taskTitle)
                        .focused($isTitleFocused)
                        .font(.body)

                    TextField("Description (optional)", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...5)
                        .font(.body)
                } header: {
                    Text("Task Details")
                }

                // Priority section
                Section {
                    Picker("Priority", selection: $selectedPriority) {
                        ForEach(priorities, id: \.value) { priority in
                            Label(priority.name, systemImage: priority.icon)
                                .tag(priority.value)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Priority")
                }

                // Info section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Task will be created in your default list", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if fileData != nil {
                            Label("File will be uploaded in the background", systemImage: "arrow.up.circle")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Create Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveTask()
                    }
                    .disabled(taskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                // Auto-focus title field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isTitleFocused = true
                }

                // Pre-fill from what was shared (Shared/SharedContentLoader.swift)
                if let draft, taskTitle.isEmpty {
                    taskTitle = draft.title
                    taskDescription = draft.notes
                }
            }
        }
    }

    // MARK: - Actions

    private func saveTask() {
        guard let taskData = SharedTaskDraft.taskData(
            title: taskTitle, notes: taskDescription, priority: selectedPriority, file: fileData
        ) else { return }
        AppLog.debug("✅ [TaskQuickCreateView] Task created: \(taskData.title)")
        onSave(taskData)
    }
}

// MARK: - Preview

#Preview("With Image") {
    TaskQuickCreateView(
        draft: .file(SharedFileData(
            fileURL: URL(fileURLWithPath: "/tmp/test.jpg"),
            fileName: "vacation_photo.jpg",
            mimeType: "image/jpeg",
            fileSize: 2_500_000
        )),
        onSave: { _ in },
        onCancel: { }
    )
}

#Preview("Without File") {
    TaskQuickCreateView(
        draft: nil,
        onSave: { _ in },
        onCancel: { }
    )
}
