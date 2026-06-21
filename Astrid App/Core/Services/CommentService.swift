import Foundation
import Combine
import CoreData
import os.log

private let logger = Logger(subsystem: "com.graceful-tools.astrid", category: "CommentService")

/// Errors that can occur during comment sync
enum CommentSyncError: Error {
    case attachmentPending  // Attachment upload not complete yet - will retry later
    case taskPending        // Parent task created offline hasn't synced yet - will retry later
}

/// Resolves a pending comment's task id before it's sent to the server.
///
/// A comment created against an offline-created task carries that task's
/// temporary id (`temp_<uuid>`). It must be mapped to the real server id once
/// the task syncs; until then the comment must wait — sending it to `temp_…`
/// 404s, and a 404 is treated as a permanent failure (so the photo would be
/// dropped forever). Pure so it's unit-testable.
enum PendingCommentResolver {
    enum TaskIdResolution: Equatable {
        case ready(String)
        case taskNotSyncedYet
    }

    static func resolveTaskId(_ taskId: String, realIdProvider: (String) -> String?) -> TaskIdResolution {
        guard taskId.hasPrefix("temp_") else { return .ready(taskId) }
        if let real = realIdProvider(taskId), !real.hasPrefix("temp_") {
            return .ready(real)
        }
        return .taskNotSyncedYet
    }
}

@MainActor
class CommentService: ObservableObject {
    static let shared = CommentService()

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0

    private let apiClient = AstridAPIClient.shared
    private let coreDataManager = CoreDataManager.shared
    private let networkMonitor = NetworkMonitor.shared
    @Published public var cachedComments: [String: [Comment]] = [:] // taskId -> comments
    private var lastFetchTime: [String: Date] = [:] // taskId -> last fetch time
    private var inFlightFetches: [String: _Concurrency.Task<[Comment], Error>] = [:] // taskId -> active network fetch
    private var networkObserver: NSObjectProtocol?
    private var attachmentUploadObserver: NSObjectProtocol?
    private var taskResolvedObserver: NSObjectProtocol?

    init() {
        // Load cached comments on initialization
        _Concurrency.Task { @MainActor in
            await self.loadCachedComments()
            await self.updatePendingOperationsCount()
        }

        // Setup network observer to sync when connection is restored
        setupNetworkObserver()
    }

    deinit {
        if let observer = networkObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = attachmentUploadObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = taskResolvedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Setup network observer to sync when connection is restored
    private func setupNetworkObserver() {
        networkObserver = NotificationCenter.default.addObserver(
            forName: .networkDidBecomeAvailable,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                try? await self?.syncPendingComments()
            }
        }

        // Re-sync when an attachment upload completes — pending comments
        // that were waiting for `pendingFileId` to resolve (offline flow:
        // attachment uploaded after the comment was queued) only retry on
        // the next network event without this. Mirrors ChatService:60.
        attachmentUploadObserver = NotificationCenter.default.addObserver(
            forName: .attachmentUploadCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                try? await self?.syncPendingComments()
            }
        }

        // Re-sync when an offline-created task gets its real server id — a
        // photo-comment queued against the temp task id can now be posted to
        // the real task instead of waiting (otherwise the attachment "disappears"
        // until the next manual sync).
        taskResolvedObserver = NotificationCenter.default.addObserver(
            forName: .taskTempIdResolved,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            _Concurrency.Task { @MainActor in
                try? await self?.syncPendingComments()
            }
        }
    }

    // MARK: - Cache Management

    /// Clean up corrupted comments from old buggy data
    /// Deletes comments with: empty IDs, nil authorId (except system comments have content starting with specific patterns)
    private func cleanupCorruptedComments() async {
        do {
            let deletedCount: Int = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        // Fetch ALL comments to check for corruption
                        let fetchRequest = CDComment.fetchRequest()
                        let allComments = try context.fetch(fetchRequest)

                        var corruptedComments: [CDComment] = []

                        for comment in allComments {
                            // Delete if empty ID
                            if comment.id.isEmpty {
                                corruptedComments.append(comment)
                                continue
                            }

                            // Delete if nil authorId (legacy corrupted data)
                            // Real system comments are rare and have specific content patterns
                            if comment.authorId == nil {
                                corruptedComments.append(comment)
                                continue
                            }
                        }

                        if corruptedComments.isEmpty {
                            continuation.resume(returning: 0)
                            return
                        }

                        // Delete corrupted comments
                        for comment in corruptedComments {
                            context.delete(comment)
                        }

                        try context.save()
                        continuation.resume(returning: corruptedComments.count)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            if deletedCount > 0 {
                logger.notice("CLEANUP: Deleted \(deletedCount, privacy: .public) corrupted comments (empty IDs or nil authorId)")
            }
        } catch {
            logger.error("CLEANUP FAILED: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Load cached comments from CoreData on startup (async, non-blocking)
    /// CRITICAL: Must convert to domain models INSIDE the context to avoid faulted objects
    private func loadCachedComments() async {
        let startTime = Date()

        // CRITICAL: Wait for CoreData persistent store to be ready
        await coreDataManager.waitForStoreLoad()

        // Clean up corrupted comments (empty IDs) from old data
        await cleanupCorruptedComments()

        do {
            // Load from CoreData in background and convert to domain models INSIDE context
            let commentsByTask: [String: [Comment]] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let cdComments = try CDComment.fetchAll(context: context)

                        // CRITICAL: Convert to domain models INSIDE context block
                        // Otherwise managed objects are faulted and return nil for properties
                        var result: [String: [Comment]] = [:]
                        for cdComment in cdComments {
                            let comment = cdComment.toDomainModel()
                            if result[comment.taskId] == nil {
                                result[comment.taskId] = []
                            }
                            result[comment.taskId]?.append(comment)
                        }

                        // Sort comments within each task by createdAt
                        for (taskId, comments) in result {
                            result[taskId] = comments.sorted { c1, c2 in
                                guard let date1 = c1.createdAt, let date2 = c2.createdAt else {
                                    return false
                                }
                                return date1 < date2
                            }
                        }

                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.cachedComments = commentsByTask

            let totalComments = commentsByTask.values.reduce(0) { $0 + $1.count }
            let duration = Date().timeIntervalSince(startTime)
            if totalComments > 0 || duration > 1.0 {
                // Only log if there's something interesting (comments loaded or slow startup)
                logger.notice("Comments loaded: \(totalComments, privacy: .public) comments for \(commentsByTask.count, privacy: .public) tasks in \(String(format: "%.0f", duration * 1000), privacy: .public)ms")
            }
        } catch {
            logger.error("Failed to load cached comments: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Update the count of pending operations (for UI indicators)
    private func updatePendingOperationsCount() async {
        do {
            let pending: [CDComment] = try await withCheckedThrowingContinuation { continuation in
                coreDataManager.persistentContainer.performBackgroundTask { context in
                    do {
                        let comments = try CDComment.fetchPending(context: context)
                        continuation.resume(returning: comments)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            pendingOperationsCount = pending.count
        } catch {
            logger.error("Failed to count pending operations: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Fetching

    /// Fetch comments with cache hierarchy: Memory → CoreData → Network
    /// Network results are always saved to CoreData for offline access
    func fetchComments(taskId: String, useCache: Bool = true) async throws -> [Comment] {
        logger.notice("===== fetchComments: \(taskId.prefix(8), privacy: .public) =====")

        // STEP 1: Check memory cache first (instant)
        // We check if the key exists, even if the array is empty, to avoid infinite loops
        if useCache, let cached = cachedComments[taskId] {
            logger.notice("✓ MEMORY: \(cached.count, privacy: .public) comments")
            backgroundRefreshFromNetwork(taskId: taskId)
            return cached
        }

        // STEP 2: Check CoreData (fast, persisted)
        if useCache {
            await coreDataManager.waitForStoreLoad()
            let coreDataComments = try await loadCommentsFromCoreData(taskId: taskId)
            
            // If we found comments in CoreData, return them and refresh in background
            if !coreDataComments.isEmpty {
                logger.notice("✓ COREDATA: \(coreDataComments.count, privacy: .public) comments")
                cachedComments[taskId] = coreDataComments  // populate memory cache
                backgroundRefreshFromNetwork(taskId: taskId)
                return coreDataComments
            }
        }

        // STEP 3: Fetch from network (slow, requires connection)
        // Dedup: if a fetch for this task is already in-flight, await the existing one
        if let existingTask = inFlightFetches[taskId] {
            logger.notice("→ NETWORK: Awaiting in-flight fetch for \(taskId.prefix(8), privacy: .public)")
            return try await existingTask.value
        }

        logger.notice("→ NETWORK: Fetching...")
        isLoading = true
        errorMessage = nil

        let fetchTask = _Concurrency.Task<[Comment], Error> { [weak self] in
            guard let self = self else { return [] }
            do {
                let response: CommentsListResponse = try await self.apiClient.getTaskComments(taskId: taskId)
                logger.notice("✓ NETWORK: \(response.comments.count, privacy: .public) comments")

                // Update last fetch time
                await MainActor.run { self.lastFetchTime[taskId] = Date() }

                // Save to CoreData for offline access
                try await self.saveCommentsToCoreData(response.comments, taskId: taskId)
                logger.notice("✓ SAVED to CoreData")

                // Update memory cache, preserving pending comments (temp_ IDs not on server yet).
                // Drop any temp whose id matches a clientRequestId in the response — that means
                // the server already accepted the sync and the syncPendingCreate cache swap is
                // racing this fetch.
                await MainActor.run {
                    let acknowledgedTempIds = Set(response.comments.compactMap { $0.clientRequestId })
                    let pendingComments = (self.cachedComments[taskId] ?? []).filter {
                        $0.id.hasPrefix("temp_") && !acknowledgedTempIds.contains($0.id)
                    }
                    var mergedComments = response.comments
                    mergedComments.append(contentsOf: pendingComments)
                    mergedComments.sort { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
                    self.cachedComments[taskId] = mergedComments
                    if !pendingComments.isEmpty {
                        logger.notice("📎 Preserved \(pendingComments.count, privacy: .public) pending comments in cache")
                    }

                    // Notify views to reload comments (for pull-to-refresh updates)
                    NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": taskId])
                }

                return response.comments
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    logger.notice("✗ NETWORK: Cancelled")
                    return []
                }

                logger.error("✗ NETWORK: \(error.localizedDescription, privacy: .public)")
                await MainActor.run { self.errorMessage = error.localizedDescription }
                throw error
            }
        }

        inFlightFetches[taskId] = fetchTask

        do {
            let result = try await fetchTask.value
            inFlightFetches.removeValue(forKey: taskId)
            isLoading = false
            return result
        } catch {
            inFlightFetches.removeValue(forKey: taskId)
            isLoading = false
            throw error
        }
    }

    /// Load comments from CoreData for a specific task
    /// CRITICAL: Must convert to domain models INSIDE the context to avoid faulted objects
    private func loadCommentsFromCoreData(taskId: String) async throws -> [Comment] {
        let comments: [Comment] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let fetchRequest = CDComment.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "taskId == %@", taskId)
                    fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
                    let cdComments = try context.fetch(fetchRequest)

                    // Heal pre-fix duplicates: an offline-sync race could leave two CDComment
                    // rows for the same comment — one with the temp_ id, one synced. Dedup by
                    // grouping (taskId, content, authorId, createdAt-second) and keeping the
                    // non-temp row. Only deletes rows that look like the same comment.
                    var hadChanges = false
                    var keepers: [CDComment] = []
                    var seenSignatures: [String: CDComment] = [:]
                    for cd in cdComments {
                        let createdSecond = cd.createdAt.map { Int($0.timeIntervalSince1970) } ?? 0
                        let signature = "\(cd.taskId)|\(cd.authorId ?? "")|\(cd.content)|\(createdSecond)"
                        if let existing = seenSignatures[signature] {
                            // Keep the non-temp one; if both are non-temp, keep the older inserted (existing)
                            let existingIsTemp = existing.id.hasPrefix("temp_")
                            let currentIsTemp = cd.id.hasPrefix("temp_")
                            if existingIsTemp && !currentIsTemp {
                                context.delete(existing)
                                seenSignatures[signature] = cd
                                if let idx = keepers.firstIndex(where: { $0 === existing }) {
                                    keepers[idx] = cd
                                }
                            } else {
                                context.delete(cd)
                            }
                            hadChanges = true
                        } else {
                            seenSignatures[signature] = cd
                            keepers.append(cd)
                        }
                    }
                    if hadChanges {
                        try context.save()
                        logger.notice("🧹 Removed duplicate CDComment rows for task \(taskId.prefix(8), privacy: .public)")
                    }

                    // CRITICAL: Convert to domain models INSIDE context block
                    // Otherwise managed objects are faulted and return nil for properties
                    let domainComments = keepers.map { $0.toDomainModel() }
                    continuation.resume(returning: domainComments)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return comments
    }

    /// Background refresh from network (fire-and-forget)
    private func backgroundRefreshFromNetwork(taskId: String) {
        // Throttle background refreshes to once every 30 seconds per task
        if let lastFetch = lastFetchTime[taskId], Date().timeIntervalSince(lastFetch) < 30 {
            return
        }
        
        // Update last fetch time immediately to prevent concurrent background refreshes
        lastFetchTime[taskId] = Date()

        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                let response: CommentsListResponse = try await self.apiClient.getTaskComments(taskId: taskId)
                try await self.saveCommentsToCoreData(response.comments, taskId: taskId)
                let count = response.comments.count
                await MainActor.run {
                    // Preserve pending comments (temp_ IDs not on server yet); drop any whose
                    // id matches a clientRequestId echoed by the server — those are already
                    // synced and racing the cache swap in syncPendingCreate.
                    let acknowledgedTempIds = Set(response.comments.compactMap { $0.clientRequestId })
                    let pendingComments = (self.cachedComments[taskId] ?? []).filter {
                        $0.id.hasPrefix("temp_") && !acknowledgedTempIds.contains($0.id)
                    }
                    var mergedComments = response.comments
                    mergedComments.append(contentsOf: pendingComments)
                    mergedComments.sort { ($0.createdAt ?? Date.distantPast) < ($1.createdAt ?? Date.distantPast) }
                    self.cachedComments[taskId] = mergedComments
                    // Log on MainActor to satisfy Swift 6 isolation requirements
                    logger.notice("↻ BACKGROUND: Updated \(count, privacy: .public) comments, preserved \(pendingComments.count, privacy: .public) pending")
                    // Notify views to reload comments (for background refresh updates)
                    NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": taskId])
                }
            } catch {
                // Silent fail - already returned cached data
            }
        }
    }

    /// Create a new comment (local-first with optimistic update)
    func createComment(taskId: String, content: String, type: Comment.CommentType = .TEXT, fileId: String? = nil, parentCommentId: String? = nil, authorId: String? = nil) async throws -> Comment {
        // 1. Generate temp ID for optimistic update
        let tempId = "temp_\(UUID().uuidString)"

        // 2. Look up attachment info for temp fileIds (for offline display)
        var secureFiles: [SecureFile]? = nil
        if let tempFileId = fileId, tempFileId.hasPrefix("temp_") {
            if let pending = AttachmentService.shared.pendingUploads[tempFileId] {
                // Create SecureFile from pending attachment info for immediate display
                let secureFile = SecureFile(
                    id: tempFileId,
                    name: pending.fileName,
                    size: pending.fileSize,
                    mimeType: pending.mimeType
                )
                secureFiles = [secureFile]
            }
        }

        // 3. Create optimistic comment object WITH attachment info
        let optimisticComment = Comment(
            id: tempId,
            content: content,
            type: type,
            authorId: authorId,
            author: nil,
            taskId: taskId,
            createdAt: Date(),
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: parentCommentId,
            replies: nil,
            secureFiles: secureFiles
        )

        // 4. Save to Core Data with pending status
        // CRITICAL: Must await save completion before syncing to avoid race condition
        let savedFileId = fileId  // Capture for closure
        let savedContent = content
        let savedType = type.rawValue
        let savedAuthorId = authorId
        let savedTaskId = taskId

        // Serialize secureFiles for CoreData storage
        var secureFilesJson: String? = nil
        if let files = secureFiles, !files.isEmpty {
            if let jsonData = try? JSONEncoder().encode(files),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                secureFilesJson = jsonString
            }
        }

        do {
            try await coreDataManager.saveInBackground { context in
                let cdComment = CDComment(context: context)
                cdComment.id = tempId
                cdComment.content = savedContent
                cdComment.type = savedType
                cdComment.authorId = savedAuthorId
                cdComment.taskId = savedTaskId
                cdComment.createdAt = Date()
                cdComment.updatedAt = Date()
                cdComment.syncStatus = "pending"
                cdComment.pendingOperation = "create"
                cdComment.syncAttempts = 0
                cdComment.pendingFileId = savedFileId  // Store fileId for sync
                cdComment.secureFilesData = secureFilesJson  // Store attachment info for display
            }

            // Update pending count
            await updatePendingOperationsCount()
        } catch {
            logger.error("Failed to save pending comment: \(error.localizedDescription, privacy: .public)")
        }

        // 4. Update in-memory cache immediately
        if cachedComments[taskId] == nil {
            cachedComments[taskId] = []
        }
        cachedComments[taskId]?.append(optimisticComment)

        // 5. Trigger background sync (fire-and-forget) - AFTER save completes
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingComments()
            }
        }

        // 6. Return optimistic comment immediately
        return optimisticComment
    }

    /// Update a comment (local-first with optimistic update)
    func updateComment(id: String, content: String) async throws -> Comment {

        // 1. Create updated comment object
        let updatedComment = Comment(
            id: id,
            content: content,
            type: .TEXT, // Preserve existing type
            authorId: nil,
            author: nil,
            taskId: "", // Will be populated from cache
            createdAt: nil,
            updatedAt: Date(),
            attachmentUrl: nil,
            attachmentName: nil,
            attachmentType: nil,
            attachmentSize: nil,
            parentCommentId: nil,
            replies: nil,
            secureFiles: nil
        )

        // 2. Update in-memory cache immediately
        for (taskId, comments) in cachedComments {
            if let index = comments.firstIndex(where: { $0.id == id }) {
                var updated = comments[index]
                updated.content = content
                updated.updatedAt = Date()
                cachedComments[taskId]?[index] = updated
                break
            }
        }

        // 3. Save to Core Data with pending status (non-blocking)
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coreDataManager.saveInBackground { context in
                    guard let cdComment = try CDComment.fetchById(id, context: context) else { return }
                    cdComment.pendingContent = content
                    cdComment.syncStatus = "pending_update"
                    cdComment.pendingOperation = "update"
                    cdComment.updatedAt = Date()
                    cdComment.syncAttempts = 0
                }
                await self.updatePendingOperationsCount()
            } catch {
                // Silent fail - will retry on next sync
            }
        }

        // 4. Trigger background sync (fire-and-forget)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingComments()
            }
        }

        return updatedComment
    }

    /// Delete a comment (local-first with optimistic update)
    func deleteComment(id: String) async throws {
        // 1. Remove from in-memory cache immediately (optimistic)
        for (taskId, comments) in cachedComments {
            if let index = comments.firstIndex(where: { $0.id == id }) {
                cachedComments[taskId]?.remove(at: index)
                break
            }
        }

        // 2. Mark as pending delete in Core Data (non-blocking)
        _Concurrency.Task.detached { [weak self] in
            guard let self = self else { return }
            do {
                try await self.coreDataManager.saveInBackground { context in
                    guard let cdComment = try CDComment.fetchById(id, context: context) else { return }
                    cdComment.syncStatus = "pending_delete"
                    cdComment.pendingOperation = "delete"
                    cdComment.syncAttempts = 0
                }
                await self.updatePendingOperationsCount()
            } catch {
                // Silent fail - will retry on next sync
            }
        }

        // 3. Trigger background sync (fire-and-forget)
        if networkMonitor.isConnected {
            _Concurrency.Task.detached { [weak self] in
                try? await self?.syncPendingComments()
            }
        }
    }

    // MARK: - Background Sync

    /// Data extracted from CDComment for sync operations (to avoid CoreData context faulting)
    private struct PendingCommentData {
        let id: String
        let taskId: String
        let content: String
        let type: String
        let operation: String
        let pendingContent: String?
        let pendingFileId: String?  // For attachment uploads
        let createdAt: Date?  // Client timestamp for correct ordering
    }

    /// Sync all pending comment operations (create, update, delete) with the server
    func syncPendingComments() async throws {
        guard networkMonitor.isConnected else { return }

        // Fetch all pending comments from Core Data - extract data INSIDE context to avoid faulting
        let pendingData: [PendingCommentData] = try await withCheckedThrowingContinuation { continuation in
            coreDataManager.persistentContainer.performBackgroundTask { context in
                do {
                    let comments = try CDComment.fetchPending(context: context)

                    // CRITICAL: Extract all data INSIDE context before objects become faulted
                    let extracted = comments.map { cdComment in
                        PendingCommentData(
                            id: cdComment.id,
                            taskId: cdComment.taskId,
                            content: cdComment.content,
                            type: cdComment.type,
                            operation: cdComment.pendingOperation ?? "unknown",
                            pendingContent: cdComment.pendingContent,
                            pendingFileId: cdComment.pendingFileId,
                            createdAt: cdComment.createdAt
                        )
                    }
                    continuation.resume(returning: extracted)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }

        guard !pendingData.isEmpty else { return }

        // Process each pending operation using extracted data
        for data in pendingData {
            do {
                switch data.operation {
                case "create":
                    try await syncPendingCreate(data)
                case "update":
                    try await syncPendingUpdate(data)
                case "delete":
                    try await syncPendingDelete(data)
                default:
                    try await markAsFailed(id: data.id, error: "Unknown operation type")
                }
            } catch CommentSyncError.attachmentPending {
                // Attachment still uploading - will retry automatically
            } catch CommentSyncError.taskPending {
                // Parent task (created offline) hasn't synced yet - will retry automatically
            } catch {
                logger.error("Failed to sync \(data.operation, privacy: .public): \(error.localizedDescription, privacy: .public)")

                // Detect permanent HTTP errors (403/404/410) — no point retrying these
                let isPermanent: Bool
                if case APIError.httpError(let code, _) = error, [403, 404, 410].contains(code) {
                    isPermanent = true
                } else if case AstridAPIError.httpError(let code, _) = error, [403, 404, 410].contains(code) {
                    isPermanent = true
                } else {
                    isPermanent = false
                }

                if isPermanent {
                    logger.notice("🚫 Permanently failed comment \(data.id.prefix(8), privacy: .public) — will not retry")
                    try await markAsFailed(id: data.id, error: error.localizedDescription)
                } else {
                    try await markAsRetryable(id: data.id, error: error.localizedDescription)
                }
            }
        }

        await updatePendingOperationsCount()

        // Notify views to reload comments (updates UI after sync replaces temp IDs)
        NotificationCenter.default.post(name: .commentDidSync, object: nil)
    }

    /// Sync a pending create operation
    private func syncPendingCreate(_ data: PendingCommentData) async throws {
        // Resolve a temp task id (offline-created task) to its real server id.
        // The task syncs before comments do, so the mapping is available; if it
        // isn't yet, wait and retry rather than POSTing to a temp_ id (which
        // 404s → permanent failure → the photo/comment is dropped forever).
        let resolvedTaskId: String
        switch PendingCommentResolver.resolveTaskId(data.taskId, realIdProvider: { TaskService.shared.mappedRealTaskId(for: $0) }) {
        case .ready(let id):
            resolvedTaskId = id
        case .taskNotSyncedYet:
            throw CommentSyncError.taskPending
        }

        // Resolve temp fileId to real fileId if needed
        var resolvedFileId = data.pendingFileId
        if let tempFileId = data.pendingFileId, tempFileId.hasPrefix("temp_") {
            if let realFileId = AttachmentService.shared.getRealFileId(for: tempFileId) {
                resolvedFileId = realFileId
            } else if AttachmentService.shared.isPendingUpload(tempFileId) {
                throw CommentSyncError.attachmentPending
            } else {
                // Attachment not found - sync without it
                resolvedFileId = nil
            }
        }

        // Call API to create comment (pass client createdAt for correct ordering).
        // The temp ID (data.id, "temp_<UUID>") doubles as the idempotency key — it's
        // already persisted on CDComment.id, so any retry of this same pending row
        // sends the same key, and the server returns the existing comment instead of
        // creating a duplicate. This is the airplane-mode fix for the Bam-x4 bug.
        let response = try await apiClient.createComment(
            taskId: resolvedTaskId,
            content: data.content,
            type: Comment.CommentType(rawValue: data.type) ?? .TEXT,
            fileId: resolvedFileId,
            parentCommentId: nil,
            createdAt: data.createdAt,
            clientRequestId: data.id
        )

        // Update Core Data with server ID and mark as synced. Also migrate the
        // row to the real task id so it's correctly associated after an
        // offline-created task syncs.
        let oldId = data.id
        let newTaskId = resolvedTaskId
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(oldId, context: context) else { return }
            comment.id = response.comment.id
            comment.taskId = newTaskId
            comment.syncStatus = "synced"
            comment.lastSyncedAt = Date()
            comment.pendingOperation = nil
            comment.pendingContent = nil
            comment.syncAttempts = 0
            comment.syncError = nil
        }

        // Update in-memory cache: replace the temp comment, moving it from the
        // temp-task bucket to the real-task bucket if the id changed.
        if var oldBucket = cachedComments[data.taskId],
           let index = oldBucket.firstIndex(where: { $0.id == oldId }) {
            oldBucket.remove(at: index)
            cachedComments[data.taskId] = oldBucket
        }
        if resolvedTaskId != data.taskId || cachedComments[resolvedTaskId] != nil {
            var newBucket = cachedComments[resolvedTaskId] ?? []
            if !newBucket.contains(where: { $0.id == response.comment.id }) {
                newBucket.append(response.comment)
            }
            cachedComments[resolvedTaskId] = newBucket
        }
    }

    /// Sync a pending update operation
    private func syncPendingUpdate(_ data: PendingCommentData) async throws {
        guard let updatedContent = data.pendingContent else { return }

        _ = try await apiClient.updateComment(
            commentId: data.id,
            content: updatedContent
        )

        let commentId = data.id
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(commentId, context: context) else { return }
            comment.content = updatedContent
            comment.syncStatus = "synced"
            comment.lastSyncedAt = Date()
            comment.pendingOperation = nil
            comment.pendingContent = nil
            comment.syncAttempts = 0
            comment.syncError = nil
        }
    }

    /// Sync a pending delete operation
    private func syncPendingDelete(_ data: PendingCommentData) async throws {
        let _ = try await apiClient.deleteComment(commentId: data.id)

        let commentId = data.id
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(commentId, context: context) else { return }
            context.delete(comment)
        }
    }

    /// Mark a comment as failed after sync error
    private func markAsFailed(id: String, error: String) async throws {
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(id, context: context) else { return }
            comment.syncStatus = "failed"
            comment.syncAttempts = CDComment.maxSyncAttempts
            comment.syncError = error
        }
    }

    /// Record a transient sync failure with exponential backoff
    private func markAsRetryable(id: String, error: String) async throws {
        try await coreDataManager.saveInBackground { context in
            guard let comment = try CDComment.fetchById(id, context: context) else { return }
            comment.recordSyncFailure(error: error)
        }
    }
}

// MARK: - Response Models

struct CommentsListResponse: Codable {
    let comments: [Comment]
    let meta: MetaInfo
}

struct CommentResponse: Codable {
    let comment: Comment
    let meta: MetaInfo
}

struct DeleteResponse: Codable {
    let success: Bool?
    let message: String?
    let meta: MetaInfo?
}

struct MetaInfo: Codable {
    let apiVersion: String?
    let authSource: String?
}

// MARK: - CoreData Persistence (Extension)

extension CommentService {
    /// Save multiple comments to CoreData for a specific task
    private func saveCommentsToCoreData(_ comments: [Comment], taskId: String) async throws {
        logger.notice("💾 Starting CoreData save for task \(taskId.prefix(8), privacy: .public)")
        logger.notice("💾 Comments to save: \(comments.count, privacy: .public)")

        // CRITICAL: Wait for CoreData persistent store to be ready
        await coreDataManager.waitForStoreLoad()

        let startTime = Date()

        try await coreDataManager.saveInBackground { context in
            // Fetch all existing comments for this task in ONE batch query.
            // Also include temp_ ids the server echoes back as clientRequestId — those
            // identify the still-renaming pending row from a racing syncPendingCreate.
            let commentIds = comments.map { $0.id }
            let acknowledgedTempIds = comments.compactMap { $0.clientRequestId }
                .filter { $0.hasPrefix("temp_") }
            let lookupIds = Array(Set(commentIds + acknowledgedTempIds))

            let fetchRequest = CDComment.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", lookupIds)
            let existingComments = try context.fetch(fetchRequest)

            // Create dictionary for O(1) lookup
            var existingCommentsDict = [String: CDComment]()
            for cdComment in existingComments {
                existingCommentsDict[cdComment.id] = cdComment
            }

            let newCommentsCount = comments.count - existingComments.count
            logger.notice("💾 Will update \(existingComments.count, privacy: .public) existing, create \(newCommentsCount, privacy: .public) new")

            // Update or create comments, skipping unchanged ones
            var updatedCount = 0
            var createdCount = 0
            var skippedCount = 0

            for comment in comments {
                // Prefer the row indexed by server id; fall back to the temp_ row that
                // matches this comment's clientRequestId. Renaming the temp row in place
                // prevents leaving a duplicate after syncPendingCreate later swaps its id.
                let existing = existingCommentsDict[comment.id]
                    ?? (comment.clientRequestId.flatMap { existingCommentsDict[$0] })

                if let existing = existing {
                    // Skip if updatedAt hasn't changed (comment is identical) AND ids match
                    if existing.id == comment.id,
                       let existingUpdatedAt = existing.updatedAt,
                       let commentUpdatedAt = comment.updatedAt,
                       existingUpdatedAt == commentUpdatedAt {
                        skippedCount += 1
                        continue
                    }
                    existing.id = comment.id
                    existing.update(from: comment)
                    existing.taskId = taskId
                    existing.syncStatus = "synced"
                    existing.lastSyncedAt = Date()
                    existing.pendingOperation = nil
                    existing.pendingContent = nil
                    existing.pendingFileId = nil
                    existing.syncAttempts = 0
                    existing.syncError = nil
                    updatedCount += 1
                } else {
                    let cdComment = CDComment(context: context)
                    cdComment.id = comment.id
                    cdComment.update(from: comment)
                    cdComment.taskId = taskId
                    cdComment.syncStatus = "synced"
                    cdComment.lastSyncedAt = Date()
                    createdCount += 1
                }
            }

            logger.notice("💾 CoreData: updated \(updatedCount, privacy: .public), created \(createdCount, privacy: .public), skipped \(skippedCount, privacy: .public) unchanged comments")
        }

        let duration = Date().timeIntervalSince(startTime)
        logger.notice("✅ CoreData save completed in \(String(format: "%.0f", duration * 1000), privacy: .public)ms for \(comments.count, privacy: .public) comments")
    }

    /// Save single comment to CoreData
    private func saveCommentToCoreData(_ comment: Comment, syncStatus: String = "synced") async throws {
        try await coreDataManager.saveInBackground { context in
            let cdComment = try CDComment.fetchById(comment.id, context: context) ?? CDComment(context: context)
            cdComment.id = comment.id
            cdComment.update(from: comment)
            cdComment.syncStatus = syncStatus
            if syncStatus == "synced" {
                cdComment.lastSyncedAt = Date()
            }
        }
    }

    /// Retry all failed operations
    func retryFailedOperations() async {
        do {
            try await coreDataManager.saveInBackground { context in
                let request = CDComment.fetchRequest()
                request.predicate = NSPredicate(format: "syncStatus == %@", "failed")
                let failedComments = try context.fetch(request)
                for comment in failedComments {
                    comment.syncAttempts = 0
                    comment.syncStatus = "pending"
                    comment.syncError = nil
                }
            }
            try await syncPendingComments()
        } catch {
            logger.error("Failed to retry operations: \(error.localizedDescription, privacy: .public)")
        }
    }
}
