import AstridCore
import Combine
import Foundation

/// The comments the task views draw, and every way to write one — through astrid-core.
///
/// The core holds each task's comments in its cache and journals every write (a post, an edit, a
/// delete, a photo's upload and the comment that carries it) to go out when it can
/// (docs/CORE_MIGRATION.md). This service keeps the per-task buckets the views bind to and reads
/// them back when the core says a task's comments moved — the live stream, a sync pass, a
/// delivery.
@MainActor
class CommentService: ObservableObject {
    static let shared = CommentService()

    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Comment writes waiting to reach the server.
    @Published var pendingOperationsCount: Int = 0
    @Published var failedOperationsCount: Int = 0
    /// taskId → its comments, oldest first, flat (`CommentThread` nests the replies).
    @Published public var cachedComments: [String: [Comment]] = [:]
    /// taskId → the agent writing a reply there right now.
    @Published var typingAgent: [String: String] = [:]

    private var core: CoreSession { AppCore.shared.session }
    /// When each task's comments were last asked of the server, so opening a task twice in a
    /// minute does not fetch twice.
    private var lastFetchTime: [String: Date] = [:]
    /// Temp comment ids the views may still hold, and the real ids they became.
    private var tempCommentIdMapping: [String: String] = [:]

    init() {}

    // MARK: - Reading

    /// A task's comments: the cache at once, then the server's — the cached copy refreshed in the
    /// background when there is one, awaited when there is not.
    func fetchComments(taskId: String, useCache: Bool = true) async throws -> [Comment] {
        let cached = await read(taskId: taskId)
        if useCache, !cached.isEmpty {
            backgroundRefresh(taskId: taskId)
            return cached
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            lastFetchTime[taskId] = Date()
            try await core.run(CoreCommand(kind: "refreshComments", taskId: taskId))
        } catch {
            // Offline: the cache is the answer.
            errorMessage = error.localizedDescription
        }
        return await read(taskId: taskId)
    }

    /// What the core holds for `taskId`, published into its bucket.
    @discardableResult
    private func read(taskId: String) async -> [Comment] {
        guard let comments = try? await core.run(CoreCommand(kind: "comments", taskId: taskId),
                                                 as: [Comment].self) else {
            return cachedComments[taskId] ?? []
        }
        await learnResolvedIds(in: taskId)
        if cachedComments[taskId] != comments {
            cachedComments[taskId] = comments
            // A reply from an agent is the end of its typing, whatever the stream said.
            if comments.last?.author?.isAIAgent == true { typingAgent[taskId] = nil }
            NotificationCenter.default.post(name: .commentDidSync, object: nil, userInfo: ["taskId": taskId])
        }
        return comments
    }

    /// Ask the server again, at most every 30 seconds per task.
    private func backgroundRefresh(taskId: String) {
        if let last = lastFetchTime[taskId], Date().timeIntervalSince(last) < 30 { return }
        lastFetchTime[taskId] = Date()
        _Concurrency.Task {
            try? await core.run(CoreCommand(kind: "refreshComments", taskId: taskId))
            await read(taskId: taskId)
        }
    }

    /// The core says a task's comments moved: read back the ones a view is showing.
    func coreDidChange(_ change: CoreChange) {
        switch change {
        case .comments(let taskId) where cachedComments[taskId] != nil:
            _Concurrency.Task { await self.read(taskId: taskId) }
        case .agentTyping(_, let taskId?, let agentName, let active):
            typingAgent[taskId] = active ? (agentName ?? "Agent") : nil
        case .delivered(let delivery) where !delivery.undescribed:
            // The threads a delivery touched, of those a view is showing (AITD-454).
            for taskId in delivery.commentTaskIds where cachedComments[taskId] != nil {
                _Concurrency.Task { await self.read(taskId: taskId) }
            }
        case .synced, .unknown, .delivered:
            // A delivery or a pass that could not say what moved: the open threads, again.
            for taskId in cachedComments.keys {
                _Concurrency.Task { await self.read(taskId: taskId) }
            }
            refreshOutboxCounts()
        default:
            break
        }
    }

    /// Temp comment and file ids in a bucket that have become real: remember which, and tell the
    /// attachment cache so a thumbnail drawn under the temp id follows the file to its real one.
    private func learnResolvedIds(in taskId: String) async {
        let comments = cachedComments[taskId] ?? []
        let tempComments = comments.map(\.id).filter { $0.hasPrefix("temp_") }
        let tempFiles = comments.flatMap { $0.secureFiles ?? [] }.map(\.id).filter { $0.hasPrefix("temp_") }
        let temps = tempComments + tempFiles
        guard !temps.isEmpty,
              let moved = try? await core.run(CoreCommand.resolveIds(temps), as: [String: String].self)
        else { return }
        for (temp, real) in moved {
            if tempFiles.contains(temp) {
                AttachmentService.shared.recordOutboxUpload(tempFileId: temp, realFileId: real)
            } else {
                tempCommentIdMapping[temp] = real
            }
        }
    }

    /// Real server id for a temporary (offline-created) comment id, once it has synced.
    func mappedRealCommentId(for tempId: String) -> String? {
        tempCommentIdMapping[tempId]
    }

    // MARK: - Writing

    /// Post a comment — at once in the thread, to the server when it can.
    ///
    /// - Parameters:
    ///   - fileId: a file to carry. A temporary one is a file the person just picked, staged by
    ///     `AttachmentService`: the core copies it, uploads it, and posts the comment once the
    ///     upload answers, all through its journal.
    ///   - clientRequestId: the id of the row a view already drew for this comment (AITD-331); it
    ///     becomes the comment's id until the server answers.
    func createComment(
        taskId: String, content: String, type: Comment.CommentType = .TEXT, fileId: String? = nil,
        parentCommentId: String? = nil, authorId: String? = nil, clientRequestId: String? = nil
    ) async throws -> Comment {
        let rowId = clientRequestId ?? "temp_\(UUID().uuidString)"
        let command: CoreCommand
        if let fileId, fileId.hasPrefix("temp_"),
           let staged = AttachmentService.shared.pendingUploads[fileId] {
            command = Self.attachFile(taskId: taskId, staged: staged, content: content,
                                      commentId: rowId, parentCommentId: parentCommentId)
        } else {
            var post = CoreCommand(kind: "postComment", [
                "taskId": .value(taskId), "content": .value(content), "type": .value(type.rawValue),
                "clientRequestId": .value(rowId),
            ])
            post.set("fileId", fileId)
            post.set("parentCommentId", parentCommentId)
            post.set("authorId", authorId)
            command = post
        }
        let comment = try await core.run(command, as: Comment.self)
        var bucket = cachedComments[taskId] ?? []
        bucket.removeAll { $0.id == comment.id }
        bucket.append(comment)
        cachedComments[taskId] = bucket
        refreshOutboxCounts()
        return comment
    }

    private static func attachFile(
        taskId: String, staged: PendingAttachment, content: String, commentId: String,
        parentCommentId: String?
    ) -> CoreCommand {
        var command = CoreCommand(kind: "attachFile", [
            "taskId": .value(taskId), "path": .value(staged.localPath), "content": .value(content),
            "fileId": .value(staged.tempFileId), "name": .value(staged.fileName),
            "mimeType": .value(staged.mimeType), "clientRequestId": .value(commentId),
        ])
        command.set("parentCommentId", parentCommentId)
        return command
    }

    /// Edit a comment — at once in the thread, to the server when it can.
    func updateComment(id: String, content: String) async throws -> Comment {
        try await core.run(CoreCommand(kind: "editComment", ["commentId": .value(id), "content": .value(content)]))
        var edited: Comment?
        for (taskId, comments) in cachedComments {
            guard let index = comments.firstIndex(where: { $0.id == id }) else { continue }
            var comment = comments[index]
            comment.content = content
            comment.updatedAt = Date()
            cachedComments[taskId]?[index] = comment
            edited = comment
        }
        refreshOutboxCounts()
        guard let edited else {
            throw NSError(domain: "CommentService", code: 404, userInfo: [NSLocalizedDescriptionKey: "Comment not found"])
        }
        return edited
    }

    /// Delete a comment — at once from the thread, from the server when it can.
    func deleteComment(id: String) async throws {
        try await core.run(CoreCommand(kind: "deleteComment", ["commentId": .value(id)]))
        for taskId in cachedComments.keys {
            cachedComments[taskId]?.removeAll { $0.id == id }
        }
        refreshOutboxCounts()
    }

    // MARK: - Delivery

    /// Send what is waiting now rather than at the delivery loop's next turn.
    func syncPendingComments() async throws {
        try await core.run(CoreCommand(kind: "drain"))
        refreshOutboxCounts()
    }

    /// Give writes the server refused another go.
    func retryFailedOperations() async {
        try? await syncPendingComments()
    }

    /// Counts the core already gave (a delivery carries them), shown without asking again.
    func showOutboxCounts(pending: Int, failed: Int) {
        if pending != pendingOperationsCount { pendingOperationsCount = pending }
        if failed != failedOperationsCount { failedOperationsCount = failed }
    }

    private func refreshOutboxCounts() {
        struct Stats: Decodable { let pending: Int; let running: Int; let failed: Int }
        _Concurrency.Task {
            guard let stats = try? await core.run(CoreCommand(kind: "outboxStats"), as: Stats.self) else { return }
            pendingOperationsCount = stats.pending + stats.running
            failedOperationsCount = stats.failed
        }
    }

    /// Clear what the views read (sign-out; the core wipes its own cache there too).
    func clearCache() {
        cachedComments = [:]
        typingAgent = [:]
        lastFetchTime = [:]
        tempCommentIdMapping = [:]
    }
}

// MARK: - Response Models

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
