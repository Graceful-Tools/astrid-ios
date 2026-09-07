import Foundation

/// Whether an incoming comment should raise a local notification on this device (AITD-331).
///
/// This used to be belt-and-braces. The server excluded a comment's author from the SSE fan-out,
/// so a comment you wrote never came back to you and the "not mine" check could never fire. That
/// exclusion is gone — it was wrong, because it also hid your comments from your OTHER devices —
/// and the check is now the only thing standing between you and a notification for every comment
/// you write, on every device you have open.
enum CommentNotificationPolicy {

    /// - Parameters:
    ///   - authorId: the comment's author. `nil` for a system comment ("marked complete", …).
    ///   - currentUserId: the signed-in user on this device.
    static func shouldNotify(authorId: String?,
                             currentUserId: String,
                             isMentioned: Bool,
                             isAssignee: Bool) -> Bool {
        guard authorId != currentUserId else { return false }
        return isMentioned || isAssignee
    }
}
