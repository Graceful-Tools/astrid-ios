import Foundation

/// Manages shared data between main app and Share Extension via App Group
class ShareDataManager {
    static let shared = ShareDataManager()

    /// The App Group both the app and the Share Extension use to hand files and tasks to each
    /// other. It must appear in BOTH targets' entitlements, and be registered in the developer
    /// portal — otherwise `containerURL(forSecurityApplicationGroupIdentifier:)` returns nil and
    /// every share silently goes nowhere.
    ///
    /// Not private, so a test can assert the app is actually entitled to it. This was wrong from
    /// the initial commit until 2026-08-27: the SHARE EXTENSION and this file named
    /// `group.cc.astrid.app` while the app was entitled to the identifier below, so the app
    /// logged `container_create_or_lookup_app_group_path_by_app_group_identifier: client is not
    /// entitled` and shared content never arrived. The app's group is the registered one, so the
    /// extension moved to it. `ShareExtensionAppGroupTests` guards the pair now.
    static let appGroupIdentifier = "group.gracefultools.astrid"

    private var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupIdentifier)
    }

    private var pendingTasksURL: URL? {
        sharedContainerURL?.appendingPathComponent("pending_tasks.json")
    }

    private var sharedFilesDirectory: URL? {
        sharedContainerURL?.appendingPathComponent("shared_files")
    }

    private init() {
        // Create shared files directory if it doesn't exist
        if let sharedFilesDir = sharedFilesDirectory {
            try? FileManager.default.createDirectory(at: sharedFilesDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Save Shared Task

    /// Save a new shared task from Share Extension
    func saveSharedTask(_ taskData: SharedTaskData) throws {
        print("📤 [ShareDataManager] Saving shared task: \(taskData.title)")

        var pendingTasks = try loadPendingTasks()
        let item = SharedTaskItem(data: taskData, status: .pending)
        pendingTasks.append(item)

        try savePendingTasks(pendingTasks)
        print("✅ [ShareDataManager] Shared task saved. Total pending: \(pendingTasks.count)")
    }

    // MARK: - Load Pending Tasks

    /// Load all pending tasks (called by main app)
    func loadPendingTasks() throws -> [SharedTaskItem] {
        guard let url = pendingTasksURL else {
            throw ShareDataError.appGroupNotConfigured
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            print("📭 [ShareDataManager] No pending tasks file found")
            return []
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let tasks = try decoder.decode([SharedTaskItem].self, from: data)
        print("📥 [ShareDataManager] Loaded \(tasks.count) pending tasks")
        return tasks
    }

    // MARK: - Update Task Status

    /// Update status of a shared task
    func updateTaskStatus(taskId: String, status: SharedTaskStatus, createdTaskId: String? = nil, error: String? = nil) throws {
        var pendingTasks = try loadPendingTasks()

        guard let index = pendingTasks.firstIndex(where: { $0.data.id == taskId }) else {
            print("⚠️ [ShareDataManager] Task not found: \(taskId)")
            return
        }

        pendingTasks[index].status = status
        pendingTasks[index].updatedAt = Date()
        if let createdTaskId = createdTaskId {
            pendingTasks[index].taskId = createdTaskId
        }
        if let error = error {
            pendingTasks[index].errorMessage = error
        }

        try savePendingTasks(pendingTasks)
        print("✅ [ShareDataManager] Updated task \(taskId) status to \(status.rawValue)")
    }

    // MARK: - Remove Completed Tasks

    /// Remove completed tasks from pending list
    func removeCompletedTasks() throws {
        var pendingTasks = try loadPendingTasks()
        let beforeCount = pendingTasks.count

        pendingTasks.removeAll { $0.status == .completed }

        try savePendingTasks(pendingTasks)
        print("🗑️ [ShareDataManager] Removed \(beforeCount - pendingTasks.count) completed tasks")
    }

    // MARK: - File Management

    /// Copy file to shared container
    func copyFileToSharedContainer(from sourceURL: URL) throws -> URL {
        guard let sharedFilesDir = sharedFilesDirectory else {
            throw ShareDataError.appGroupNotConfigured
        }

        // Create unique filename
        let fileExtension = sourceURL.pathExtension
        let uniqueFilename = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = sharedFilesDir.appendingPathComponent(uniqueFilename)

        // Copy file
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        print("📁 [ShareDataManager] Copied file to shared container: \(uniqueFilename)")

        return destinationURL
    }

    /// Delete file from shared container
    func deleteSharedFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
        print("🗑️ [ShareDataManager] Deleted shared file: \(url.lastPathComponent)")
    }

    /// Clean up old shared files (older than 7 days)
    func cleanupOldFiles() throws {
        guard let sharedFilesDir = sharedFilesDirectory else { return }

        let fileManager = FileManager.default
        let files = try fileManager.contentsOfDirectory(at: sharedFilesDir, includingPropertiesForKeys: [.creationDateKey])

        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 60 * 60)

        for fileURL in files {
            if let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let creationDate = attributes[.creationDate] as? Date,
               creationDate < sevenDaysAgo {
                try? fileManager.removeItem(at: fileURL)
                print("🗑️ [ShareDataManager] Cleaned up old file: \(fileURL.lastPathComponent)")
            }
        }
    }

    // MARK: - Private Helpers

    private func savePendingTasks(_ tasks: [SharedTaskItem]) throws {
        guard let url = pendingTasksURL else {
            throw ShareDataError.appGroupNotConfigured
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted

        let data = try encoder.encode(tasks)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Validation

    /// Check if App Group is properly configured
    func validateAppGroupAccess() -> Bool {
        guard let containerURL = sharedContainerURL else {
            print("❌ [ShareDataManager] App Group not configured: \(Self.appGroupIdentifier)")
            return false
        }

        print("✅ [ShareDataManager] App Group access validated: \(containerURL.path)")
        return true
    }
}

// MARK: - Errors

enum ShareDataError: LocalizedError {
    case appGroupNotConfigured
    case fileNotFound
    case invalidData

    var errorDescription: String? {
        switch self {
        case .appGroupNotConfigured:
            return "App Group '\(ShareDataManager.appGroupIdentifier)' is not configured. Please add it to both app and extension entitlements."
        case .fileNotFound:
            return "Shared file not found"
        case .invalidData:
            return "Invalid shared data format"
        }
    }
}
