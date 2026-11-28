import SwiftUI

/// "Hand back to <asker>" above a task's comment composer, on iOS and the Mac (ADEV-360).
///
/// Draws nothing unless `ReplyHandBack` finds someone to hand back to, so a composer can always
/// include it. The rule decides who and which state; this only draws the button and makes the
/// one service call.
struct ReplyHandBackButton: View {
    let taskId: String
    /// The task as the hand-back left it, for a surface holding its own copy of the assignee.
    var onHandedBack: ((Task) -> Void)? = nil
    @ObservedObject private var taskService = TaskService.shared
    @ObservedObject private var commentService = CommentService.shared
    @State private var sending = false

    var body: some View {
        if let target {
            Button {
                handBack(to: target)
            } label: {
                Label(String(format: NSLocalizedString("comments.hand_back", comment: "Hand back to <name>"),
                             target.name),
                      systemImage: "arrowshape.turn.up.left")
                    .font(.caption)
                    .lineLimit(1)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
            .disabled(sending)
            .frame(maxWidth: .infinity, alignment: .leading)
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

    private func handBack(to target: ReplyHandBack.Target) {
        sending = true
        _Concurrency.Task {
            defer { sending = false }
            do {
                let updated = try await ReplyHandBack.perform(target, taskId: taskId)
                onHandedBack?(updated)
            } catch {
                AppLog.debug("❌ [ReplyHandBack] Hand back refused: \(error)")
            }
        }
    }
}
