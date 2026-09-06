import Foundation
#if canImport(UIKit)
import UIKit
#endif
import UniformTypeIdentifiers
import Combine

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

@MainActor
class AttachmentService: ObservableObject {
    static let shared = AttachmentService(apiClient: APIClient.shared)

    @Published var isUploading = false
    @Published var uploadProgress: Double = 0
    @Published var errorMessage: String?
    @Published var pendingUploads: [String: PendingAttachment] = [:]  // tempFileId -> PendingAttachment

    private let apiClient: APIClientProtocol
    private let fileManager = FileManager.default
    private let cacheDirectory: URL  // For pending uploads
    private let downloadCacheDirectory: URL  // For downloaded/viewed attachments
    private let networkMonitor = NetworkMonitor.shared
    private var networkObserver: NSObjectProtocol?

    // Map temp fileIds to real fileIds after upload
    private var fileIdMapping: [String: String] = [:]

    init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient

        // Setup local cache directory for pending attachments
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent("PendingAttachments", isDirectory: true)
        downloadCacheDirectory = cachesDirectory.appendingPathComponent("DownloadedAttachments", isDirectory: true)

        // Create cache directories if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: downloadCacheDirectory, withIntermediateDirectories: true)

        print("📦 [AttachmentService] Pending cache: \(cacheDirectory.path)")
        print("📦 [AttachmentService] Download cache: \(downloadCacheDirectory.path)")

        // Load any pending uploads from previous session
        loadPendingUploads()

        // Setup network observer to sync when connection is restored
        setupNetworkObserver()
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Setup network observer: on reconnect, drain the Outbox so queued
    /// upload→comment/send chains run.
    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { _ in
            _Concurrency.Task { @MainActor in
                print("🔄 [AttachmentService] Network restored - draining outbox")
                await OutboxManager.shared.drain()
            }
        }
    }

    // MARK: - Local File Cache

    /// Save file locally and return temp fileId immediately
    /// Upload happens asynchronously in background
    /// Save file locally and upload in background. Accepts a generic context dict.
    func saveLocallyAndUploadAsync(
        fileData: Data,
        fileName: String,
        mimeType: String,
        context: [String: String]
    ) -> String {
        let tempFileId = "temp_\(UUID().uuidString)"
        let localPath = cacheDirectory.appendingPathComponent(tempFileId).path

        // Save file locally
        do {
            try fileData.write(to: URL(fileURLWithPath: localPath))
            print("💾 [AttachmentService] Saved file locally: \(tempFileId) (\(fileData.count) bytes)")
        } catch {
            print("❌ [AttachmentService] Failed to save file locally: \(error)")
            return tempFileId
        }

        // Create pending attachment record
        let pending = PendingAttachment(
            tempFileId: tempFileId,
            localPath: localPath,
            fileName: fileName,
            mimeType: mimeType,
            fileSize: fileData.count,
            uploadContext: context,
            realFileId: nil,
            uploadStatus: .pending
        )

        pendingUploads[tempFileId] = pending
        savePendingUploads()

        // No upload starts here: the comment/chat compose path builds an Outbox
        // upload→comment dependency chain from this pending record, so the Outbox
        // owns the upload. The local save + pending record above still happen so
        // the optimistic thumbnail shows and the chain can read
        // localPath/fileName/mimeType/context.
        return tempFileId
    }

    /// Record a temp→real fileId mapping produced by the Outbox upload handler so
    /// thumbnail display (getRealFileId) and any legacy resolver path see it.
    /// Mirrors the legacy completion side effects: thumbnail alias + the
    /// `.attachmentUploadCompleted` notification (any waiter resolves).
    func recordOutboxUpload(tempFileId: String, realFileId: String) {
        fileIdMapping[tempFileId] = realFileId
        if var pending = pendingUploads[tempFileId] {
            pending.realFileId = realFileId
            pending.uploadStatus = .completed
            pendingUploads[tempFileId] = pending
            savePendingUploads()
        }
        ThumbnailCache.shared.alias(from: tempFileId, to: realFileId)
        NotificationCenter.default.post(
            name: .attachmentUploadCompleted,
            object: nil,
            userInfo: ["tempFileId": tempFileId, "realFileId": realFileId]
        )
    }

    /// Convenience wrapper: save file with taskId context (existing callers)
    func saveLocallyAndUploadAsync(
        fileData: Data,
        fileName: String,
        mimeType: String,
        taskId: String
    ) -> String {
        return saveLocallyAndUploadAsync(fileData: fileData, fileName: fileName, mimeType: mimeType, context: ["taskId": taskId])
    }

    /// Get the real fileId for a temp fileId (if upload completed)
    func getRealFileId(for tempFileId: String) -> String? {
        return fileIdMapping[tempFileId] ?? pendingUploads[tempFileId]?.realFileId
    }

    /// Check if a fileId is a temp ID that's still pending
    func isPendingUpload(_ fileId: String) -> Bool {
        guard fileId.hasPrefix("temp_") else { return false }
        if let pending = pendingUploads[fileId] {
            return pending.uploadStatus != .completed
        }
        return false
    }

    /// Get local file data for a temp fileId
    func getLocalFileData(for tempFileId: String) -> Data? {
        guard let pending = pendingUploads[tempFileId] else { return nil }
        return try? Data(contentsOf: URL(fileURLWithPath: pending.localPath))
    }

    // MARK: - Downloaded Attachments Cache (for offline viewing)

    /// Get cached download data for a fileId
    func getCachedDownload(for fileId: String) -> Data? {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        guard fileManager.fileExists(atPath: cachedPath.path) else { return nil }
        return try? Data(contentsOf: cachedPath)
    }

    /// Save downloaded data to cache
    func cacheDownload(fileId: String, data: Data) {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        do {
            try data.write(to: cachedPath)
            print("💾 [AttachmentService] Cached download: \(fileId) (\(data.count) bytes)")
        } catch {
            print("⚠️ [AttachmentService] Failed to cache download: \(error)")
        }
    }

    /// Check if a download is cached
    func hasDownloadCached(for fileId: String) -> Bool {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        return fileManager.fileExists(atPath: cachedPath.path)
    }

    /// Get cached file URL for QuickLook preview
    func getCachedFileURL(for fileId: String, fileName: String) -> URL? {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        guard fileManager.fileExists(atPath: cachedPath.path) else { return nil }

        // Create a temp file with the proper extension for QuickLook
        let tempDir = fileManager.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(fileName)

        do {
            // Remove existing temp file if any
            try? fileManager.removeItem(at: tempFile)
            // Copy cached file to temp with proper name
            try fileManager.copyItem(at: cachedPath, to: tempFile)
            return tempFile
        } catch {
            print("⚠️ [AttachmentService] Failed to prepare cached file for preview: \(error)")
            return nil
        }
    }

    /// Get the signed download URL for a secure file
    func getSecureFileDownloadURL(for fileId: String) async throws -> URL? {
        let infoURL = "\(Constants.API.baseURL)/api/v1/secure-files/\(fileId)?info=true"
        guard let url = URL(string: infoURL) else { return nil }
        
        var request = URLRequest(url: url)
        AnalyticsPlatformHeader.apply(to: &request)
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        
        let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
        guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }
        
        struct FileInfo: Codable { let url: String }
        let fileInfo = try JSONDecoder().decode(FileInfo.self, from: infoData)
        
        return URL(string: fileInfo.url)
    }

    /// The bytes of a secure file, wherever they already are: the local staging copy of a file
    /// that has not finished uploading, then the download cache, then the server.
    ///
    /// One ladder, two platforms. iOS's chat attachment view and the Mac comment bubble both
    /// need exactly this, and the Mac copy was written by transcribing the iOS one — which is
    /// how the two drift. Returns nil rather than throwing: a thumbnail that cannot load is a
    /// placeholder, not an error to surface.
    func fileData(for fileId: String) async -> Data? {
        // 1. Staged locally and not uploaded yet — the bytes are on this machine.
        if fileId.hasPrefix("temp_") {
            return getLocalFileData(for: fileId)
        }
        // 2. Already downloaded once.
        if let cached = getCachedDownload(for: fileId) {
            return cached
        }
        // 3. Ask the server for a signed URL, then fetch it and cache the result.
        do {
            guard let downloadURL = try await getSecureFileDownloadURL(for: fileId) else { return nil }
            let (data, _) = try await URLSession.shared.data(from: downloadURL)
            cacheDownload(fileId: fileId, data: data)
            return data
        } catch {
            print("❌ [AttachmentService] Failed to load file data for \(fileId): \(error)")
            return nil
        }
    }

    /// Prepare multiple files for preview
    func prepareFilesForPreview(files: [SecureFile]) async -> [(fileId: String, url: URL)] {
        var results: [(fileId: String, url: URL)] = []
        
        for file in files {
            // 1. Check if it's a temp file
            if file.id.hasPrefix("temp_") {
                if let localData = getLocalFileData(for: file.id) {
                    let tempDir = fileManager.temporaryDirectory
                    let tempFileURL = tempDir.appendingPathComponent(file.name)
                    try? localData.write(to: tempFileURL)
                    results.append((fileId: file.id, url: tempFileURL))
                }
                continue
            }
            
            // 2. Check disk cache
            if let cachedURL = getCachedFileURL(for: file.id, fileName: file.name) {
                results.append((fileId: file.id, url: cachedURL))
                continue
            }
            
            // 3. Download if not cached
            do {
                let infoURL = "\(Constants.API.baseURL)/api/v1/secure-files/\(file.id)?info=true"
                guard let url = URL(string: infoURL) else { continue }
                
                var request = URLRequest(url: url)
                AnalyticsPlatformHeader.apply(to: &request)
                if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
                    request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
                }
                
                let (infoData, infoResponse) = try await URLSession.shared.data(for: request)
                guard let httpResponse = infoResponse as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else { continue }
                
                struct FileInfo: Codable { let url: String }
                let fileInfo = try JSONDecoder().decode(FileInfo.self, from: infoData)
                
                guard let downloadURL = URL(string: fileInfo.url) else { continue }
                let (fileData, _) = try await URLSession.shared.data(from: downloadURL)
                
                cacheDownload(fileId: file.id, data: fileData)
                
                let tempDir = fileManager.temporaryDirectory
                let tempFileURL = tempDir.appendingPathComponent(file.name)
                try? fileData.write(to: tempFileURL)
                results.append((fileId: file.id, url: tempFileURL))
            } catch {
                print("❌ [AttachmentService] Failed to download file for multi-preview: \(error)")
            }
        }
        
        return results
    }

    /// Cancel a pending upload and clean up local file
    func cancelUpload(tempFileId: String) {
        guard let pending = pendingUploads[tempFileId] else {
            print("⚠️ [AttachmentService] No pending upload to cancel: \(tempFileId)")
            return
        }

        print("🗑️ [AttachmentService] Cancelling upload: \(tempFileId)")

        // Delete local file
        try? fileManager.removeItem(atPath: pending.localPath)

        // Remove from pending uploads
        pendingUploads.removeValue(forKey: tempFileId)
        fileIdMapping.removeValue(forKey: tempFileId)
        savePendingUploads()

        print("✅ [AttachmentService] Upload cancelled and cleaned up: \(tempFileId)")
    }

    // MARK: - Persistence

    private func savePendingUploads() {
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(pendingUploads) {
            UserDefaults.standard.set(data, forKey: "pendingAttachments")
        }
    }

    private func loadPendingUploads() {
        guard let data = UserDefaults.standard.data(forKey: "pendingAttachments") else { return }
        let decoder = JSONDecoder()
        if let loaded = try? decoder.decode([String: PendingAttachment].self, from: data) {
            pendingUploads = loaded

            // Build fileId mapping from completed uploads
            for (tempId, pending) in loaded {
                if let realId = pending.realFileId {
                    fileIdMapping[tempId] = realId
                }
            }

            // No launch auto-retry: the Outbox journal owns upload retries, and a
            // side-channel upload here would steal the file out from under the
            // upload→comment chain.
            print("📦 [AttachmentService] Loaded \(loaded.count) pending uploads")
        }
    }
    
    // MARK: - Upload

    func uploadAttachment(taskId: String, fileData: Data, fileName: String, mimeType: String) async throws -> Attachment {
        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        defer { isUploading = false }

        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request
        let url = URL(string: Constants.API.baseURL + "/api/v1/tasks/\(taskId)/attachments")!
        var request = URLRequest(url: url)
        AnalyticsPlatformHeader.apply(to: &request)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Note: Do NOT set httpBody when using upload(for:from:) - pass body data directly to upload method

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }

        // Upload with progress - body is passed here, not set on request.httpBody
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        // Parse response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let attachment = try decoder.decode(Attachment.self, from: data)

        uploadProgress = 1.0
        return attachment
    }

    // MARK: - Secure Upload (for comments)

    /// Upload file to secure storage endpoint for use with comments
    /// Returns fileId that can be associated with a comment
    ///
    /// For files larger than 4MB, uses direct upload to Vercel Blob:
    /// 1. Request upload URL from server (validates permissions, generates token)
    /// 2. PUT file directly to Vercel Blob (bypasses serverless size limits)
    /// 3. Server callback stores metadata
    func uploadToSecureEndpoint(fileData: Data, fileName: String, mimeType: String, context: [String: String]) async throws -> String {
        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        defer { isUploading = false }

        // For files larger than 4MB, use direct upload to bypass serverless limits
        let fileSizeMB = Double(fileData.count) / (1024 * 1024)
        if fileSizeMB > 4.0 {
            print("📦 [AttachmentService] Large file detected (\(String(format: "%.1f", fileSizeMB)) MB), using direct upload")
            return try await uploadDirectToBlob(fileData: fileData, fileName: fileName, mimeType: mimeType, context: context)
        }

        // For smaller files, use the original server-side upload
        return try await uploadViaServer(fileData: fileData, fileName: fileName, mimeType: mimeType, context: context)
    }

    /// Convenience wrapper for existing callers that pass taskId
    func uploadToSecureEndpoint(fileData: Data, fileName: String, mimeType: String, taskId: String) async throws -> String {
        return try await uploadToSecureEndpoint(fileData: fileData, fileName: fileName, mimeType: mimeType, context: ["taskId": taskId])
    }

    /// Upload directly to Vercel Blob using a client token (for large files)
    private func uploadDirectToBlob(fileData: Data, fileName: String, mimeType: String, context: [String: String]) async throws -> String {
        // Step 1: Get upload URL and token from server
        print("📡 [AttachmentService] Step 1: Requesting upload URL...")

        let getUrlEndpoint = URL(string: Constants.API.baseURL + "/api/v1/secure-upload/get-upload-url")!
        var getUrlRequest = URLRequest(url: getUrlEndpoint)
        AnalyticsPlatformHeader.apply(to: &getUrlRequest)
        getUrlRequest.httpMethod = "POST"
        getUrlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            getUrlRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            print("⚠️ [AttachmentService] WARNING: No session cookie found!")
            throw AttachmentError.uploadFailed
        }

        // Request body with file metadata
        let requestBody: [String: Any] = [
            "fileName": fileName,
            "fileType": mimeType,
            "fileSize": fileData.count,
            "context": context
        ]
        getUrlRequest.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (urlData, urlResponse) = try await URLSession.shared.data(for: getUrlRequest)

        guard let httpResponse = urlResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            PrivacyLogger.error("AttachmentService", code: "upload_url_failed", status: (urlResponse as? HTTPURLResponse)?.statusCode)
            throw AttachmentError.uploadFailed
        }

        // Parse response to get upload URL and token
        struct UploadUrlResponse: Codable {
            let uploadToken: String
            let pathname: String
            let fileId: String
            let uploadUrl: String
        }

        let decoder = JSONDecoder()
        let uploadUrlResponse = try decoder.decode(UploadUrlResponse.self, from: urlData)

        PrivacyLogger.debug("AttachmentService", "upload_url=received")
        uploadProgress = 0.1

        // Step 2: Upload file directly to Vercel Blob
        print("📡 [AttachmentService] Step 2: Uploading to Vercel Blob...")

        // No platform header: Vercel Blob is a third party, and our analytics contract is
        // with our own server only (AITD-301).
        var blobRequest = URLRequest(url: URL(string: uploadUrlResponse.uploadUrl)!)
        blobRequest.httpMethod = "PUT"
        // Vercel Blob expects the client token in the Authorization header
        blobRequest.setValue("Bearer \(uploadUrlResponse.uploadToken)", forHTTPHeaderField: "Authorization")
        blobRequest.setValue(mimeType, forHTTPHeaderField: "Content-Type")
        blobRequest.setValue("public, max-age=31536000", forHTTPHeaderField: "x-cache-control-max-age")

        // Use upload delegate to track progress
        let delegate = UploadProgressDelegate(onProgress: { [weak self] progress in
            _Concurrency.Task { @MainActor in
                // Progress from 0.1 to 0.9 during upload
                self?.uploadProgress = 0.1 + (progress * 0.8)
            }
        })

        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        let (_, blobResponse) = try await session.upload(for: blobRequest, from: fileData)

        guard let blobHttpResponse = blobResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid blob response type")
            throw AttachmentError.uploadFailed
        }

        print("📡 [AttachmentService] Blob upload status: \(blobHttpResponse.statusCode)")

        guard (200...299).contains(blobHttpResponse.statusCode) else {
            PrivacyLogger.error("AttachmentService", code: "blob_upload_failed", status: blobHttpResponse.statusCode)
            throw AttachmentError.uploadFailed
        }

        print("✅ [AttachmentService] File uploaded directly to Vercel Blob")
        uploadProgress = 1.0

        return uploadUrlResponse.fileId
    }

    /// Upload via server (for smaller files)
    private func uploadViaServer(fileData: Data, fileName: String, mimeType: String, context: [String: String]) async throws -> String {
        // Create multipart form data
        let boundary = UUID().uuidString
        var body = Data()

        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Add context field (serialize dict to JSON)
        let contextJSON = (try? JSONSerialization.data(withJSONObject: context))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"context\"\r\n\r\n".data(using: .utf8)!)
        body.append(contextJSON.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        // Create request to secure upload endpoint
        let url = URL(string: Constants.API.baseURL + "/api/v1/secure-upload/request-upload")!
        var request = URLRequest(url: url)
        AnalyticsPlatformHeader.apply(to: &request)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        // Note: Do NOT set httpBody when using upload(for:from:) - pass body data directly to upload method

        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        } else {
            print("⚠️ [AttachmentService] WARNING: No session cookie found!")
        }

        PrivacyLogger.request("AttachmentService", method: "POST", url: url)

        // Upload - body is passed here, not set on request.httpBody
        let (data, response) = try await URLSession.shared.upload(for: request, from: body)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid response type")
            throw AttachmentError.uploadFailed
        }

        print("📡 [AttachmentService] Upload response status: \(httpResponse.statusCode)")

        guard (200...299).contains(httpResponse.statusCode) else {
            PrivacyLogger.error("AttachmentService", code: "server_upload_failed", status: httpResponse.statusCode)
            throw AttachmentError.uploadFailed
        }

        // Parse response to get fileId
        struct SecureUploadResponse: Codable {
            let fileId: String
            let fileName: String
            let fileSize: Int
            let mimeType: String
            let success: Bool
        }

        let decoder = JSONDecoder()
        let uploadResponse = try decoder.decode(SecureUploadResponse.self, from: data)

        uploadProgress = 1.0
        return uploadResponse.fileId
    }
    
    // MARK: - Download
    
    func downloadAttachment(_ attachment: Attachment) async throws -> Data {
        guard let url = URL(string: attachment.url) else {
            throw AttachmentError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        return data
    }
    
    // MARK: - Update (for edited attachments)

    /// Update an existing secure file with new content (e.g., after markup editing)
    /// Uses direct upload to Vercel Blob to bypass serverless function payload limits
    /// Returns the updated file info
    func updateAttachment(fileId: String, newFileData: Data, mimeType: String) async throws -> SecureFile {
        isUploading = true
        uploadProgress = 0
        errorMessage = nil

        defer { isUploading = false }

        PrivacyLogger.debug("AttachmentService", "update_started bytes=\(newFileData.count)")

        // Get session cookie
        guard let sessionCookie = try? KeychainService.shared.getSessionCookie() else {
            print("⚠️ [AttachmentService] WARNING: No session cookie found!")
            throw AttachmentError.uploadFailed
        }

        // Step 1: Request upload URL from server
        print("📤 [AttachmentService] Step 1: Getting upload URL...")
        let uploadUrlEndpoint = URL(string: Constants.API.baseURL + "/api/v1/secure-files/\(fileId)/upload-url")!
        var uploadUrlRequest = URLRequest(url: uploadUrlEndpoint)
        AnalyticsPlatformHeader.apply(to: &uploadUrlRequest)
        uploadUrlRequest.httpMethod = "POST"
        uploadUrlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        uploadUrlRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        uploadUrlRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "mimeType": mimeType,
            "fileSize": newFileData.count
        ])

        let (uploadUrlData, uploadUrlResponse) = try await URLSession.shared.data(for: uploadUrlRequest)

        guard let httpResponse = uploadUrlResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid response type")
            throw AttachmentError.uploadFailed
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            PrivacyLogger.error("AttachmentService", code: "replacement_url_failed", status: httpResponse.statusCode)
            throw AttachmentError.uploadFailed
        }

        // Parse upload URL response
        struct UploadUrlResponse: Codable {
            let uploadUrl: String
            let pathname: String
            let headers: [String: String]
            let oldBlobUrl: String?
        }

        let decoder = JSONDecoder()
        let uploadUrlInfo = try decoder.decode(UploadUrlResponse.self, from: uploadUrlData)

        PrivacyLogger.debug("AttachmentService", "replacement_url=received")
        uploadProgress = 0.2

        // Step 2: Upload directly to Vercel Blob
        print("📤 [AttachmentService] Step 2: Uploading to Vercel Blob...")
        guard let blobUrl = URL(string: uploadUrlInfo.uploadUrl) else {
            print("❌ [AttachmentService] Invalid blob URL")
            throw AttachmentError.uploadFailed
        }

        var blobRequest = URLRequest(url: blobUrl)
        blobRequest.httpMethod = "PUT"
        for (key, value) in uploadUrlInfo.headers {
            blobRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (blobData, blobResponse) = try await URLSession.shared.upload(for: blobRequest, from: newFileData)

        guard let blobHttpResponse = blobResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid blob response type")
            throw AttachmentError.uploadFailed
        }

        print("📡 [AttachmentService] Blob upload status: \(blobHttpResponse.statusCode)")

        guard (200...299).contains(blobHttpResponse.statusCode) else {
            PrivacyLogger.error("AttachmentService", code: "replacement_blob_failed", status: blobHttpResponse.statusCode)
            throw AttachmentError.uploadFailed
        }

        // Parse blob response to get the final URL
        struct BlobUploadResponse: Codable {
            let url: String
            let pathname: String
        }

        let blobResult = try decoder.decode(BlobUploadResponse.self, from: blobData)
        PrivacyLogger.debug("AttachmentService", "replacement_blob=uploaded")
        uploadProgress = 0.8

        // Step 3: Confirm upload with our server
        print("📤 [AttachmentService] Step 3: Confirming upload...")
        let confirmEndpoint = URL(string: Constants.API.baseURL + "/api/v1/secure-files/\(fileId)/confirm-upload")!
        var confirmRequest = URLRequest(url: confirmEndpoint)
        AnalyticsPlatformHeader.apply(to: &confirmRequest)
        confirmRequest.httpMethod = "POST"
        confirmRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        confirmRequest.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        confirmRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "blobUrl": blobResult.url,
            "mimeType": mimeType,
            "fileSize": newFileData.count,
            "oldBlobUrl": uploadUrlInfo.oldBlobUrl ?? ""
        ])

        let (confirmData, confirmResponse) = try await URLSession.shared.data(for: confirmRequest)

        guard let confirmHttpResponse = confirmResponse as? HTTPURLResponse else {
            print("❌ [AttachmentService] Invalid confirm response type")
            throw AttachmentError.uploadFailed
        }

        guard (200...299).contains(confirmHttpResponse.statusCode) else {
            PrivacyLogger.error("AttachmentService", code: "confirm_failed", status: confirmHttpResponse.statusCode)
            throw AttachmentError.uploadFailed
        }

        // Parse confirm response
        struct ConfirmResponse: Codable {
            let id: String
            let originalName: String
            let mimeType: String
            let fileSize: Int
            let updatedAt: String
            let success: Bool
        }

        let confirmResult = try decoder.decode(ConfirmResponse.self, from: confirmData)

        // Invalidate cached download for this file
        invalidateCache(for: fileId)

        PrivacyLogger.debug("AttachmentService", "update=complete")
        uploadProgress = 1.0

        // Notify that file was updated
        NotificationCenter.default.post(
            name: .attachmentUpdated,
            object: nil,
            userInfo: ["fileId": fileId]
        )

        return SecureFile(
            id: confirmResult.id,
            name: confirmResult.originalName,
            size: confirmResult.fileSize,
            mimeType: confirmResult.mimeType
        )
    }

    /// Invalidate cached data for a file (used after updates)
    func invalidateCache(for fileId: String) {
        let cachedPath = downloadCacheDirectory.appendingPathComponent(fileId)
        try? fileManager.removeItem(at: cachedPath)
        print("🗑️ [AttachmentService] Invalidated cache for: \(fileId)")
    }

    // MARK: - Delete

    func deleteAttachment(taskId: String, attachmentId: String) async throws {
        let url = URL(string: Constants.API.baseURL + "/api/v1/tasks/\(taskId)/attachments/\(attachmentId)")!
        var request = URLRequest(url: url)
        AnalyticsPlatformHeader.apply(to: &request)
        request.httpMethod = "DELETE"
        
        // Add session cookie
        if let sessionCookie = try? KeychainService.shared.getSessionCookie() {
            request.setValue(sessionCookie, forHTTPHeaderField: "Cookie")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
    }
    
    // MARK: - Shared Files (from Share Extension)

    /// Upload file from shared container (created by Share Extension)
    /// Used by main app to process files shared via system share sheet
    func uploadSharedFile(fileURL: URL, fileName: String, mimeType: String, taskId: String) async throws -> Attachment {
        PrivacyLogger.debug("AttachmentService", "shared_upload=started")

        // Read file data from shared container
        let fileData = try Data(contentsOf: fileURL)

        // Upload using standard method
        let attachment = try await uploadAttachment(
            taskId: taskId,
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType
        )

        // Clean up shared file after successful upload
        try? ShareDataManager.shared.deleteSharedFile(at: fileURL)
        print("✅ [AttachmentService] Shared file uploaded and cleaned up")

        return attachment
    }

    // MARK: - Helpers

    func getMimeType(for fileExtension: String) -> String {
        if let type = UTType(filenameExtension: fileExtension) {
            return type.preferredMIMEType ?? "application/octet-stream"
        }
        return "application/octet-stream"
    }
}

enum AttachmentError: LocalizedError {
    case invalidURL
    case uploadFailed
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid attachment URL"
        case .uploadFailed:
            return "Failed to upload attachment"
        case .downloadFailed:
            return "Failed to download attachment"
        }
    }
}

// MARK: - Upload Progress Delegate

/// Delegate for tracking upload progress
class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    private let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(progress)
    }
}
