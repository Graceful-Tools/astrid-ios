import Foundation

/// "Hand back": the quick way to return a task to whoever asked you something on it (ADEV-360).
///
/// Jon's report: answering a question in a task's comments left the task assigned to him, so the
/// agent (or person) who asked never got it back without a trip to the assignee picker. This rule
/// says when the comment area offers the one-tap way back, and to whom; the views only draw it.
///
/// - Offered only on an open task assigned to YOU — handing back something that isn't yours is
///   reassignment, which the assignee picker already does.
/// - The asker is the author of the newest comment written by someone else. System lines (no
///   author) and your own replies are skipped, so it still points at the asker after you answer.
/// - An agent goes back in **Ready**: an agent's queue is Ready tasks assigned to it, so assigning
///   without Ready would hand it back to an agent that never looks. A person keeps whatever column
///   the task is in.
enum ReplyHandBack {

    /// Who the task goes back to.
    struct Target: Equatable {
        let userId: String
        let name: String
        let isAgent: Bool

        /// The board state the hand-back writes: Ready for an agent, unchanged (nil) for a person.
        var statusRole: String? { isAgent ? "ready" : nil }
    }

    static func target(assigneeId: String?, currentUserId: String?, completed: Bool,
                       comments: [Comment]) -> Target? {
        guard !completed, let me = currentUserId, !me.isEmpty, assigneeId == me else { return nil }
        // Oldest first by time; the core's order breaks ties, so an untimed row keeps its place.
        let ordered = comments.enumerated().sorted { a, b in
            let ta = a.element.createdAt ?? .distantPast, tb = b.element.createdAt ?? .distantPast
            return ta == tb ? a.offset < b.offset : ta < tb
        }.map(\.element)
        guard let asked = ordered.last(where: { comment in
            guard let author = comment.authorId, !author.isEmpty else { return false }
            return author != me
        }), let askerId = asked.authorId else { return nil }
        return Target(userId: askerId,
                      name: asked.author?.displayName ?? asked.authorDisplayName ?? askerId,
                      isAgent: asked.author?.isAIAgent == true)
    }

    /// The task, reassigned to `target` — one edit through the service layer, so it journals and
    /// goes out offline like any other.
    @MainActor
    @discardableResult
    static func perform(_ target: Target, taskId: String,
                        service: TaskService = .shared) async throws -> Task {
        try await service.updateTask(taskId: taskId, assigneeId: target.userId,
                                     statusRole: target.statusRole)
    }
}
