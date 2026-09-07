import Foundation

/// How a comment thread absorbs one incoming comment — from the server, from SSE, or from the
/// user's own optimistic post (AITD-331).
///
/// The rules moved here because the server stopped excluding a comment's author from the SSE
/// fan-out. It used to do `userIds.delete(authorId)` on the theory that the author already sees
/// their own comment optimistically — true of the one device that posted it, false for every
/// other device that user has open. **A user is not a device.** So this app now receives
/// `comment_created` / `comment_deleted` for comments it wrote itself, where before it received
/// none, and every rule below has to survive its own echo.
///
/// The one rule that makes that safe: **dedupe on comment id, never on author.** Skipping events
/// whose author is the current user keeps missing every comment that user writes on another
/// device — the original bug — and gives no protection against the echo either. Ignoring a
/// comment whose id is already in the thread solves both at once.
///
/// Extracted from `CommentSectionViewEnhanced` (1,898 lines) for the same reason `CommentVisibility`
/// was: the view held five separate copies of these rules — three SSE handlers and two inline row
/// callbacks — which is five chances for the next edit to fix one and miss four.
enum CommentThread {

    // MARK: - Shape

    /// Groups a flat response into one level of replies.
    ///
    /// `GET /api/v1/tasks/:id` returns every comment as a top-level row carrying `parentCommentId`;
    /// there is no `replies` relation in the response. The rows render nested, so somebody has to
    /// build the tree, and until now nobody did: a reply appeared nested when you wrote it and
    /// jumped back to the top level after the next refresh.
    ///
    /// **A reply whose parent is absent stays visible at the top level.** The response is capped at
    /// 500 rows, so the parent can simply be missing — dropping the orphan would silently delete
    /// somebody's words from the thread.
    static func nest(_ flat: [Comment]) -> [Comment] {
        let byId = Dictionary(flat.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        var roots: [Comment] = []
        var rootIndex: [String: Int] = [:]
        var pendingReplies: [(parent: String, reply: Comment)] = []

        for comment in flat {
            var row = comment
            row.replies = nil
            if let parentId = row.parentCommentId, byId[parentId] != nil, parentId != row.id {
                pendingReplies.append((parentId, row))
            } else {
                rootIndex[row.id] = roots.count
                roots.append(row)
            }
        }

        for (parentId, reply) in pendingReplies {
            // A reply to a reply hangs off the top-level ancestor: the row view renders exactly one
            // level, so a deeper tree would be built and never drawn.
            guard let index = rootIndex[rootOf(parentId, in: byId)] else {
                roots.append(reply)   // parent was cut off by the response cap — keep it visible
                continue
            }
            roots[index].replies = (roots[index].replies ?? []) + [reply]
        }
        return roots
    }

    /// Every comment in the thread, replies included, as one list.
    static func flatten(_ thread: [Comment]) -> [Comment] {
        thread.flatMap { comment -> [Comment] in
            var row = comment
            let replies = row.replies ?? []
            row.replies = nil
            return [row] + replies
        }
    }

    // MARK: - Applying one event

    /// Inserts `incoming`, or replaces the row that already carries its id.
    ///
    /// Idempotent by construction, which is what makes the self-echo harmless: the second delivery
    /// of a comment replaces the first rather than appending beside it.
    static func upsert(_ incoming: Comment, into thread: [Comment]) -> [Comment] {
        var result = thread

        if let index = result.firstIndex(where: { $0.id == incoming.id }) {
            result[index] = carryingLocalExtras(incoming, over: result[index])
            return result
        }
        for i in result.indices {
            guard var replies = result[i].replies,
                  let j = replies.firstIndex(where: { $0.id == incoming.id }) else { continue }
            replies[j] = carryingLocalExtras(incoming, over: replies[j])
            result[i].replies = replies
            return result
        }

        var row = incoming
        row.replies = nil
        if let parentId = row.parentCommentId,
           let index = result.firstIndex(where: { $0.id == parentId || ($0.replies?.contains { $0.id == parentId } ?? false) }) {
            result[index].replies = (result[index].replies ?? []) + [row]
        } else {
            result.append(row)      // an orphan reply is still somebody's words — show it
        }
        return result
    }

    /// Collapses the optimistic row this server comment settles, then upserts the server comment.
    ///
    /// Two steps, not one. With the author now in the audience the echo can arrive **before** the
    /// POST response, and upserting by id alone would leave the same comment in the thread twice —
    /// once as `temp_…` and once under its real id.
    static func settle(_ server: Comment, in thread: [Comment]) -> [Comment] {
        guard let optimistic = optimisticMatch(for: server, in: thread) else {
            return upsert(server, into: thread)
        }
        let local = flatten(thread).first { $0.id == optimistic }
        return upsert(carryingLocalExtras(server, over: local), into: remove(id: optimistic, from: thread))
    }

    /// Removes a comment wherever it sits. A no-op when it is already gone, so a delete that
    /// arrives twice — or after the local optimistic removal — changes nothing.
    static func remove(id: String, from thread: [Comment]) -> [Comment] {
        var result = thread.filter { $0.id != id }
        for i in result.indices {
            result[i].replies?.removeAll { $0.id == id }
            if result[i].replies?.isEmpty == true { result[i].replies = nil }
        }
        return result
    }

    /// Applies an edit to a comment wherever it sits, top-level or reply.
    ///
    /// Content and `updatedAt` only: the server row can arrive without the author or the secure
    /// files this device already resolved, and an edit must not blank them.
    static func applyEdit(_ edited: Comment, to thread: [Comment]) -> [Comment] {
        applyEdit(id: edited.id, content: edited.content, updatedAt: edited.updatedAt, to: thread)
    }

    /// The same edit from a local row action, where only the new text is known.
    static func applyEdit(id: String, content: String, updatedAt: Date?, to thread: [Comment]) -> [Comment] {
        var result = thread
        if let index = result.firstIndex(where: { $0.id == id }) {
            result[index].content = content
            result[index].updatedAt = updatedAt
            return result
        }
        for i in result.indices {
            if let j = result[i].replies?.firstIndex(where: { $0.id == id }) {
                result[i].replies?[j].content = content
                result[i].replies?[j].updatedAt = updatedAt
                return result
            }
        }
        return result
    }

    // MARK: - Matching an optimistic row

    /// The id of the optimistic row `server` settles, if the thread is still holding one.
    ///
    /// `clientRequestId` is the real answer — the server echoes back the id this device sent, so
    /// the match is identity. The content fallback exists only for a temp row queued by an older
    /// build, which sent an Outbox UUID the display row never knew; it is deliberately narrow
    /// (author AND parent AND non-empty content) because an attachment-only comment has EMPTY
    /// content, and matching on that collapses one attachment onto another's row.
    static func optimisticMatch(for server: Comment, in thread: [Comment]) -> String? {
        let pending = flatten(thread).filter { $0.id.hasPrefix("temp_") }

        if let requestId = server.clientRequestId,
           let exact = pending.first(where: { $0.id == requestId }) {
            return exact.id
        }
        guard !server.content.isEmpty else { return nil }
        return pending.first {
            $0.content == server.content
                && $0.authorId == server.authorId
                && $0.parentCommentId == server.parentCommentId
        }?.id
    }

    // MARK: - Helpers

    /// The server row, keeping what this device resolved locally and the server did not send.
    private static func carryingLocalExtras(_ incoming: Comment, over local: Comment?) -> Comment {
        var row = incoming
        row.replies = local?.replies ?? incoming.replies
        if row.secureFiles?.isEmpty ?? true, let files = local?.secureFiles, !files.isEmpty {
            row.secureFiles = files
        }
        if row.author == nil, let author = local?.author {
            row.author = author
            row.authorId = row.authorId ?? author.id
        }
        return row
    }

    /// Walks up to the top-level ancestor of `id`, so a reply-to-a-reply lands on the row that is
    /// actually drawn. Bounded, because a cycle in the data must not hang the thread.
    private static func rootOf(_ id: String, in byId: [String: Comment]) -> String {
        var current = id
        for _ in 0..<32 {
            guard let parent = byId[current]?.parentCommentId, parent != current, byId[parent] != nil else {
                return current
            }
            current = parent
        }
        return current
    }
}
