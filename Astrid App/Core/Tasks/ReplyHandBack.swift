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

    /// - `assignedBy`/`assignedAt`: who gave the task its current assignee and when (the server's
    ///   `TaskEvent` trail, ADEV-393). An agent that assigns you a task without a word is still
    ///   the one to hand it back to.
    static func target(assigneeId: String?, currentUserId: String?, completed: Bool,
                       comments: [Comment], assignedBy: User? = nil, assignedAt: Date? = nil) -> Target? {
        guard !completed, let me = currentUserId, !me.isEmpty, assigneeId == me else { return nil }
        // Oldest first by time; the core's order breaks ties, so an untimed row keeps its place.
        let ordered = comments.enumerated().sorted { a, b in
            let ta = a.element.createdAt ?? .distantPast, tb = b.element.createdAt ?? .distantPast
            return ta == tb ? a.offset < b.offset : ta < tb
        }.map(\.element)
        var asked: (target: Target, at: Date)?
        for comment in ordered.reversed() {
            if let found = asker(of: comment, me: me) {
                asked = (found, comment.createdAt ?? .distantPast)
                break
            }
        }
        // The assignment, when someone else made it, and it is at least as new as that comment.
        if let by = assignedBy, !by.id.isEmpty, by.id != me {
            let at = assignedAt ?? .distantPast
            if asked == nil || at >= asked!.at {
                return Target(userId: by.id, name: by.displayName, isAgent: by.isAIAgent == true)
            }
        }
        return asked?.target
    }

    /// Who a comment counts as asking: an agent's `AGENT-HANDBACK: <mailbox>` line names it
    /// whoever the comment is signed as (an agent posting with its owner's credentials signs as
    /// them, ADEV-393); otherwise its author, unless that is you or nobody (a system line).
    private static func asker(of comment: Comment, me: String) -> Target? {
        if let mailbox = handbackMailbox(comment.content) {
            let id = "ai-agent-\(mailbox)"
            if id == me { return nil }
            let name = comment.authorId == id
                ? (comment.author?.displayName ?? comment.authorDisplayName ?? id)
                : mailbox.prefix(1).uppercased() + mailbox.dropFirst() + " Agent"
            return Target(userId: id, name: name, isAgent: true)
        }
        guard let author = comment.authorId, !author.isEmpty, author != me else { return nil }
        return Target(userId: author,
                      name: comment.author?.displayName ?? comment.authorDisplayName ?? author,
                      isAgent: comment.author?.isAIAgent == true)
    }

    /// The mailbox an `AGENT-HANDBACK: <mailbox>` line names (astrid-core `questions::marker_mailbox`).
    static func handbackMailbox(_ content: String) -> String? {
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("AGENT-HANDBACK:") else { continue }
            let mailbox = trimmed.dropFirst("AGENT-HANDBACK:".count).trimmingCharacters(in: .whitespaces)
            if !mailbox.isEmpty { return mailbox }
        }
        return nil
    }

    /// The words on the one blue button (Jon: "like Gmail's Send & Archive"): what a tap does,
    /// given whether something is typed. A person keeps the column, so their button never says Ready.
    static func titleKey(for target: Target, hasReply: Bool) -> String {
        switch (hasReply, target.isAgent) {
        case (true, true): return "comments.reply_reassign_ready"
        case (false, true): return "comments.reassign_ready"
        case (true, false): return "comments.reply_reassign"
        case (false, false): return "comments.reassign"
        }
    }

    /// One tap: the reply first, then the hand-back, so whoever gets the task finds the answer
    /// already there when it lands in their queue. Nothing typed is a plain hand-back. A reply
    /// that fails stops it: the task never goes back without the answer it was waiting for.
    @MainActor
    static func replyThenHandBack(_ target: Target, reply: (() async throws -> Void)?,
                                  handBack: (Target) async throws -> Void) async throws {
        if let reply { try await reply() }
        try await handBack(target)
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
