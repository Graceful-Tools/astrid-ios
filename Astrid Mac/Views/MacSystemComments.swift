//  MacSystemComments.swift
//  Astrid for Mac — hiding status chatter in the comment thread (Task 9c24d16c).
//
//  A comment with no author is the system talking ("marked complete", "moved to …"). iOS
//  (CommentSectionViewEnhanced) hides those by default and offers a toggle only when there are
//  any; the Mac showed every one of them, always, burying the actual conversation.
//
//  The offline exception is iOS's and is deliberate: cached comments can come back WITHOUT an
//  authorId, so filtering while disconnected would empty the thread — a much worse failure than
//  showing a few status lines.

#if os(macOS)
import Foundation

enum MacSystemComments {
    static func isSystem(_ comment: Comment) -> Bool { comment.authorId == nil }

    static func displayed(_ comments: [Comment], showingSystem: Bool, isOffline: Bool) -> [Comment] {
        guard !isOffline, !showingSystem else { return comments }
        return comments.filter { !isSystem($0) }
    }

    static func count(_ comments: [Comment], showingSystem: Bool, isOffline: Bool) -> Int {
        displayed(comments, showingSystem: showingSystem, isOffline: isOffline).count
    }

    /// No system comments (or offline, where they are all shown anyway) → no toggle: an affordance
    /// that reveals nothing is noise.
    static func showsToggle(_ comments: [Comment], isOffline: Bool) -> Bool {
        !isOffline && comments.contains(where: isSystem)
    }

    static func toggleTitle(showingSystem: Bool) -> String {
        NSLocalizedString(showingSystem ? "mac.system_comments_hide" : "mac.system_comments_show",
                          comment: "")
    }
}

/// The other half of the rule above: what the Mac must SEND so its own comments survive it.
///
/// `isSystem` hides anything without an authorId, so a comment posted without one is filtered
/// straight back out of the thread — the comment you just typed disappears until the Outbox
/// syncs and a refresh returns the server copy, which does carry an author (task a3f868b4).
enum MacCommentPost {
    /// The author a comment posted from this Mac must carry.
    static func authorId(currentUserId: String?) -> String? { currentUserId }

    /// Whether a comment posted with this author will actually be visible in the thread.
    static func isVisibleInThread(authorId: String?) -> Bool { authorId != nil }
}
#endif
