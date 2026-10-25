import Foundation

/// Turns what the Share Extension queued in the App Group into tasks. The extension cannot reach
/// the server, so it leaves `SharedTaskData` in `ShareDataManager`; the app drains it on launch and
/// on foreground — through `TaskService`, like every other create (ASTRID.md rule 1).
///
/// Lifted out of `AstridApp` so a test can run a queued share into an in-memory core (AITD-542).
@MainActor
struct SharedTaskInbox {
    typealias Upload = (_ fileURL: URL, _ fileName: String, _ mimeType: String, _ taskId: String) async throws -> Void

    let shares: ShareDataManager
    let tasks: TaskService
    var assigneeId: () -> String? = { AuthManager.shared.userId }
    var upload: Upload = { fileURL, fileName, mimeType, taskId in
        _ = try await AttachmentService.shared.uploadSharedFile(
            fileURL: fileURL, fileName: fileName, mimeType: mimeType, taskId: taskId)
    }

    /// Creates a task for every pending share, then clears the ones that made it. A share that
    /// fails stays queued, marked failed with the reason. Returns how many became tasks.
    @discardableResult
    func drain() async -> Int {
        let pending: [SharedTaskItem]
        do {
            pending = try shares.loadPendingTasks()
        } catch {
            AppLog.debug("❌ [SharedTaskInbox] Failed to read shared tasks: \(error)")
            return 0
        }
        guard !pending.isEmpty else { return 0 }
        AppLog.debug("📋 [SharedTaskInbox] Found \(pending.count) pending shared task(s)")

        var created = 0
        for item in pending where item.status == .pending {
            if await process(item.data) { created += 1 }
        }
        try? shares.removeCompletedTasks()
        return created
    }

    private func process(_ share: SharedTaskData) async -> Bool {
        do {
            try shares.updateTaskStatus(taskId: share.id, status: .creating)
            let task = try await tasks.createTask(
                listIds: share.listId.map { [$0] } ?? [],
                title: share.title,
                description: share.description ?? "",
                priority: share.priority,
                assigneeId: assigneeId()
            )
            if let fileURL = share.fileURL, let fileName = share.fileName, let mimeType = share.mimeType {
                try shares.updateTaskStatus(taskId: share.id, status: .uploading, createdTaskId: task.id)
                try await upload(fileURL, fileName, mimeType, task.id)
            }
            try shares.updateTaskStatus(taskId: share.id, status: .completed, createdTaskId: task.id)
            return true
        } catch {
            AppLog.debug("❌ [SharedTaskInbox] Failed to process shared task: \(error)")
            try? shares.updateTaskStatus(taskId: share.id, status: .failed, error: error.localizedDescription)
            return false
        }
    }
}
