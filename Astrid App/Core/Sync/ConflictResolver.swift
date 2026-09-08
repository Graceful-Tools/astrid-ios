import Foundation

/// Handles conflict resolution when local and server data differ
/// Uses sensible defaults to auto-resolve without user intervention
class ConflictResolver {
    static let shared = ConflictResolver()

    private init() {}

    // MARK: - Conflict Detection

    /// Check if a local task conflicts with a server task
    func hasConflict(local: Task, server: Task) -> Bool {
        // No conflict if either is missing timestamp
        guard let localUpdated = local.updatedAt, let serverUpdated = server.updatedAt else {
            return false
        }

        // Conflict if both were modified after last sync
        return localUpdated != serverUpdated
    }

    // MARK: - Task Resolution

    /// Resolve conflict between local and server task versions
    /// Returns the merged task with conflicts auto-resolved
    func resolveTaskConflict(local: Task, server: Task) -> Task {
        // If no real conflict, prefer server version
        guard hasConflict(local: local, server: server) else {
            return server
        }

        AppLog.debug("⚔️ [ConflictResolver] Resolving conflict for task: \(local.id)")

        // Start with server version as base
        var resolved = server

        // Rule 1: Completion status - LOCAL WINS (user intent takes priority)
        if local.completed != server.completed {
            resolved = resolveCompletion(local: local, server: server, base: resolved)
        }

        // Rule 2: Title/Description - MOST RECENT WINS
        resolved = resolveContent(local: local, server: server, base: resolved)

        // Rule 3: Due date - MOST RECENT WINS
        resolved = resolveDueDate(local: local, server: server, base: resolved)

        // Rule 4: Priority - MOST RECENT WINS
        resolved = resolvePriority(local: local, server: server, base: resolved)

        // Rule 5: Lists/Assignment - SERVER WINS (collaborative changes)
        // Already using server version for these

        AppLog.debug("✅ [ConflictResolver] Conflict resolved for task: \(resolved.id)")
        return resolved
    }

    // MARK: - Field-Level Resolution

    /// Resolve completion status conflict - LOCAL WINS
    private func resolveCompletion(local: Task, server: Task, base: Task) -> Task {
        // If user completed the task locally, honor that
        if local.completed && !server.completed {
            AppLog.debug("  → Completion: local (completed) wins")
            return Task(
                id: base.id,
                title: base.title,
                description: base.description,
                assigneeId: base.assigneeId,
                assignee: base.assignee,
                creatorId: base.creatorId,
                creator: base.creator,
                dueDateTime: base.dueDateTime,
                isAllDay: base.isAllDay,
                reminderTime: base.reminderTime,
                reminderSent: base.reminderSent,
                reminderType: base.reminderType,
                repeating: base.repeating,
                repeatingData: base.repeatingData,
                repeatFrom: base.repeatFrom,
                occurrenceCount: base.occurrenceCount,
                priority: base.priority,
                lists: base.lists,
                listIds: base.listIds,
                isPrivate: base.isPrivate,
                completed: true,  // LOCAL WINS
                attachments: base.attachments,
                comments: base.comments,
                createdAt: base.createdAt,
                updatedAt: Date(),
                originalTaskId: base.originalTaskId,
                sourceListId: base.sourceListId
            )
        } else {
            AppLog.debug("  → Completion: server wins")
            return base
        }
    }

    /// Resolve content (title/description) conflict - MOST RECENT WINS
    private func resolveContent(local: Task, server: Task, base: Task) -> Task {
        var result = base

        let localUpdated = local.updatedAt ?? .distantPast
        let serverUpdated = server.updatedAt ?? .distantPast

        // Check if title changed and local is newer
        if local.title != server.title && localUpdated > serverUpdated {
            AppLog.debug("  → Title: local wins (more recent)")
            result = Task(
                id: result.id,
                title: local.title,
                description: result.description,
                assigneeId: result.assigneeId,
                assignee: result.assignee,
                creatorId: result.creatorId,
                creator: result.creator,
                dueDateTime: result.dueDateTime,
                isAllDay: result.isAllDay,
                reminderTime: result.reminderTime,
                reminderSent: result.reminderSent,
                reminderType: result.reminderType,
                repeating: result.repeating,
                repeatingData: result.repeatingData,
                repeatFrom: result.repeatFrom,
                occurrenceCount: result.occurrenceCount,
                priority: result.priority,
                lists: result.lists,
                listIds: result.listIds,
                isPrivate: result.isPrivate,
                completed: result.completed,
                attachments: result.attachments,
                comments: result.comments,
                createdAt: result.createdAt,
                updatedAt: Date(),
                originalTaskId: result.originalTaskId,
                sourceListId: result.sourceListId
            )
        }

        // Check if description changed and local is newer
        if local.description != server.description && localUpdated > serverUpdated {
            AppLog.debug("  → Description: local wins (more recent)")
            result = Task(
                id: result.id,
                title: result.title,
                description: local.description,
                assigneeId: result.assigneeId,
                assignee: result.assignee,
                creatorId: result.creatorId,
                creator: result.creator,
                dueDateTime: result.dueDateTime,
                isAllDay: result.isAllDay,
                reminderTime: result.reminderTime,
                reminderSent: result.reminderSent,
                reminderType: result.reminderType,
                repeating: result.repeating,
                repeatingData: result.repeatingData,
                repeatFrom: result.repeatFrom,
                occurrenceCount: result.occurrenceCount,
                priority: result.priority,
                lists: result.lists,
                listIds: result.listIds,
                isPrivate: result.isPrivate,
                completed: result.completed,
                attachments: result.attachments,
                comments: result.comments,
                createdAt: result.createdAt,
                updatedAt: Date(),
                originalTaskId: result.originalTaskId,
                sourceListId: result.sourceListId
            )
        }

        return result
    }

    /// Resolve due date conflict - MOST RECENT WINS
    private func resolveDueDate(local: Task, server: Task, base: Task) -> Task {
        let localUpdated = local.updatedAt ?? .distantPast
        let serverUpdated = server.updatedAt ?? .distantPast

        if (local.dueDateTime != server.dueDateTime || local.isAllDay != server.isAllDay) && localUpdated > serverUpdated {
            AppLog.debug("  → Due date: local wins (more recent)")
            return Task(
                id: base.id,
                title: base.title,
                description: base.description,
                assigneeId: base.assigneeId,
                assignee: base.assignee,
                creatorId: base.creatorId,
                creator: base.creator,
                dueDateTime: local.dueDateTime,
                isAllDay: local.isAllDay,
                reminderTime: base.reminderTime,
                reminderSent: base.reminderSent,
                reminderType: base.reminderType,
                repeating: base.repeating,
                repeatingData: base.repeatingData,
                repeatFrom: base.repeatFrom,
                occurrenceCount: base.occurrenceCount,
                priority: base.priority,
                lists: base.lists,
                listIds: base.listIds,
                isPrivate: base.isPrivate,
                completed: base.completed,
                attachments: base.attachments,
                comments: base.comments,
                createdAt: base.createdAt,
                updatedAt: Date(),
                originalTaskId: base.originalTaskId,
                sourceListId: base.sourceListId
            )
        }

        return base
    }

    /// Resolve priority conflict - MOST RECENT WINS
    private func resolvePriority(local: Task, server: Task, base: Task) -> Task {
        let localUpdated = local.updatedAt ?? .distantPast
        let serverUpdated = server.updatedAt ?? .distantPast

        if local.priority != server.priority && localUpdated > serverUpdated {
            AppLog.debug("  → Priority: local wins (more recent)")
            return Task(
                id: base.id,
                title: base.title,
                description: base.description,
                assigneeId: base.assigneeId,
                assignee: base.assignee,
                creatorId: base.creatorId,
                creator: base.creator,
                dueDateTime: base.dueDateTime,
                isAllDay: base.isAllDay,
                reminderTime: base.reminderTime,
                reminderSent: base.reminderSent,
                reminderType: base.reminderType,
                repeating: base.repeating,
                repeatingData: base.repeatingData,
                repeatFrom: base.repeatFrom,
                occurrenceCount: base.occurrenceCount,
                priority: local.priority,
                lists: base.lists,
                listIds: base.listIds,
                isPrivate: base.isPrivate,
                completed: base.completed,
                attachments: base.attachments,
                comments: base.comments,
                createdAt: base.createdAt,
                updatedAt: Date(),
                originalTaskId: base.originalTaskId,
                sourceListId: base.sourceListId
            )
        }

        return base
    }

    // MARK: - Comment Resolution

    /// Resolve comment conflicts - MERGE (keep both if concurrent creates)
    func resolveCommentConflicts(local: [Comment], server: [Comment]) -> [Comment] {
        var merged: [String: Comment] = [:]

        // Add all server comments
        for comment in server {
            merged[comment.id] = comment
        }

        // Merge local comments (add new ones, keep local if newer)
        for comment in local {
            if let existing = merged[comment.id] {
                // Both exist - keep most recent
                let localUpdated = comment.updatedAt ?? comment.createdAt ?? .distantPast
                let serverUpdated = existing.updatedAt ?? existing.createdAt ?? .distantPast

                if localUpdated > serverUpdated {
                    merged[comment.id] = comment
                }
            } else if comment.id.hasPrefix("temp_") {
                // Local-only comment (pending sync) - keep it
                merged[comment.id] = comment
            }
        }

        return Array(merged.values).sorted {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
    }
}
