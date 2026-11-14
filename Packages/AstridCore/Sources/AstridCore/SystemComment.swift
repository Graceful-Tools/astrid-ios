import Foundation

extension CoreRules {
    /// Whether a comment is the server's ("marked this as complete") rather than a person's —
    /// astrid-core's `commentVisibility` answer's `isSystem` (AITD-667).
    ///
    /// No author and no GitHub login, and never while `offline`: a cached comment can come back
    /// without its `authorId`, so offline "no author" proves nothing. Never throws: a question the
    /// core cannot read answers `false`, so the comment is shown rather than hidden.
    public static func isSystemComment(authorId: String?, remoteAuthorLogin: String?,
                                       offline: Bool) -> Bool {
        let request = SystemCommentRequest(
            comment: .init(authorId: authorId, remoteAuthorLogin: remoteAuthorLogin),
            offline: offline)
        return (try? ask(request, as: SystemCommentAnswer.self))?.isSystem ?? false
    }
}

private struct SystemCommentRequest: Encodable {
    /// Only the two fields the rule reads; `id` and `content` because the wire requires them.
    struct Comment: Encodable {
        let id = ""
        let content = ""
        let authorId: String?
        let remoteAuthorLogin: String?
    }

    let kind = "commentVisibility"
    let comment: Comment
    let offline: Bool
}

private struct SystemCommentAnswer: Decodable {
    let isSystem: Bool
}
