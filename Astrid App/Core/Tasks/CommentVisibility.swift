import Foundation

/// Which comments a thread shows, and what counts as a system comment (Task 946c41c6).
///
/// First extraction out of `CommentSectionViewEnhanced` (1,898 lines, previously untested). The
/// rule looks trivial — a system comment is one with no author — and it is nearly right. The part
/// worth protecting is the offline caveat: a cached comment can come back without its `authorId`,
/// so offline "no author" stops being evidence of anything. Applying the plain rule then would
/// hide the user's own words from their own thread, offline, which is exactly when they cannot
/// check against the server.
///
/// The view had this correct in three separate places — the displayed list, the count beside the
/// header, and each row's styling — which is three chances for the next edit to get one wrong.
enum CommentVisibility {

    /// Is this a system comment ("marked complete", "moved to …") rather than someone's message?
    ///
    /// A GitHub commenter with no Astrid account has no `authorId` either, but carries
    /// `remoteAuthorLogin` — a person, not the server (AITD-517, web's `isSystemComment`).
    static func isSystem(authorId: String?, remoteAuthorLogin: String? = nil, isOffline: Bool) -> Bool {
        guard !isOffline else { return false }
        return authorId == nil && remoteAuthorLogin == nil
    }

    static func isSystem(_ comment: Comment, isOffline: Bool) -> Bool {
        isSystem(authorId: comment.authorId, remoteAuthorLogin: comment.remoteAuthorLogin,
                 isOffline: isOffline)
    }

    /// The comments to render, in their original order.
    static func displayed(_ comments: [Comment], showSystem: Bool, isOffline: Bool) -> [Comment] {
        guard !isOffline, !showSystem else { return comments }
        return comments.filter { !isSystem($0, isOffline: isOffline) }
    }

    /// The number beside the header. Derived from `displayed` rather than recomputed, so the count
    /// and the list cannot disagree.
    static func count(_ comments: [Comment], showSystem: Bool, isOffline: Bool) -> Int {
        displayed(comments, showSystem: showSystem, isOffline: isOffline).count
    }
}
