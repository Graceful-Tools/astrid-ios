import SwiftUI

/// Quick task creation UI for Share Extension
/// Minimal interface focused on speed - full editing available in main app
struct TaskQuickCreateView: View {
    let fileData: SharedFileData?
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
                            Image(systemName: fileIcon(for: fileData.mimeType))
                                .font(.system(size: 32))
                                .foregroundColor(.blue)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(fileData.fileName)
                                    .font(.subheadline)
                                    .lineLimit(2)

                                Text(formatFileSize(fileData.fileSize))
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

                // Pre-fill title from filename if available
                if let fileName = fileData?.fileName, taskTitle.isEmpty {
                    // Remove file extension and clean up
                    let nameWithoutExt = (fileName as NSString).deletingPathExtension
                    taskTitle = nameWithoutExt
                        .replacingOccurrences(of: "_", with: " ")
                        .replacingOccurrences(of: "-", with: " ")
                }
            }
        }
    }

    // MARK: - Actions

    private func saveTask() {
        let trimmedTitle = taskTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }

        let taskData = SharedTaskData(
            title: trimmedTitle,
            description: taskDescription.isEmpty ? nil : taskDescription,
            listId: nil, // Will use default list in main app
            priority: selectedPriority == 0 ? nil : selectedPriority,
            fileURL: fileData?.fileURL,
            fileName: fileData?.fileName,
            mimeType: fileData?.mimeType,
            fileSize: fileData?.fileSize
        )

        print("✅ [TaskQuickCreateView] Task created: \(trimmedTitle)")
        if fileData != nil {
            print("   📎 With attachment: \(fileData!.fileName)")
        }

        onSave(taskData)
    }

    // MARK: - Helpers

    private func fileIcon(for mimeType: String) -> String {
        switch mimeType {
        case let type where type.hasPrefix("image/"):
            return "photo"
        case let type where type.hasPrefix("video/"):
            return "video"
        case let type where type.contains("pdf"):
            return "doc.fill"
        case let type where type.contains("text"):
            return "doc.text"
        case let type where type.contains("zip"), let type where type.contains("archive"):
            return "archivebox"
        default:
            return "doc"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Preview

#Preview("With Image") {
    TaskQuickCreateView(
        fileData: SharedFileData(
            fileURL: URL(fileURLWithPath: "/tmp/test.jpg"),
            fileName: "vacation_photo.jpg",
            mimeType: "image/jpeg",
            fileSize: 2_500_000
        ),
        onSave: { _ in },
        onCancel: { }
    )
}

#Preview("Without File") {
    TaskQuickCreateView(
        fileData: nil,
        onSave: { _ in },
        onCancel: { }
    )
}
