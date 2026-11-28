import SwiftUI

/// The one blue button in a task's comment composer, on iOS and the Mac (ADEV-360): **Reply,
/// Reassign & Ready**. Jon: "we want a button on all platform. Kind of like 'send & Archive' with
/// Gmail." One tap posts what's typed and hands the task back to whoever asked.
///
/// Draws nothing unless `ReplyHandBack` finds someone to hand back to, so a composer can always
/// include it. The composer owns the draft: on a tap it hands over the reply (or nil when nothing
/// is typed) through `onTap`, and `ReplyHandBack.replyThenHandBack` sequences the two writes.
struct ReplyHandBackButton: View {
    let taskId: String
    /// Something is typed or attached: the button posts it too.
    let hasReply: Bool
    /// Tapped, with who the task goes back to. The composer posts its draft, then hands back.
    let onTap: (ReplyHandBack.Target) -> Void
    var busy = false

    @ObservedObject private var taskService = TaskService.shared
    @ObservedObject private var commentService = CommentService.shared

    var body: some View {
        if let target {
            Button { onTap(target) } label: {
                VStack(spacing: 0) {
                    Text(NSLocalizedString(ReplyHandBack.titleKey(for: target, hasReply: hasReply), comment: ""))
                        .font(Theme.Typography.headline())
                    Text(String(format: NSLocalizedString("comments.hand_back_to", comment: "to <name>"), target.name))
                        .font(Theme.Typography.caption1())
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .disabled(busy)
            .accessibilityLabel(Text(String(format: NSLocalizedString("comments.hand_back", comment: ""), target.name)))
            .accessibilityIdentifier("comment.handBack")
        }
    }

    private var target: ReplyHandBack.Target? {
        guard let task = taskService.tasks.first(where: { $0.id == taskId }) else { return nil }
        return ReplyHandBack.target(assigneeId: task.assigneeId,
                                    currentUserId: AuthManager.shared.userId,
                                    completed: task.completed,
                                    comments: commentService.cachedComments[taskId] ?? [])
    }
}

/// What a composer needs from its task view to draw the button: the task, how that view posts a
/// comment (attachments and offline included), and where the reassigned task goes back to.
struct ReplyHandBackHost {
    let taskId: String
    let post: @MainActor (_ content: String, _ type: Comment.CommentType, _ fileIds: [String]) async -> Void
    var onHandedBack: (Task) -> Void = { _ in }

    /// Post the draft if there is one, then hand back. A refused hand-back is logged; the reply
    /// is already posted and the task simply stays with you.
    @MainActor
    func send(_ draft: (content: String, type: Comment.CommentType, fileIds: [String])?,
              to target: ReplyHandBack.Target) async {
        do {
            try await ReplyHandBack.replyThenHandBack(
                target,
                reply: draft.map { d in { await post(d.content, d.type, d.fileIds) } },
                handBack: { t in onHandedBack(try await ReplyHandBack.perform(t, taskId: taskId)) })
        } catch {
            AppLog.debug("❌ [ReplyHandBack] Hand back refused: \(error)")
        }
    }
}
