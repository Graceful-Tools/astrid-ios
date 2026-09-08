//  PendingAttachment.swift
//  A file staged on this device and not yet uploaded.
//
//  Lifted out of `AttachmentService` (task AITD-353), which crossed its 1,000-line ceiling when
//  three views' duplicated download and upload paths were folded back into it. That is the right
//  direction for the tree — roughly 200 lines left the views — so the file to shrink was this
//  model, which is a `Codable` value with its own migration-shaped decoder and was never service
//  logic in the first place.
import Foundation

/// Info about a locally cached attachment pending upload
struct PendingAttachment: Codable {
    let tempFileId: String
    let localPath: String
    let fileName: String
    let mimeType: String
    let fileSize: Int
    let uploadContext: [String: String]  // e.g. {"taskId": "..."} or {"listId": "..."}
    var realFileId: String?  // Set when upload completes
    var uploadStatus: UploadStatus

    /// Backward compatibility — reads taskId from context
    var taskId: String { uploadContext["taskId"] ?? "" }

    enum UploadStatus: String, Codable {
        case pending
        case uploading
        case completed
        case failed
    }

    enum CodingKeys: String, CodingKey {
        case tempFileId, localPath, fileName, mimeType, fileSize
        case uploadContext, realFileId, uploadStatus
        case taskId  // Legacy field for decoding old data
    }

    init(tempFileId: String, localPath: String, fileName: String, mimeType: String, fileSize: Int, uploadContext: [String: String], realFileId: String? = nil, uploadStatus: UploadStatus) {
        self.tempFileId = tempFileId
        self.localPath = localPath
        self.fileName = fileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.uploadContext = uploadContext
        self.realFileId = realFileId
        self.uploadStatus = uploadStatus
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tempFileId = try container.decode(String.self, forKey: .tempFileId)
        localPath = try container.decode(String.self, forKey: .localPath)
        fileName = try container.decode(String.self, forKey: .fileName)
        mimeType = try container.decode(String.self, forKey: .mimeType)
        fileSize = try container.decode(Int.self, forKey: .fileSize)
        realFileId = try container.decodeIfPresent(String.self, forKey: .realFileId)
        uploadStatus = try container.decode(UploadStatus.self, forKey: .uploadStatus)

        // Try new context dict first, fall back to legacy taskId string
        if let ctx = try? container.decode([String: String].self, forKey: .uploadContext) {
            uploadContext = ctx
        } else if let legacyTaskId = try? container.decode(String.self, forKey: .taskId) {
            uploadContext = ["taskId": legacyTaskId]
        } else {
            uploadContext = [:]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tempFileId, forKey: .tempFileId)
        try container.encode(localPath, forKey: .localPath)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(mimeType, forKey: .mimeType)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(uploadContext, forKey: .uploadContext)
        try container.encodeIfPresent(realFileId, forKey: .realFileId)
        try container.encode(uploadStatus, forKey: .uploadStatus)
    }
}
