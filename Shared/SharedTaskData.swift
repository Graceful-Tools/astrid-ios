import Foundation

/// Data structure for sharing task creation data between Share Extension and main app
/// Stored in App Group shared container
struct SharedTaskData: Codable {
    let id: String
    let title: String
    let description: String?
    let listId: String?
    let priority: Int?
    let fileURL: URL?
    let fileName: String?
    let mimeType: String?
    let fileSize: Int64?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, description, listId, priority
        case fileURL, fileName, mimeType, fileSize, createdAt
    }

    init(
        id: String = UUID().uuidString,
        title: String,
        description: String? = nil,
        listId: String? = nil,
        priority: Int? = nil,
        fileURL: URL? = nil,
        fileName: String? = nil,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.listId = listId
        self.priority = priority
        self.fileURL = fileURL
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.createdAt = createdAt
    }
}

/// Status of shared task processing
enum SharedTaskStatus: String, Codable {
    case pending       // Waiting to be processed
    case uploading     // File is being uploaded
    case creating      // Task is being created
    case completed     // Task created successfully
    case failed        // Failed to process
}

/// Wrapper for shared task with status tracking
struct SharedTaskItem: Codable {
    let data: SharedTaskData
    var status: SharedTaskStatus
    var taskId: String?        // Set after task is created
    var errorMessage: String?  // Set if processing fails
    var updatedAt: Date

    init(data: SharedTaskData, status: SharedTaskStatus = .pending) {
        self.data = data
        self.status = status
        self.taskId = nil
        self.errorMessage = nil
        self.updatedAt = Date()
    }
}
